# Request-input ownership in Pocket Glimmer

Read-only grounding at parent commit `4b92321`. No repository file was changed, no commit or push was made, no model or paid API was called. The code evidence below is source inspection plus the saved Swift tests named; it is not an Xcode build, an iPhone run, or a process-kill test. This container has no Swift toolchain, so the tests were not rerun here.

The parent's one-line claim is slightly mis-cited: `AppModel.swift:198` is the `send` signature; the `guard !busy` is line 199, and `SharedInbox.put` is line 202. The substance is correct.

## Overview

A user request and its payload currently have three independent lifetimes:

1. The visible request is a `ChatItem` in `AppModel.chat`, held only in memory (`AppModel.swift:52`).
2. A confirmation is `ChatItem.pending`, a `PlannedAction?`, also only in memory (`AppModel.swift:14`).
3. Shared text is `SharedInbox.shared.item`, one process-global slot in memory (`core/Sources/PocketCore/Skills.swift:286-302`).

Nothing joins them by identity. `busy` is one `@MainActor` Boolean (`AppModel.swift:62`). A share that arrives while busy is refused before its body is stored. A share that arrives while idle is stored globally and read later, when a skill executes or when the user confirms. That is enough for any later request to overwrite or consume it. A process restart drops all three. The pending recovery implementation will fix effect attempts, but the checked-in contract explicitly classifies the shared-text skills as reply-only and never claimed (`docs/research/EFFECT_RECOVERY_CONTRACT.md:201`), so their payload is outside that recovery. It needs a request-level staging record, not an effect attempt.

## Key Concepts

- **Request identity.** The recovery contract already defines `UserRequestID` (`EFFECT_RECOVERY_CONTRACT.md:210-214`), gives `DraftCard` a `requestID` (`:273-284`), and stores `request_id` on `action_attempts` (`:788-810`). `Assistant.handle` is specified to create one per utterance (`:604`). Today's code creates no such ID in `AppModel.send`.
- **Payload.** The bytes the user supplied: shared email/document text, a voice transcript, or a camera JPEG plus OCR/question. The payload is not the same thing as the planned action. Effect actions carry their arguments in `PlannedAction.args`; the reply-only shared-text skills do not.
- **Admission vs ownership.** `busy` decides whether a request may start now. It is not an owner of the request or its data. Today it is treated as both: a false `busy` drops the request.
- **Reply-only skills.** `email_digest`, `analyze_document`, `translate`, `summarize_text`, `html_viz`, `device_status`, `calendar_find`, and `memory_recall` are reply-only in the contract (`:201`). In the current call paths `email_digest`, `analyze_document`, `html_viz`, and `summarize_text` can read `SharedInbox`; `translate` is reply-only but its required text argument normally stops at a clarify before the shared peek, and the last three do not read it.
- **`take` vs `peek`.** `take` reads and clears under one lock; `peek` reads without clearing (`Skills.swift:292-301`). The planner mixes both, so some requests consume the shared body and some can reuse it repeatedly.
- **Revision.** A request-bound fix needs the payload bytes plus a revision (or equivalent immutable version), and confirmation must claim that revision. A content hash can be an integrity check, but the contract rejects inventing a new identity mechanism (`:58`, `:140`); a monotonic revision plus stored bytes is enough.

## How It Works

### 1. Ingress paths

- **Typed chat.** `ChatView` clears the text field, then starts `Task { await model.send(t) }` (`app/PocketGlimmer/Views/ChatView.swift:30-33`). The send button is disabled while `model.busy` (`:34`), but the clear happens before the async call. If `send` refuses, the refusal is the return value and is ignored; the typed text is not appended to `chat` and is no longer in the field. This is a narrow actor-hop race, but it is a real way to lose typed text.
- **Share text/file.** `HandleTextIntent.perform` builds `body` from `text` or `IntentFile`, extracts PDF/UTF-8 text, checks non-empty, calls `SkillSetup.ensureInstalled()`, derives an utterance, and calls `AppModel.shared.send(ask, sharedText: body, source: source)` (`app/PocketGlimmer/Intents/SkillIntents.swift:57-68`). This is the only production producer of shared text. `openAppWhenRun = true` (`:46`). If `send` refuses, `body` exists only in the intent's local scope and is gone when the intent returns.
- **Ask / action intents.** `AskPocketGlimmerIntent` calls `boot()` then `send(request)` (`Intents.swift:35-46`). `RunSkillIntent` joins its action phrase and `details` and calls `send` without shared text (`SkillIntents.swift:100-113`). Both lose their input on a busy refusal; neither looks at `busy` first.
- **Voice.** `MicButton` records a WAV, then transcribes and calls `model.send(t.text)` (`Capture/VoiceCapture.swift:111-132`). It participates in the same `busy` flag but deletes the recording before its final busy check (details below).
- **Camera.** `CameraButton` opens `GlimpseView`; `GlimpseView.run` calls `MultimodalGate` directly (`Views/GlimpseView.swift:73-95`). It never calls `AppModel.send`, never checks `model.busy` inside `run`, and never sets `model.busy`. The photo, question, and result live in view `@State`. This is a separate request path with no shared admission ownership.
- **Proactive trigger.** `ProactiveTriggerIntent` calls `AppModel.handleTrigger` (`Intents.swift:13-33`), which has no `busy` guard (`AppModel.swift:243-254`). It does not consume `SharedInbox`, but it can interleave with a send and write memory.

### 2. Admission: `AppModel.send`

```swift
func send(_ text: String, sharedText: String? = nil, source: String = "share") async -> String {
    guard !busy else { return "I'm working on another request..." }   // 199
    guard let assistant else { return modelState }                    // 200
    guard !text.trimmed.isEmpty else { return "No request..." }       // 201
    if let sharedText { SharedInbox.shared.put(sharedText, source: source) } // 202
    chat.append(.init(role: .user, text: text))                       // 203
    busy = true; defer { busy = false; refresh() }                    // 204
    await loadScrubberNames()                                         // 205
    let turn = try await assistant.handle(text)                       // 207
    ...
}
```

From line 199 through 204 there is no `await`, so on the `@MainActor` two sends cannot both pass the guard. That is why the single `busy` Boolean looks sufficient. It is not: the refusal at 199 happens before 202, so a busy share/typed/voice/intent request has no stored body. And once 202 has stored a body, `Assistant.handle(text)` receives only the utterance; the payload stays in the global slot.

Two additional consequences:

- If `assistant.handle` throws, the catch at `:226-230` appends an error but does **not** clear the shared body. The body remains usable for 15 minutes and can remain in process memory longer (only `take` clears it), so the next unrelated request can consume it.
- If `handle` returns `.clarify`, `.local`, or `.answer_local` without reaching a shared-text skill, the body also remains. A share can be silently unused and later consumed by something else.

### 3. Interpretation: `Assistant.handle` and `ActionPlanner.execute`

`Assistant.handle(_ utterance:now:)` receives only the utterance (`core/Sources/PocketCore/Assistant.swift:107`). It runs memory/route decisions and then either `toolPath` or `planSkillCore`. Both build a `PlannedAction` whose `args` are extracted from the utterance, and either return `.needsConfirmation(action, prompt:)` or call `execute` immediately (`Assistant.swift:237-249`, `ActionPlanner.swift:133-140`). No request ID or shared payload is passed.

The shared payload is resolved inside `ActionPlanner.execute` (`ActionPlanner.swift:145-183`), at execution time:

| Skill | Line | Read | Consumes? | Consequence |
|---|---|---:|---|---|
| `email_digest` | `:153-157` | `SharedInbox.shared.take()` | yes | First confirm/execute takes the body; a second card gets nil. |
| `analyze_document` | `:158-165` | `SharedInbox.shared.take()?.text ?? ""`, otherwise document picker | yes | A stale share silently replaces the picker and gets analyzed. |
| `html_viz` | `:166-174` | `SharedInbox.shared.peek()` only when `data` is empty or has no numbers | no | A stale share can be charted, then reused again. |
| `.cloudReason` (`summarize_text`; `translate` is normally blocked by its required arg) | `:175-178` | `args["text"] ?? SharedInbox.shared.peek()?.text ?? ""` | no | A stale share can be sent to cloud reasoning repeatedly, under an unrelated request. |

`email_digest` is category `.email`, so `Skill.confirm` is forced true (`Skills.swift:12`, `:100`, `:112`, `:183`) and it always produces a card. `analyze_document`, `html_viz`, `translate`, and `summarize_text` are `.documents`/`.web`, not forced; `confirmBeforeAct` may say `act`, in which case a skill that reaches `execute` consumes or peeks the shared body immediately (`ActionPlanner.swift:135-140`). `translate` normally clarifies on its required text arg before that point. The card prompt is built from `args` only (`ActionPlanner.swift:318-326`); for `email_digest` it is essentially "Summarize my recent emails: 5?" and does not show the shared body. The user cannot verify which payload the confirmation will use.

`reason` can escalate a long shared body to the cloud when online (`ActionPlanner.swift:187-202`). The current privacy repair screens the outgoing text, but the ownership bug can select the wrong text. This is a privacy consequence, not only a content-quality one; the contract keeps these reply-only cloud skills on the old `reason` path until the privacy repair (`EFFECT_RECOVERY_CONTRACT.md:948`).

### 4. Confirmation: `AppModel.confirm` and `Assistant.confirm`

`ChatView` calls `model.confirm(item)` (`ChatView.swift:79-83`). `AppModel.confirm`:

```swift
guard !busy, let assistant,
      let i = chat.firstIndex(...), let a = chat[i].pending else { return } // 234-236
chat[i].pending = nil                                                        // 237
busy = true; defer { busy = false; refresh() }                               // 238
if case .acted(let t) = (try? await assistant.confirm(a)) ?? .acted("Failed") { ... } // 239
```

Three separate problems:

1. **A busy confirmation is silently ignored.** The guard at 234 returns without feedback. The card remains, so it is not lost, but the tap is. The user may think they confirmed.
2. **The card is cleared before execution.** Line 237 removes `pending` before the await. If `assistant.confirm` throws, `try?` becomes `.acted("Failed")`; the card is gone and there is no retry. This is the effect-recovery implementation's territory, but it also applies to reply-only cards.
3. **The payload is read at confirm time.** `Assistant.confirm(a)` calls `execute(a)` (`Assistant.swift:252`), which reaches the `take`/`peek` lines above. The `PlannedAction` contains no shared body and no revision. If another share was put after the card was created, the confirmation summarizes the new text; if the body expired or was taken, it gets nil and returns the "select emails in Mail → Share" message (`ActionPlanner.swift:154-156`).

`AppModel.cancel` clears `pending` and appends "Cancelled." (`AppModel.swift:256-260`) but never clears `SharedInbox`. A cancelled share remains available to a later `email_digest`/`analyze_document` request. This is a straightforward cross-request leak.

### 5. `SharedInbox` lifetime

`SharedInbox` is one static instance with one tuple (`Skills.swift:286-302`):

- `put` overwrites unconditionally (`:291`). There is no rejection, no second slot, no key.
- `peek` returns nil after 900 seconds but does not clear the expired item (`:292-296`). Sensitive text can remain in process memory past its logical expiry until a `take`, overwrite, or process death.
- `take` clears the item, including when it is expired (`:297-301`). A late confirmation therefore destroys the body while reporting that nothing was shared.
- There is no disk I/O, no request ID, no source validation, no revision, and no explicit `clear`.
- The doc comment says `email_digest / analyze_document / html_viz` read it and it "is consumed once" (`:284-285`). The execute branch also has a peek for `summarize_text`/`translate`; `summarize_text` reaches it, `translate` normally does not because its required text arg is clarified first. `html_viz` and cloud-reason use `peek`, so the body is not consumed once. The comment understates the consumers and overstates consumption.

### 6. Voice and camera ownership

**Voice.** `VoiceRecorder.stop` stops the recorder, deletes the temporary WAV (or moves it to `Documents/Recordings` only if the user opted in), and returns the bytes (`Capture/VoiceCapture.swift:51-65`). `MicButton.finish` calls `stop` at `:112`, then checks `!model.busy` at `:114`. If busy, it says "The recording was not sent" and returns; the WAV data is already deleted (unless the optional copy exists), and there is no request record pointing at it. This is a direct, reachable busy drop.

The transcription handoff then does `model.busy = true` (`:119`), awaits the cloud transcription (`:121`), sets `model.busy = false` (`:122`), notes the result, and calls `await model.send(t.text)` (`:127`). On the `@MainActor` there is no suspension point between 122 and the synchronous prefix of `send`, so in today's code another task should not slip into that gap. But the code releases ownership before the next owner is established, and if `send` refuses for any reason the transcript is only in the ignored return; it is not appended as a user bubble and no staged record exists. Treat the release-before-send as a design smell, not a proven race. The proven loss is the line 114 busy drop after deletion.

**Camera.** `CameraButton` disables itself while `model.busy || preparing` (`Capture/CameraGlimpse.swift:64`), but only at the moment of opening. Once `GlimpseView` is open, `run` checks neither `model.busy` nor a shared request state (`GlimpseView.swift:73-95`). It can run concurrently with a typed/voice request, and a typed/voice request can start while it runs. Its payload is local `@State` (`photo`, `question`, `concept`); dismissing the sheet or process death loses it. `record` appends the user bubble only after the cloud result (`:98-114`), so a killed run leaves no chat trace. Camera does not participate in `busy` ownership at all.

## Where Things Live

| Concern | File:line | Owner today | Lifetime |
|---|---|---|---|
| Visible request | `app/PocketGlimmer/AppModel.swift:52`, `:203` | `AppModel.chat` | memory, process |
| Pending effect/read card | `AppModel.swift:14`, `:218` | `ChatItem.pending` | memory, until confirm/cancel |
| Busy flag | `AppModel.swift:62`, `:199`, `:204`, `:238` | `AppModel` | memory, one request |
| Shared text | `core/Sources/PocketCore/Skills.swift:286-302` | global `SharedInbox.shared` | memory, 900 s logical TTL |
| Share producer | `app/PocketGlimmer/Intents/SkillIntents.swift:57-68` | `HandleTextIntent` | intent local + global slot |
| Reply-only consumers | `core/Sources/PocketCore/ActionPlanner.swift:153-178` | `ActionPlanner.execute` | execution/confirm time |
| Effect execution | `AppModel.swift:239` → `Assistant.swift:252` | `Assistant`/`SystemActions` | effect recovery owns migration |
| Voice payload | `Capture/VoiceCapture.swift:51-65`, `:111-132` | `VoiceRecorder` + local `Data` | temp file, deleted on stop |
| Camera payload | `Views/GlimpseView.swift:73-95` | view `@State` | sheet lifetime |
| Durable store | `AppModel.swift:114` (`SQLiteDB`) | memory/telemetry today | disk, no request table |
| Existing shared-text test | `core/Tests/PocketCoreTests/SkillsTests.swift:239-256` | proves confirm-time read | in-memory |
| Existing shared-slot consumption test | `core/Tests/PocketCoreTests/TakeoverRegressionTests.swift:137-159` | proves global-slot consume | in-memory |

## Gotchas

- **Expiry is logical, not physical.** `peek` stops returning an expired item but leaves it in memory (`Skills.swift:292-296`); only `take` clears it. Do not copy this into a durable store.
- **The doc comment is wrong.** It says `email_digest / analyze_document / html_viz` read the slot and it is "consumed once" (`Skills.swift:284-285`). `summarize_text` also peeks, `html_viz` peeks, and `take` vs `peek` gives different consumption.
- **The confirmation is blind to the payload.** `email_digest`'s card is built from `args` only; the shared body is read later inside `execute`. The user cannot see which text will be summarized.
- **A stale share hijacks the document picker.** `analyze_document` calls `take()` before opening `DocumentPicker` (`ActionPlanner.swift:159-162`); an unrelated share means the picker never opens.
- **`source` is not an ownership tag.** It is stored and returned but no consumer uses it to decide whether the payload belongs to the request.
- **Cancel and failure do not clear the slot.** `AppModel.cancel` clears the card only; a throw in `handle` leaves the body. The next request can consume it.
- **Camera is outside admission.** `GlimpseView.run` neither checks nor sets `model.busy`; voice deletes the recording before its final busy check.

## Reachable loss and cross-talk scenarios

**S1. Busy share is dropped.** Start a typed/voice request (busy true). Share text via `HandleTextIntent`. `AppModel.send` returns at `AppModel.swift:199`; line 202 is never reached. The body exists only in the intent's local `body` and is discarded when the intent returns. The user sees the refusal string if the intent result is shown; nothing is staged. Code-trace proof; no runtime test.

**S2. A pending card uses another share's body.** Share A when idle → `put(A)` → `email_digest` card A. Before confirming, share B when idle → `put(B)` overwrites A (`Skills.swift:291`) → card B. Confirm card A: `execute` at `ActionPlanner.swift:154` calls `take()` and receives B. Card A's prompt never showed the body, so the user sees a summary of B under A's request. If a third share arrives before card B is confirmed, card B gets C or nil. Two or more pending cards can coexist in `chat`; there is one slot.

**S3. Another request consumes the share.** Share A → `email_digest` card A. Before confirming, type "analyze this document"; if `analyze_document` is chosen and `confirmBeforeAct` says act, `ActionPlanner.swift:159` calls `take()` and consumes A. Card A's later confirm gets nil and returns the "how to share" message. The same happens with a second typed "summarize my last 5 emails" card: whichever confirms first takes the body; the other gets nil. `analyze_document` is especially surprising because a stale share prevents the document picker from opening.

**S4. Confirmation uses stale or expired text.** The card is created at handle time; the body is read at confirm time. If the share is overwritten, the card uses the replacement. If 900 seconds pass, `take()` returns nil and clears the body (`Skills.swift:299`); the card remains in `chat` indefinitely if the process lives. If `peek` consumers (`html_viz`, `summarize_text`) read the body, the card still sees it, but it may already have been sent to cloud reasoning under an unrelated request. Existing test `testEmailDigestUsesSharedInboxOnDevice` proves the late read: it creates the card before `put`, then confirms and gets the text (`SkillsTests.swift:244-255`).

**S5. Process restart loses the text and the card.** `SharedInbox.item`, `AppModel.chat`, `ChatItem.pending`, and `busy` are all in memory. `AppModel.boot` opens SQLite for memory/telemetry and rebuilds the Assistant (`AppModel.swift:111-153`), but never restores chat or pending cards. The checked-in plan already says the current source loses pending confirmations on process death (`docs/research/WORKFLOW_DELIVERY_PLAN.md:13`). The effect recovery is specified to restore effect `DraftCard`s, but `email_digest` and the other reply-only ids are explicitly not claimed (`EFFECT_RECOVERY_CONTRACT.md:201`), so their cards/body are not covered by that recovery. Code-trace proof; a real kill test needs Xcode/iPhone.

**S6. Cancelled, clarified, or failed requests leave the body behind.** `cancel` clears only `pending` (`AppModel.swift:256-260`). A `handle` that throws leaves the body (`:226-230`). A `handle` that returns `.clarify` or `.local` without reaching a shared-text skill also leaves it. The next `email_digest`/`analyze_document` can consume a share the user thought was abandoned. `peek` does not clear, so cloud-reason skills can reuse it until expiry/overwrite.

**S7. Typed input is cleared before a refused send.** `ChatView` sets `input = ""` at `:31`, then starts the task. If `busy` becomes true before `send` runs, `send` returns the refusal at `:199`; `ChatView` ignores the return and does not restore the text. The chat shows no user bubble. This is a narrow race but the same drop shape as S1.

**S8. Voice recording is deleted then refused.** `finish` calls `recorder.stop()` at `:112`, which deletes the WAV (`:62`), then checks `!model.busy` at `:114`. If busy, the audio is gone; the note only says it was not sent. If `keep_voice_recordings` is on, a copy remains in `Documents/Recordings` with no request metadata or resend UI. The cloud transcription is not attempted, so no transcript exists.

**S9. Camera runs outside `busy` and loses state.** `GlimpseView.run` has no `model.busy` check and does not set it. It can overlap a text/voice request, and its photo/question/result are view state. Dismissing the sheet or killing the process loses the request; `record` only appends to chat after the result. This is not a `send` drop, but it is a request payload with no durable owner.

**S10. Effect confirmation throw loses the card.** `AppModel.confirm` clears `pending` at `:237` before `assistant.confirm`; a throw becomes "Failed" at `:239` with no card to retry. The running effect-recovery implementation owns this migration (`docs/research/EFFECT_RECOVERY_CONTRACT.md:17`, `:608`); it is listed so the input-staging fix does not accidentally reintroduce it for read-only cards.

## Producers and consumers of shared text

**Producers (production):**

- `HandleTextIntent.perform` → `AppModel.shared.send(ask, sharedText: body, source:)` (`SkillIntents.swift:67`).
- `AppModel.send` → `SharedInbox.shared.put(sharedText, source:)` (`AppModel.swift:202`).
- That is the only production `put`. Tests call `put` directly (`SkillsTests.swift:251`, `TakeoverRegressionTests.swift:153`).

**Consumers (production):**

- `email_digest`: `take()` (`ActionPlanner.swift:154`), consumes.
- `analyze_document`: `take()` (`:159`), consumes; if empty, opens the document picker.
- `html_viz`: `peek()` (`:167`), does not consume; only when the utterance has no usable numbers.
- `summarize_text`: `peek()` via `.cloudReason` (`:176`), does not consume; can reach `reason` and cloud escalation (`:187-202`). `translate` shares the same branch, but its required `text` argument is normally caught by the clarify check at `ActionPlanner.swift:129-131` before execution, so it is not a normal shared-text consumer.
- `SharedInbox.source` is returned by `take`/`peek` but no consumer uses it for ownership or routing; `HandleTextIntent.utterance` uses its own `source` parameter (`SkillIntents.swift:72-76`) only to append "these emails".

**No consumer checks** that the payload was produced for this request, that it has not expired, that it belongs to the same source, or that its revision matches the confirmation. `take`/`peek` are the entire contract.

## Exact ownership and lifetime requirements for a fix

1. **Create one request identity at ingress, before the busy check.** The identity should be the recovery contract's `UserRequestID` (or the same UUID under a different name), not a new parallel ID. The typed, share, voice, and (if in scope) camera paths must all create it before any `busy` refusal.
2. **One payload record per request.** Store the exact bytes (or a durable file reference plus extracted text), source, creation time, expiry, and a revision. Do not store a pointer to a global slot. A share for request A must never be visible to request B.
3. **Busy means deferred admission, not refusal.** A request arriving while busy is written to `awaitingResume` (or `staged`) and surfaced as "saved; resume when ready." It does not run automatically, and it does not overwrite the running request's payload. This is a small admission state, not a queue or worker.
4. **Bind confirmation to `(requestID, revision)`.** The card that the user sees must carry the payload revision (or an immutable payload reference). `confirm` must claim exactly that revision atomically and fail visibly if it was replaced, expired, or already consumed. The current `PlannedAction` has neither field.
5. **Restart requires explicit user resume.** On launch, read `awaitingResume` rows and show the request plus a payload preview; require a tap to resume, edit, or discard. Never auto-execute after restart, even for a read-only summary that could send text to the cloud. This matches the accepted requirement: "Preserve requests arriving while busy as separately identified, explicitly resumable inputs... must not execute automatically" (`MUSE_REVIEW_FINDINGS.md:26-29`).
6. **Retention and removal are part of the boundary.** Give the record a user-visible TTL, delete the body on complete/cancel/expire, and keep only a tombstone (request id, timestamps, no body) for replay prevention. The current `peek` leaves expired text in memory; a durable store must not repeat that. Decide whether the payload store is excluded from iCloud backup or protected with file protection; `Application Support` is backed up by default, and shared email/document text is sensitive.
7. **Persistence errors must be observable.** If the row or file write fails, refuse the request with a clear "input was not saved; nothing was sent" message. Do not fall back to the in-memory global slot or swallow the error with `try?`. The current code silently relies on the slot.
8. **One writer, one resolver.** The ingress creates the record; the store is the only writer of its table/files; `ActionPlanner.execute` receives a resolver for the request and only reads that request's payload. The UI reads a projection. No skill, view, or intent writes the store directly.
9. **Voice and camera payload ownership.** Voice must stage the WAV or transcript before `stop` deletes it; a busy/refused request must retain the recording or transcript in the record, not just print a note. Camera must either join the same record before its cloud call or be explicitly declared out of scope; today it has no owner and can overlap `busy`.
10. **No automatic replay, no workflow engine, no background service.** The resumed request goes through the same `Assistant.handle`/`confirm` path. There is no separate runner, no multi-step scheduler, and no iOS background execution.

## The smallest ownership boundary

The boundary that must change is **ingress → request context**, not the effect executor.

Today the app hands `Assistant` an utterance and hides the payload in a global singleton. The fix is one durable request-input record keyed by the request identity, created by the ingress adapter before `busy` is consulted, plus a resolver that `ActionPlanner.execute`/`Assistant.confirm` use for that request only. That is smaller than a queue: one active request, a small set of explicitly resumable inputs, and a single durable table/file.

The integration seam with the checked-in recovery contract is already visible:

- `UserRequestID` is per utterance (`EFFECT_RECOVERY_CONTRACT.md:604`).
- `DraftCard` already carries `requestID` (`:273-284`), and `action_attempts` stores `request_id` (`:788-810`). `EffectSession.evaluate` already takes a `requestID` (`:548-557`).
- Reply-only ids are explicitly never claimed and never a workflow step (`:201`). Do not turn `email_digest` into an `AttemptID` or add a fake effect just to get persistence. Use a sibling request-input record keyed by the same `UserRequestID`.
- The running recovery implementation owns `EffectSession`/`EffectLedger`, typed reports, editable pending drafts, exact contact methods/instants, and the `AppModel`/`ChatView` confirmation migration. The staging fix should merge at the `DraftCard`/`ChatItem` projection and share the request ID; it should not create a second confirmation model or touch the ledger's state machine.
- The store can live in PocketCore on the same `SQLiteDB` as `MemoryStore`/`EffectLedger`, following the contract's usage rule (`EFFECT_RECOVERY_CONTRACT.md:67`, `:781`) and its no-nested-transaction rule (`:842`). It must be its own writer/table, not a column the effect ledger owns, because reply-only reads have no attempt.

**Staging before the busy guard alone is not a fix.** `ActionPlanner.execute` reads `SharedInbox` at execution time (`ActionPlanner.swift:154-176`). If `put` moves above the guard but the running request still resolves through the same global slot, the running document request can consume the new request's data. That is exactly the rejection in `MUSE_REVIEW_FINDINGS.md:29` and the accepted direction in `WORKFLOW_DELIVERY_PLAN.md:96`. The binding to the request, not the order of `put`, is the fix.

**A bounded next design question:** *What is the minimal durable request-input record and resolver that binds exactly one immutable/revisioned payload to one `UserRequestID` across the busy boundary and restart, and which ingress paths (share, typed, voice; camera included or explicitly deferred) must write it before the first `busy` check, without turning reply-only reads into effect attempts or adding a queue?*

That question is deliberately narrower than "design a queue." It asks only for the record shape, the resolver seam, and the ingress coverage. The effect recovery implementation remains the owner of effects and confirmations; this fix owns the request's bytes.

## Focused behavior checks the parent can run on Linux

No Swift toolchain is present in this container, so none of these were run here. The project record reports 136 tests, one skipped (`WORKFLOW_DELIVERY_PLAN.md:98-99`).

**Existing checks that already expose the current behavior:**

- `swift test --package-path core --filter SkillsTests/testEmailDigestUsesSharedInboxOnDevice` — proves the card is created before the body is stored, and `confirm` reads `take()` at confirmation time (`SkillsTests.swift:239-256`).
- `swift test --package-path core --filter TakeoverRegressionTests/testSharedTextEscalationScrubsRememberedEntityNames` — proves `execute` consumes the global slot and sends the shared text through `reason` (`TakeoverRegressionTests.swift:137-159`).
- A small test or script can prove `SharedInbox` is per-instance, not durable: `put` on one `SharedInbox`, construct another, `peek` returns nil. That is not an app-restart test; source inspection is the proof that the app uses only `.shared`.

**Proposed core-only checks for the fix (no app/Xcode needed):**

1. **Busy share is staged, not dropped.** Fake admission: stage request A for payload A while "busy"; stage B; assert both records exist, neither auto-ran, and the running request still resolves A.
2. **Confirm uses its own payload.** Stage A and B; confirm A; resolver returns A; B remains B; no overwrite. Then confirm B; still B.
3. **Overwrite cannot change a pending revision.** Stage A rev 1; create a card bound to rev 1; replace A with A′ rev 2; confirm rev 1 fails visibly and executes zero times.
4. **Expiry purges, not just hides.** Expire A; `peek`/`resolve` returns nil; the body is physically gone or tombstoned; a later `email_digest` gets nil, not A.
5. **Cancel removes the payload.** Stage A, cancel; then run `email_digest`; it returns the honest "share" message, not A.
6. **Restart restores `awaitingResume` without executing.** File-backed SQLite, stage A, drop the store, reopen; A is listed, `perform`/`execute` count is zero; explicit resume is required.
7. **Concurrent confirm yields one payload.** Two threads confirm the same card; exactly one claim gets the payload/revision; the other returns a typed terminal result, not a second read.
8. **Persistence failure is observable.** A failing store returns an explicit error to the ingress; the request is not silently placed in the old global slot.
9. **Source/revision mismatch is rejected.** A record created for request A cannot be resolved by request B even if both are `email_digest` and both are unexpired.

**What these tests cannot prove:** AppModel's busy guard, App Intents, SwiftUI input clearing, voice recording/deletion, camera sheet lifetime, process kill, and iOS cloud/UI behavior. Those remain code-trace or device checks.

## Code-trace proof vs runtime proof

- **Code-trace proof (this report):** the busy guard ordering, `put` overwrite, `take`/`peek` call sites, card prompt construction, confirm-time read, in-memory lifetimes, voice delete-before-check, and camera's missing busy check. These are direct source facts at the cited lines.
- **Saved-test proof:** `testEmailDigestUsesSharedInboxOnDevice` proves the late read at confirm time; `testSharedTextEscalation...` proves `execute` consumes the global slot. These run in PocketCore only.
- **Runtime proof (not available here):** an actual share while busy, an actual two-share/confirm sequence in the app, a real app kill/relaunch, voice/camera permissions and transcription, App Intent delivery, and iPhone timing. A Simulator run would still not prove the phone behavior, and this report does not claim one.

## What cannot be tested without Xcode/iPhone

- App Intents execution: whether the share sheet delivers `HandleTextIntent` while the app is busy, whether iOS retries it, whether `openAppWhenRun` runs in the app process, and how the refusal is displayed to the user.
- Process kill/relaunch, scene state, background suspension, data protection, and iCloud backup of any new payload store.
- `AVAudioSession`, microphone permission, recording lifecycle, Meta transcription, camera/PhotosPicker, Vision OCR, and the Glimpse cloud calls.
- `AppModel`/SwiftUI actor timing, input clearing, confirm/cancel taps, sheet dismissal, and accessibility.
- MessageUI, Mail, EventKit, Keychain, and the actual effect execution the recovery implementation owns.
- iPhone latency, memory, thermal, and model behavior. The saved evaluation is Linux CPU data; no phone claim follows.

## Attention: continuation decision-trail audit

Scope: only `decisions.tsv` rows starting at run41's start, 2026-11-04T17:48:02Z — rows 22–24. Everything through row 21 (17:42:02Z) belongs to earlier runs. Parent thread `4311f30f-96dc-4e78-9f19-860e3bbea796` was read after position 1682 in bounded messages/activity reads. As of 18:00 UTC the TSV still ends at 17:48:02Z.

**What the three rows say and whether it holds:**

| Row | Claim | Check |
|---|---|---|
| start | Resume at `4b92321`; existing recovery/review delegates intact; clean tree; no implementation restarted | Our checkout is clean at `4b92321`; the recovery and review child threads were found after ID encoding. The current tree matches. |
| model-question | Report internal gains without an industry-wide Pareto claim; small hand-authored evals; no inference/training | The messages do avoid the frontier claim and repeatedly label decision-label results. The chart's numbers are mostly right; one is not (below). |
| resume-scope | Busy input is dropped; `SharedInbox` is a global single slot; effect implementation owns overlapping files | Correct. The guard is `AppModel.swift:199` (not 198); `SharedInbox` class starts at `Skills.swift:286`, singleton at 287, `put` at 291. No source write was made by this continuation. |

**Model-number check against saved files (no new inference):**

- 74.2 → 81.7% accuracy: `eval/results/risk_coverage_test120.json` (`0.741666…` → `0.816666…`); `AFTER_FLOOR.md` rounds to 0.74 → 0.82. Accurate.
- 15.0 → 50.8% at τ=0.80: `risk_coverage_test120.json` `at_tau` gives `0.15` → `0.508333…`. Accurate.
- 6.7 → 36.7% at τ=0.90: the shipping side is `0.366666…` (44/120), accurate. **The baseline side is not 6.7%.** The saved test run has 9/120 kept at τ=0.90 = **7.5%** (`eval/experiments/test120_results.json`; `risk_coverage_test120.json` `at_tau` = `0.075`). 6.7% is 8/120, which is the *curve* step at τ≈0.9196, not the τ=0.90 kept set. The rendered chart at positions 1706/1708 therefore says 6.7% where the cited saved files say 7.5%; that is a one-item error (0.83 pt) and makes the baseline look slightly worse than it was. The rest of the chart is consistent.
- 89 → 92% accuracy on handled at τ=0.80: `AFTER_FLOOR.md` 0.89 → 0.92; the JSON gives 0.8889 → 0.9180. Accurate to rounding.
- ECE 0.150 → 0.064: `AFTER_FLOOR.md`. Accurate (test120, 10 bins).
- AURC 0.148 → 0.085: `risk_coverage_test120.json` `0.14778` → `0.08534`. Accurate.
- Shipping τ=0.90: 44 accepted, 41 correct. Consistent with the 0.3667 coverage and 0.06818 risk; `PROJECT_STATUS.md` also states it.
- "Q4 was our best measured compromise; larger Q8/full precision gave no clear improvement." `QUANT_IDENTITY.md` supports Q4 on size plus calibration/bound, but on test120 Q8/f16 actually handled more (0.53 vs 0.51) with higher accuracy on handled (0.938/0.953 vs 0.918). The claim is a reasonable size/calibration judgment, not uniform dominance; "no clear gain" is an over-compression if read as every metric.
- "The second training round also failed its acceptance gate." `ROUND2.md` says V4-gpuC passed on the two fresh runs but failed the ECE clause on both warm runs; the pre-registered gate required every run, so the final verdict is rejected and the shipping model is unchanged. The sentence is true, but it omits that this was the strongest near-miss (bound 9.6–9.8% at τ0.88, coverage 0.54–0.56, ECE 0.059 fresh / 0.066 warm). No test120 run was made for round 2; do not infer test generalization either way.
- The historical 10.2% bound: the continuation messages do not repeat it. `AFTER_FLOOR.md` still contains the sentence in its historical body, but its header and `EVALUATION_CLAIMS.md` say the calculation is nominal, selected on cal180, and not a post-selection guarantee. The 3 errors in 44 accepted at τ0.90 give a nominal one-sided 90% limit around 14.6%, not 10.2%. Keep quoting the caveat, not the bound.

**Trail gaps and risks:**

1. **The chart is shown to the user with a wrong baseline.** Fix the 6.7% label to 7.5% (9/120) or say "about 7%" and cite `test120_results.json`/`risk_coverage_test120.json`. This is the one concrete misleading number in the continuation.
2. **The training pivot after 17:48 is not in `decisions.tsv`.** At position 1735 the user asked to scale training with remaining credits; the parent agreed at 1736 and by 1803 reported a controlled two-epoch V4 experiment and asked for dashboard balances. The TSV has no row for that experiment, budget reservation, or acceptance gate. The user explicitly asked for an orchestrator handoff ledger; the tsv is stale for the newest work. This is a handoff risk, not a claim that the experiment is wrong.
3. **"Q8/full precision offered no clear gain" is compressed.** If the parent repeats it, add "Q8/f16 handled slightly more on test120 but were worse on calibration/bound and much larger." Otherwise a listener may think Q4 dominated every metric.
4. **"Round 2 failed" is true but incomplete.** It failed under the every-run gate; two fresh runs passed. If the next decision is "don't scale training," this row alone understates the near-miss. `ROUND2.md` is the evidence; the tsv does not cite the fresh-vs-warm split.
5. **51% is not shipping coverage.** It is τ=0.80, labeled experimental in the chart and in the 1690 message. The shipping τ=0.90 figure is 36.7%. The parent message says this, so this is a headline-reading risk, not a false claim.
6. **The `AFTER_FLOOR.md` historical body is a trap.** It still says "error bound 10.2%" and "certified" language in places; the correction header is easy to miss. The current messages avoid it. Do not let a later summary quote the body without the header.
7. **Minor citation:** parent's `AppModel.swift:198` is the signature; the guard is 199. `Skills.swift:286` is the class declaration; the singleton is 287 and `put` is 291.

No settings changes were made. The report is at `/tmp/pocket-glimmer-takeover/request-input-grounding.md`.
