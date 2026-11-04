# Cross-judge: request-input candidates A and B

**Verdict: A is the better base, narrowly (15.0 vs 14.0 on a 25-point scale), but neither candidate is implementable as written.** A's single-transaction request store is closer to the actual crash paths; B's caller/UI behavior is better but its file+row stage and pre-CAS transcription are structural. A becomes viable only with an explicit process-ownership lock and a resume-time review rule. Those are focused grafts, not a new workflow.

**Evidence and limits.** I read both designs end-to-end, `docs/research/REQUEST_INPUT_GROUNDING.md`, the accepted Muse requirement at `docs/research/MUSE_REVIEW_FINDINGS.md:26-29`, the parent's `docs/research/REQUEST_INPUT_DESIGN_A_REVIEW.md`, and the current code at parent `d21d32a` (compile fix `c2e3fb4` integrated). Current line anchors differ from both designs' baselines (A `1e5c56e`; B `5912cd7`/`2475888`): today `AppModel.send` is line 231 with the busy guard at 232; `Assistant.handle` is 112 and creates its own `UserRequestID` at 117; `ChatView` clears at 32-33 and disables send at 35; `MicButton` deletes the WAV in `VoiceCapture.stop` at 51-65 and disables itself at 94; `GlimpseView.run` is 73-95 with no busy check. The substantive seam is unchanged. This is read-only: no repository edit, agent, paid call, worktree, Swift build, or Xcode run. I am the same model family as both candidates (River02/DeepSeek V4.1 Flash1017 max); that is an evidence limitation, not an independence claim. The mac_prep diagnostics change and the separate calibration/time worker do not affect these conclusions.

## Scorecard

| Criterion | A | B | Decisive reason |
|---|---:|---:|---|
| 1. Durable immutable per-request ownership before busy/refusal, no crossover, text+share+voice, explicit camera completeness | 3.5 | 3.0 | A's body+state is one transaction; B's files+row is two-resource and has an orphan race. A's UI still disables busy ingress; B's enables it. A's trigger still permits resurrection; B's camera plan is thinner. |
| 2. Crash/claim safety, concurrent instances, double resume, kill at each handoff, no automatic run/repeated effects | 2.0 | 2.5 | A's per-instance recovery flag can turn a live claim into a retryable interruption and duplicate a calendar/reminder effect. B's no-resume interrupted state avoids duplicate effects, but `recoverClaimed` still misclassifies live work, and voice transcribes before the CAS. |
| 3. Minimal coherent integration with `UserRequestID`/effect ledger, small API, honest results | 4.0 | 3.0 | A adds a read-only effect-state query and a pure resume policy; B's same-DB/six-method store is smaller but never reconciles its input projection with the ledger, and its rejection of A is a strawman. |
| 4. Bounded sensitive retention/protection, crash-safe cleanup, no forensic claim | 3.0 | 2.5 | A has a total byte cap and secure-delete/VACUUM, but retains `source_label`/`interrupt_reason` and allows a nulled body to be rewritten. B's row is text-free but the cap counts only staged rows, so interrupted bytes accumulate. |
| 5. Verifiable caller behavior, capture-time meaning/relative dates, accessibility, practical scope | 2.5 | 3.0 | B enables the composer/mic while busy and has VoiceOver labels; A has the better receipt type and camera slice plan. Both silently resolve relative dates at resume; `calendar_create`/`reminder_create` can auto-act with no card. |
| **Total** | **15.0** | **14.0** | Narrow A base; the safety-critical scores are failing, not passing. |

## 1. Durable ownership before busy, no crossover, all ingress paths

**A.** The core is right: `send`/`submitVoice` stage one immutable body keyed by a new `UserRequestID` before reading `busy`; the body, preview, byte count, source, creation and expiry are one transaction. There is no global slot, and `Assistant.handle` receives the same ID. The immutable-body trigger is a real defense, but not complete:

- **Terminal resurrection.** The trigger's `WHEN` requires an old non-null body (`design.md` 456-465). After `complete`/`discard`/`expired` nulls every body field, `UPDATE request_inputs SET payload_text='...' WHERE request_id=...` is allowed because `OLD.payload_text IS NULL`. The public API has no such method today, but the database does not enforce the claimed invariant, and a future migration/bug can leave sensitive text in a terminal row.
- **Metadata is not deleted.** A's deletion list clears utterance, payload text/blob/meta, transcript and preview, but not `source_label` or `interrupt_reason` (`design.md` 427, 452-453). `source_label` comes from `HandleTextIntent.source`, an arbitrary Shortcut parameter, and can be a filename or user phrase. `interrupt_reason` is arbitrary `String`; an error message can contain input. The tombstone then keeps exactly the fields the parent asked to clear (`REQUEST_INPUT_DESIGN_A_REVIEW.md:19-22`).
- **One-time transcript is store logic, not a constraint.** The trigger does not cover `transcript`; a second `setTranscript` would be accepted unless the implementation remembers. The test plan says it is written once (`design.md` 553), but the schema does not enforce it.
- **Caller behavior contradicts the store.** A leaves `.disabled(... || model.busy)` on the composer (`design.md` 37; current `ChatView:35`) and does not remove `MicButton`'s `.disabled(model.busy)` (current `VoiceCapture:94`). A busy typed request cannot reach `send`; a busy voice request cannot start recording. The one reachable voice loss is the race where recording begins idle and `busy` becomes true before release. A's field retention is only `@State`; process death while busy loses it. B explicitly enables both, which is the correct caller contract.
- **Camera.** A is honest and concrete: slice 1 stays view-only; slice 2 adds `.camera(jpeg, question, concept, mode, photoText)` to the same store, reopens `GlimpseView` on resume, never routes camera through `Assistant.handle`, and uses a 1 MiB cap and protected/excluded storage (`design.md` 406-410). The photo and OCR text still die on process death today, but A names the durable next slice rather than calling the gap solved.

**B.** The caller contract is better: `submit` is synchronous, stages before `busy`, and the composer/mic are enabled while busy (`design.md` 40-51, 74-90, 371-377). `RequestSource` is an enum, so no free-form source label leaks; `RequestTerminal` makes terminal-to-staged impossible at the type level. But the ownership boundary is weaker:

- **Files then row.** `stage` writes `<uuid>/request.json` and `voice.wav`, then inserts the row. On init, the store removes any `<uuid>` directory with no matching row (`design.md` 294-304). A concurrent writer can lose an in-flight file: writer A creates its directory and writes the body; writer B opens the store and its init orphan sweep sees no row yet and deletes A's directory; A then inserts a row pointing at a missing body. The row becomes staged with `payloadAvailable == false`, and `claim` turns it unreadable. This is not durable ownership under the exact concurrent-instance case the task requires. The sweep needs a grace period or an incoming/staging marker, and file writes need atomic write + fsync; none is specified.
- **No total-byte cap.** B caps per payload (`maxTextBytes`, `maxVoiceBytes`) and counts staged rows (`maxPending = 8`), but the UI deliberately shows "at most eight staged, plus any interrupted items" (`design.md` 360). Interrupted items are terminal and are not counted; each keeps its body for 24 h (`design.md` 340). Repeated kill-during-handle can accumulate 2 MB WAVs or 1 MB texts without a cap.
- **Camera.** B's dismiss guard and "not saved" copy are useful immediate mitigation, and the future `.photo(Data)` option is named. But B does not specify the question/concept/mode/OCR fields or a resume route, so its completeness for the final durable-capture requirement is below A's slice 2.

**Score: A 3.5, B 3.0.** A's store has the better ownership primitive; B's caller is more truthful. A's trigger/metadata gaps and B's file/row race are both real, not stylistic.

## 2. Crash and claim safety: concurrent instances, double resume, kill points

**A.** The single SQLite transaction is the strongest part of either design. `stage` commits body+row together; `claim` is one CAS (`WHERE state='staged' AND expires>?`, `changes()==1`); `complete`/`discard`/`expire` null the body in the same row; `interrupt` keeps it. Kill after stage, after claim, after effect `insertAwaiting`, after effect claim, and after effect settle are all classifiable from the input row plus the ledger. The reconciliation table is the right shape: `.awaiting` shows the card and completes the input, `.settled` completes it, `.uncertain` blocks Resume, `.none` permits only an explicit retry. Launch and `busy` clear never call `handle`. Voice claims before transcribing (`design.md` 364-367), so two resumes cannot both upload the WAV; a crash after `setTranscript` reuses the transcript, and a crash before it repeats only on explicit retry.

The blocking defect is the ownership of a claim:

- **The one-shot flag is per store instance, not per process.** `recoverOnLaunch`'s first call converts every `.claimed` row to `.interrupted` (`design.md` 210, 373-378). A second `RequestInputStore` instance on the same directory — a second process, a test helper, a future view model, or an App Intent extension — has its own "first call" and converts a live claim. A's own test `testReopenTurnsClaimedIntoInterrupted` asserts this. The open question at `design.md` 600 admits that an epoch is the proposed fix, but an epoch alone still does not prove the prior process is dead. Concrete failure: process A claims request R and is awaiting its first reflex decision (no `action_attempts` row yet); process B opens the store, marks R interrupted; the user taps "Try again"; `requestState` is `.none`; B claims R and runs `calendar_create`; A finishes and also creates the event. Two effects, same request ID. No amount of CAS on the input row fixes this once the row is wrongly terminal.
- **Cloud reads are not in the ledger.** A says an interrupted request with no effect row is "safe with respect to external actions" (`design.md` 404), but the `sharedText`/`reason` path creates no `action_attempts` row at all. Crash after the cloud read but before the UI returns; relaunch shows "Try again"; retry sends the same document to the cloud again. A discloses repeated voice transcription but not repeated cloud reads. The parent's review item 5 requires this disclosure (`REQUEST_INPUT_DESIGN_A_REVIEW.md:26-27`).
- **Two smaller state gaps.** `summaries` is described as "the same expiry and purge without the claimed conversion" (`design.md` 210); it does not say claimed rows are excluded from the UI. A stuck claimed row after a `complete` failure could be shown as a saved card whose Resume/Discard both return `.alreadyClaimed`. And `resume` never guards `assistant != nil`: a saved card visible before the model loads has an enabled Resume; if tapped, it claims and then cannot run, turning a valid staged request into interrupted. B explicitly says Resume refuses until the model loads (`design.md` 257); that is the correct behavior.

**B.** The no-resume interrupted policy is genuinely safer for effects: `claim` accepts only staged; `recoverClaimed` makes claimed interrupted; interrupted can only be discarded or expired (`design.md` 307-318). A misclassified live claim cannot be retried, so the calendar-event duplicate above does not occur. Double resume is a one-winner CAS for text. Kill at stage, after claim, during transcription, during handle, and after effect settle never auto-runs and never retries a claimed row. The terminal deletion order (delete body directory before writing the terminal row) fails in the privacy-safe direction: a crash leaves a prior status with no body, and `claim` marks it unreadable.

But B has three concrete crash/claim problems:

- **`recoverClaimed` has the same live-claim corruption, with less duplicate risk.** A second process that boots while A is running converts R to interrupted; B's live owner continues, but B's lifecycle says terminal never returns, so the input row stays "interrupted" and the body is retained. B's UI then says "Outcome unknown; nothing was re-run" even if the ledger later settles the effect. B has no `EffectLedger.requestState` equivalent, so it can misreport a known result as unknown. If the second process stages its own request S, both processes can run turns concurrently because `busy` is process-local. B's answer to the process boundary is an assumption ("`openAppWhenRun = true` should mean the app is foreground"), not an ownership mechanism.
- **Voice transcribes before the CAS.** B's voice section says admission transcribes while the request is still `staged`, then claims (`design.md` 377-379). That deliberately allows two resumes — or two processes — to send the same WAV to Meta before one wins the claim. The loser discards its transcript but the outbound audio and paid call already happened. It also contradicts B's own API: `resume` is synchronous and "refuses while busy, claims the row atomically, sets busy" (`design.md` 70-72), so it cannot await transcription before the claim as described. If transcription instead happens after the claim, a transcription failure must return the row to `staged` to honor "transcription failure leaves the request staged" (`design.md` 90, 379), but B's lifecycle has no claimed→staged edge and says terminal never returns. This is not a wording nit; it determines whether duplicate paid uploads and lost transcripts are possible.
- **Files+row and settled-effect presentation.** The orphan race from section 1 is also a crash-safety defect. The terminal-delete crash leaves a row whose body is gone; B handles it as unreadable, which is honest, but the user cannot recover the input. After an effect settles and the app dies before the input row is terminal, B's input bar says interrupted/unknown even though the effect ledger knows the result; the user may discard the only saved copy while the answer is in the ledger. A's `requestState` avoids that specific misreport.

**Score: A 2.0, B 2.5.** B's no-resume rule is a valid safety default, but it does not solve live ownership; A's process bug can duplicate an effect, which is worse than B's duplicate transcription and lost recovery.

## 3. Integration with `UserRequestID`, the effect ledger, API size and result honesty

**A.** The identity join is exact: one `UserRequestID` is created at ingress, stored as the input primary key, passed to `Assistant.handle`, and lands in `DraftCard.requestID` and `action_attempts.request_id`. The read-only `EffectLedger.requestState(for:)` reuses the existing `action_attempts_request` index, decoder, `contract(for:)` and `card(for:)`; it adds no column, phase or executor. The pure `RequestResumePolicy` is the right place for the "input state × effect state" decision, and the matrix in `design.md` 263-275 is complete for the states it names. The `SendReceipt` outcome type is clearer than a string. The separate protected database is a defensible boundary: it has a different TTL, size cap, protection class and backup policy from `pocket.sqlite`; the effect ledger remains the authority for effects, and the reconciliation matrix closes the crash window between the two databases.

The costs are real:

- `Assistant.handle`'s `requestID: UserRequestID = UserRequestID()` default (`design.md` 320-323) allows a production call site to omit the ingress ID and silently create a new one, unlinking the input row from the effect row. B is right that a non-default parameter is safer. The module map says "3 lines" (`design.md` 336); if the default is removed, roughly forty test call sites need the argument, as B notes. That is mechanical but not free.
- `.settled` in `RequestEffectState` carries no result (`design.md` 233-238). After a crash the UI can say "already finished" but cannot show what the effect ledger recorded. A `settled(EffectResult?)` or a separate `latestResult` would be more honest; A's current `.alreadyFinished` system note is thin.
- A's store is ten public methods; B's is six. A's extra methods are justified by retry, transcript and launch recovery, but the parent should not let the API grow into a general state setter. A generic `setState` would be a regression; keep the explicit transitions.

**B.** B's same-database sibling ledger is the smaller integration: `RequestLedger` is the only writer of `request_inputs` and `RequestInputs/`, `EffectLedger` remains the only writer of `action_attempts`, and the shared `SQLiteDB` follows the existing `MemoryStore`/`EffectLedger` pattern. `RequestTerminal` is a good type-level guard. But B never integrates the effect state into the pending UI: the card owns the action, the bar owns the input, and they are deliberately not merged (`design.md` 369). That is coherent only if the user can tell which is authoritative and if a settled effect is surfaced. B says "outcome unknown" for interrupted without querying the ledger; the ledger may know it settled. Discarding the bar does not cancel the card, and cancelling the card does not delete the body; that can leave two controls for one request with different retention. B's `send` returns a bare `String` while `submit` returns `SubmitReceipt`; the App Intent cannot assert the outcome type. The voice pre-CAS issue means the six-method store is missing the transcript/state transition it needs; adding it would enlarge the API.

B's synthesis also rejects a design that is not A: "a standalone RequestInbox actor with its own UUID and auto-drain" (`design.md` 404-413). A uses the same `UserRequestID`, no auto-drain, and an explicit resume card; its only real differences are the separate DB and retry policy. B's chosen "sibling `RequestLedger` on the effect journal's database" is closer to A than B's rejection admits. That does not make B's design wrong, but the comparison is not evidence against A.

**Score: A 4.0, B 3.0.** A's effect query/policy is the missing integration; B's smaller module is attractive but under-integrates the ledger and misstates the alternative.

## 4. Retention, protection, physical cleanup, no forensic overclaim

**A.** The policy is bounded and transparent: 24 h TTL, 8 active rows, 8 MiB total body bytes, 24,000 text characters, 2 MiB voice, 30-day tombstone, 160-character preview (`design.md` 130-139, 416-430). The separate database is `.complete`, excluded from backup, `journal_mode=DELETE`, `synchronous=FULL`, `secure_delete=ON`, and `VACUUM` after purge. `complete`/`discard`/`expired` null the body, transcript and preview; the tombstone keeps only ID, state, origin, timestamps and byte count. A correctly says this is not forensic erasure (`design.md` 469). The `_sharedText` gap is disclosed: confirmed reply cards still hold the shared text in `pocket.sqlite`, which is backed up (`design.md` 471, 599).

The concrete leaks are the ones the parent already named: `source_label` and `interrupt_reason` survive terminal deletion; the trigger permits body resurrection from null; state/body combinations are not enforced; `transcript` one-time is store logic only. `source_label` is the worst because it is free-form and can be a filename. A's `preview` is also a second sensitive copy in the database, but it is bounded and cleared; that is acceptable if it is cleared reliably. A's temporary WAV is deleted after stage success, but a crash between stage and delete leaves a `glimmer-voice-*.wav` in `tmp` with no owner; there is no launch cleanup.

**B.** The text-free row and tombstone are a genuine improvement over A's metadata: `request_inputs` stores no utterance, text or path (`design.md` 294), `source` is an enum, and terminal rows keep only IDs, source, counts and timestamps. The files are `.complete` and excluded from backup; deletion is directory-first, so a crash fails toward no body. B does not claim forensic erasure. B also correctly flags that `pocket.sqlite` still holds `_sharedText` and that the app must not be described as backup-clean (`design.md` 354, 484).

But B's retention is not actually bounded:

- The 8-item cap counts staged requests only; interrupted items are terminal and not counted (`design.md` 360). Each interrupted item keeps its full body for 24 h. A 2 MB WAV per interrupted voice request, or a 1 MB shared text, can accumulate without a total-byte cap. The cap requirement is defeated by exactly the state that is easiest to create with a kill.
- Interrupted bodies are kept "so the user can see what was in flight" (`design.md` 340), but the UI only shows a 160-character preview and offers Discard, no resume (`design.md` 362-367). Keeping the full document/WAV for a preview the user cannot open is retention without a product benefit. Either show the body with an explicit reveal/copy action, or delete it on interruption and keep the preview only.
- The orphan sweep is aggressive. It deletes any directory with no row at init; there is no age or staging marker, so a concurrent writer loses its file. The same sweep is the only cleanup for a crashed pre-row write; a crashed in-flight file can remain until the next init if the app never relaunches.
- `request.json`/`voice.wav` durability is underspecified: no atomic write, fsync, or directory sync is named. A row can exist after a power loss while the file is truncated; `claim` then marks it unreadable. That is honest but loses the input.

**Why A's separate protected SQLite body is the better tradeoff.** The actual crash paths are body+state transitions: stage, claim, complete, discard, expire. A makes each one atomic in one resource. B splits each into a file operation and a row operation, adding orphan, missing-body, and delete-before-row windows; its text-free row does not make `pocket.sqlite` backup-clean because `_sharedText` remains. A's cost is a second connection and a cross-database reconciliation with the effect ledger; that reconciliation is already required by the identity join and is specified as a small read-only query. The parent should accept the second database and spend the effort on the lock, metadata cleanup, and trigger invariants, rather than on a file/row protocol that has more failure modes.

**Score: A 3.0, B 2.5.** A has the better cap and deletion primitive; B has the better metadata shape. A's metadata leak and B's uncapped interrupted bodies are both release blockers, not polish.

## 5. Verifiable callers, capture-time meaning, accessibility, scope

**Caller behavior.** A's `SendReceipt` is testable (outcome + request ID + message), and its ChatView restore-on-refusal is a real improvement. But A's button remains disabled while busy, so the typed busy case is not exercised; the store can stage, but the caller never asks it to. B's synchronous `submit` with `.started/.deferred/.notSaved` is the strongest caller contract in either design; the composer and mic are enabled while busy, and the field is cleared only after the store wrote. A should adopt that split: synchronous `submit` for the UI, async `send` for App Intents, one store and one run core.

**Relative dates. This is a shared failure, and A's wording is wrong.** Current `calendar_create` and `reminder_create` are `.localWrite` with `.modelMayAct` (`EffectLedger.swift:517-521`; helper at 606). `EffectSession.evaluate` sets `mustCard = confirmation == .always || modelAskedConfirm || explicitDraft` (1466); if the model says act and `readiness` has no pause, a fully parsed local write performs without a card. `bind` resolves the date through `PhoneEffects.resolveInstant` (1681-1755), and `InstantParser.parse` ignores its `now`/`timeZone` arguments (`_ = now; _ = timeZone`, 1966-1972); the app adapter uses `NSDataDetector`, which resolves relative to the actual current date. A's tradeoff says "relative times are interpreted at resume time... the confirmation card shows the resolved instant before any effect" (`design.md` 589). That is false for the `.modelMayAct` auto-act path: "add lunch tomorrow at noon" typed while busy and resumed the next day can create lunch the day after capture with no card and no review. B does not mention the issue at all, so it is worse on disclosure but no better in behavior.

The practical fix is not to reparse at `capturedAt` (the detector cannot honor a past reference date without a new parser). It is to force review on resume: store `createdAt` and a resume flag; if a resumed request selects a capability with a `.datetime` argument, set `explicitDraft`/`modelAskedConfirm` so `EffectSession.evaluate` stages a card. The card shows the captured phrase/time (`BoundAction.timePhrase`, `timeZoneID`), the newly resolved instant, and a notice such as "Saved Nov 4; 'tomorrow' now resolves to Nov 6. Confirm or edit." The user reviews; no silent shift. This is a small policy flag, not a new state. It also covers the interrupted-retry path. First-run immediate requests keep today's behavior.

**Accessibility.** B is clearly better: VoiceOver labels say "Resume saved request from share, 12,430 characters" and "Discard saved request"; the body is not read (`design.md` 373). A's card uses the preview as the main text and does not specify a source/size label; VoiceOver may read a sensitive preview. A should adopt B's labels. A's expiry text is good; B's "Saved until" is good. Both should avoid putting a filename in the label.

**Practical scope.** A's module map is optimistic: adding `requestID` with no default touches roughly forty tests; the `now` parameter in `Assistant.handle` is already dead and would need removal or use; the separate database needs policy PRAGMAs (`journal_mode=DELETE`, `synchronous=FULL`, `secure_delete=ON`) immediately after open, and the current `SQLiteDB` hardcodes WAL at open (`SQLiteDB.swift:24-31`), so A must either issue the PRAGMAs on a fresh connection and handle the WAL→DELETE switch or add a small configuration hook. B correctly flags the forty call sites and the Mac/AppModel line drift. B's own scope has a hidden cost: the voice pre-CAS contradiction must be resolved with either a new transition or a transcript persistence change, and the file store needs atomic write/fsync and a safe orphan policy. Neither design's test list is executed evidence; the parent's current record is 189 tests with one skip, not A's stale 136.

**Camera.** A's slice 2 is the only plan that names the full captured state (JPEG, question, concept, mode, OCR photoText), the resume view, the 1 MiB cap, and the rule that camera does not become a fake effect. B's dismiss guard/copy is a good immediate mitigation, but its future `.photo(Data)` sketch is incomplete. The final task requires durable capture flows; neither candidate delivers camera in this slice, so the parent must schedule A's slice 2 rather than describe the app as complete after text/share/voice.

**Score: A 2.5, B 3.0.** B wins the caller/accessibility comparison; A wins the receipt/camera-plan comparison; both fail the date requirement, and A's false "card always shows the instant" claim costs it more than B's silence.

## Recommendation: A as base, with four focused grafts and the required camera slice

Use A's `RequestInputStore` (separate protected SQLite, one transaction per transition), A's `UserRequestID` join, and A's `EffectLedger.requestState` + `RequestResumePolicy`. Do not adopt B's file+row store or B's pre-CAS voice order. Graft from B only where it is clearly better:

1. **Process ownership (mandatory).** Add a small `StoreOwner`: a process-wide registry keyed by canonical store path plus an OS advisory lock (`flock` on `owner.lock`, held for the store's lifetime). Only the owner may `recoverOnLaunch`, `claim`, `retryInterrupted`, `setTranscript`, `complete` or `interrupt`. A non-owner may `stage`, `summaries` and `discard` a staged/interrupted row; it never converts a claimed row. If the OS lock cannot be acquired, the store is non-owner and the UI says "saved; another Pocket Glimmer session is finishing." On owner death the OS releases the lock; the next owner converts claimed→interrupted. No epoch, heartbeat, or pid is proof; the lock is the proof. Keep `claimed_at` for diagnostics only.
2. **Resume-time review (mandatory).** Store `createdAt`/timezone (A already has `createdAt`; add the timezone to the claimed value). Add `isResume` to the `Assistant.handle`/`planSkillCore`/`evaluate` path. On resume, any selected capability with a `.datetime` argument forces a card (`explicitDraft`/`modelAskedConfirm`), showing the captured phrase/time and the newly resolved instant. No auto-act; no silent date shift. Do not claim capture-time parsing; the current detector cannot do it without a new parser.
3. **Store hardening (mandatory).** Replace `source_label` with B's `RequestSource` enum (or a fixed allowlist), replace free-form `interrupt_reason` with a coded enum, and clear all of it on terminal. Extend the trigger/state checks so a terminal row cannot regain a body, `payload_kind`/`origin`/`byte_count` cannot be rewritten, and `transcript` is write-once. Define active cap as `staged|claimed|interrupted` and count total body bytes, so interrupted rows cannot accumulate. Add temp-WAV cleanup on launch. Add `_sharedText` to the retention scope: at minimum, null it on reply-card settle/cancel and add a TTL in a follow-up; do not call the app retention-complete until that lands.
4. **Caller truthfulness (graft B).** Enable the composer and mic while busy; use a synchronous `submit` for the UI and async `send` for App Intents over one core; clear only on saved/started, restore typed text on refusal, keep the temp WAV on refusal. Guard `resume` on `assistant != nil` (show "model not ready", do not claim). Add B's VoiceOver labels (source/size, not body). Remove the default `requestID` in production; use a debug-only test helper if the test churn is too large. Allow Discard while busy only for staged/interrupted, never for claimed.
5. **Camera (required next slice).** Add B's dismiss guard/copy now as mitigation; implement A's `.camera` body, separate Glimpse resume view, 1 MiB cap, protected/excluded store, and OCR/question/concept/mode preservation as the next slice. Do not route camera through `Assistant.handle` and do not claim durable capture until it lands.

**Do not graft B's no-resume policy wholesale.** A's explicit retry is acceptable only when the process lock proves the old owner is dead, the input row is `.interrupted`, the effect ledger is `.none` (no attempt), and the user sees a warning that a cloud read or transcription may repeat. If the parent will not accept any possible repeated cloud read, adopt B's no-resume interrupted state as a safety default, but add a "Start a new request with this text" action (new ID) and a copy/reveal path; Discard-only is not honest user recovery.

## Exact chosen API, identity and process ownership

```swift
// One identity. No second UUID, no epoch.
public struct UserRequestID: Hashable, Sendable, Codable { /* existing */ }

public enum RequestOrigin: String, Sendable, Codable { case typed, share, voice, shortcut, camera }
public enum RequestInputState: String, Sendable, Codable {
    case staged, claimed, interrupted, completed, discarded, expired
}
public enum RequestInterruption: String, Sendable, Codable {
    case appStopped, handleFailed, transcriptionFailed
}
public enum EffectUncertainty: String, Sendable, Codable {
    case claimedWithoutReceipt, ambiguous, unreadableRow, policyUnavailable
}
public enum RequestInputBody: Sendable, Equatable {
    case text(String)
    case sharedText(utterance: String, text: String)
    case voice(wav: Data, duration: TimeInterval)
    // slice 2:
    case camera(jpeg: Data, question: String, concept: String?, mode: String, photoText: String)
}

public struct RequestInputSummary: Sendable, Equatable, Identifiable {
    public let id: UserRequestID
    public let origin: RequestOrigin
    public let preview: String              // 160 chars, cleared on terminal
    public let byteCount: Int
    public let createdAt: Date
    public let expiresAt: Date
    public let state: RequestInputState
    public let interruption: RequestInterruption?
}

public struct ClaimedRequestInput: Sendable, Equatable {
    public let id: UserRequestID
    public let body: RequestInputBody
    public let origin: RequestOrigin
    public let transcript: String?          // voice, written once
    public let createdAt: Date
    public let capturedTimeZoneID: String
    public let expiresAt: Date
}

public final class RequestInputStore: @unchecked Sendable {
    public init(directory: URL, policy: RequestInputPolicy = .standard,
                now: @escaping () -> Date = Date.init) throws

    public var isExclusiveOwner: Bool { get }

    @discardableResult
    public func stage(_ body: RequestInputBody, origin: RequestOrigin) throws -> RequestInputSummary
    public func claim(_ id: UserRequestID) throws -> ClaimedRequestInput
    public func retryInterrupted(_ id: UserRequestID) throws -> ClaimedRequestInput
    public func setTranscript(_ text: String, for id: UserRequestID) throws
    public func complete(_ id: UserRequestID) throws
    public func interrupt(_ id: UserRequestID, reason: RequestInterruption) throws
    public func discard(_ id: UserRequestID) throws
    public func recoverOnLaunch() throws -> [RequestInputSummary]  // owner only
    public func summaries() throws -> [RequestInputSummary]        // excludes .claimed
    @discardableResult public func purgeExpired() throws -> Int
}
```

**Identity.** `stage` generates the only `UserRequestID`; the returned summary's ID is passed to `Assistant.handle`, `DraftCard.requestID`, and `action_attempts.request_id`. A retry keeps the same ID and body; a new user request gets a new ID. No global current-request slot, no second store, no second identity.

**Process ownership.** `StoreOwner` holds a process-wide registry entry and an exclusive `flock` on `<store>/owner.lock` for the store's lifetime. `isExclusiveOwner` is true only when both are held. Only the owner runs recovery, claims, transcript writes, completion and interruption. A non-owner can stage (the owner will see it) and read summaries; it cannot convert or claim. The owner lock is released by process death; the next owner converts a still-claimed row to `.interrupted`. `recoverOnLaunch` is one-shot per owner instance. This answers "is the prior owner dead?" without an epoch, heartbeat, or workflow state.

**Recovery policy.** `EffectLedger.requestState(for:)` returns `.none`, `.awaiting(DraftCard)`, `.settled(EffectResult?)` or `.uncertain(EffectUncertainty)` using the existing row, decoder and card. `RequestResumePolicy` maps input × effect to `.run(warning?)`, `.showCard`, `.alreadyFinished`, or `.blocked`. `.run` is offered only for `.staged/.interrupted + .none`, after the owner lock; `.interrupted` carries a `ResumeWarning` for possible repeated cloud read/transcription. `.awaiting` shows the card and completes the input. `.settled` completes the input and shows the result summary if available. `.uncertain` blocks Resume and offers Discard. No branch calls `handle` from launch or `busy` clear.

**Caller API.** Use one receipt enum and B's sync/async split:

```swift
public enum SendReceipt: Sendable, Equatable {
    case started(UserRequestID)                 // claimed; turn running
    case deferred(UserRequestID)                // saved; not running
    case completed(UserRequestID, message: String) // async send returned
    case refused(String)                        // not saved; nothing sent
}
func submit(_ text: String, sharedText: String? = nil,
            origin: RequestOrigin = .typed) -> SendReceipt
func submitVoice(_ recording: VoiceRecording) -> SendReceipt
func send(_ text: String, sharedText: String? = nil,
          origin: RequestOrigin = .share) async -> SendReceipt
func resume(_ id: UserRequestID) async
func discard(_ id: UserRequestID)
```

`submit` stages synchronously on the main actor before checking `busy`; it starts a `Task` only after claiming and setting `busy`. `send` stages synchronously, claims if idle, and awaits the same `run` core. Both return `.refused` with a message that says "not saved; nothing was sent." `SendReceipt.message` is a computed property: `.started`/`.deferred` map to the running/saved copy, `.completed` carries the reply, and `.refused` carries the failure. `HandleTextIntent` maps `receipt.message`; typed/share callers restore on `.refused`.

The two Core signatures that complete the identity/resume contract are:

```swift
public func handle(_ utterance: String,
                   requestID: UserRequestID,       // no production default
                   isResume: Bool = false,
                   sharedText: String? = nil) async throws -> AssistantTurn

public enum RequestEffectState: Sendable, Equatable {
    case none
    case awaiting(DraftCard)
    case settled(EffectResult?)
    case uncertain(EffectUncertainty)
}
public enum ResumeBlock: Sendable, Equatable {
    case effectUncertain(EffectUncertainty)
    case interruptedNoRetry
    case notResumable
}
public enum ResumeDisposition: Sendable, Equatable {
    case run(ResumeWarning?)
    case showCard(DraftCard)
    case alreadyFinished(EffectResult?)
    case blocked(ResumeBlock)
}
public enum ResumeWarning: Sendable, Equatable {
    case mayRepeatCloudRead, mayRepeatTranscription, mayRepeatLocalMemory
}
extension EffectLedger {
    public func requestState(for requestID: UserRequestID) throws -> RequestEffectState
}
```

`isResume` is the only new policy input. It forces a review card for any selected capability with a `.datetime` argument; it does not reparse against a fabricated capture time. `requestState` is read-only, uses the existing `action_attempts_request` index, decoder, contract and card builder, and adds no column or phase.

**Policy values (recommended, transparent, no user signoff needed).** 24 h TTL; 8 active rows; 8 MiB total active body bytes; 24,000 text characters; 2 MiB voice; 30-day tombstone; 160-character preview; camera 1 MiB and 1 h in slice 2. Active means `staged|claimed|interrupted`; terminal tombstones do not count. A stage that would exceed refuses with `.capacity`; nothing is evicted. The card shows the absolute expiry.

## First verifiable implementation unit

**PocketCore only, Linux `swift test`, no AppModel, no UI, no new effect phase:** `RequestInputStore` + `StoreOwner` + the store tests. This is the riskiest unit and the one that must not codify A's current live-claim bug.

Minimum tests in that unit:

1. `testStageIsAtomicAndImmutable`: stage a text/share/voice body; the row and body exist together; a second body cannot replace the first; terminal deletion removes body, preview, transcript and interruption reason; the tombstone keeps only ID, origin, timestamps and byte count; a terminal row cannot be resurrected; `setTranscript` second write throws.
2. `testOneClaimWins`: eight concurrent claims; exactly one body; the rest `.alreadyClaimed`; no second body read.
3. `testOwnerLockProtectsLiveClaim`: store A claims R; store B on the same directory cannot become owner; B's `recoverOnLaunch` does not convert R; B's `claim`/`retryInterrupted` is refused; A completes R. Then A claims a second row R2, releases the store, and B acquires ownership and converts R2 to interrupted. This is the test A's current `testReopenTurnsClaimedIntoInterrupted` must be replaced with.
4. `testKillMatrix`: reopen at stage, after claim, after `setTranscript`, after terminal delete; owner recovery produces staged/interrupted/expired as appropriate; a corrupt row is reported as a storage error and is not claimable; no `handle`, no effect call.
5. `testCapsIncludeInterrupted`: stage until the cap; interrupt rows; a new stage refuses; total bytes include interrupted bodies; expiry purges both.
6. `testUnicodeNulAndExpiry`: exact Unicode round-trip, NUL rejected, expiry deletes the body and leaves only a text-free tombstone.

Second unit: `Assistant.handle(requestID:isResume:)` with no production default, `EffectLedger.requestState(for:)`, and the date-review policy test (`calendar_create`/`reminder_create` on resume must stage a card, never auto-act). Third unit: AppModel `submit`/`send`/`resume`/`discard`, ChatView saved card, VoiceCapture stop-keeping-file, and the Xcode/Simulator tests. Device tests for file protection, backup exclusion, kill/relaunch and VoiceOver remain separate and must not be claimed from Linux.

## Blockers the parent must settle before implementation

1. **Process model and owner policy.** Confirm whether `openAppWhenRun` App Intents run in the app process on the target OS. Even if they do, add the owner lock; decide whether a non-owner may stage (recommended) and whether it may discard (recommended for staged/interrupted only). If intents can run in a second process, the owner lock is not optional; a cross-process `busy` policy may also be needed so two turns do not run concurrently. Do not use an epoch alone.
2. **Relative-date policy.** Approve the "force a review card for any `.datetime` capability on resume" rule, with captured time and newly resolved instant shown. Reject A's current "card always shows the instant" assumption for `.modelMayAct`. This determines the `handle`/`evaluate` signatures and the UI copy.
3. **Retry/cloud policy.** Decide between A's explicit retry with `requestState == .none` plus a warning, and B's no-resume interrupted state with a "start a new request" recovery. Either is defensible; silently retrying a request that may have made a cloud read is not. The parent should also decide whether voice/share retries are allowed at all.
4. **Retention scope.** Decide whether `_sharedText` null-on-settle/cancel and its TTL land in this change or a named follow-up. Also confirm that active caps include interrupted rows and that `source_label`/`interrupt_reason`/transcript are cleared or coded. Do not claim retention-complete while confirmed read cards keep the document text in the backed-up database.
5. **Camera scope.** Schedule A's camera slice as required work before claiming durable capture flows; the dismiss guard/copy is mitigation, not preservation. Decide the camera TTL (1 h recommended) and whether the OCR `photoText` is retained with the JPEG.
6. **Implementation choices.** Add a `SQLiteDB` journal-mode/secure-delete option or a private store wrapper; define atomic/file-protection/backup behavior for the separate DB and lock file; remove the composer/mic busy disables; guard `resume` on model readiness; remove the production `requestID` default; and keep voice out of the store when upload is disabled or the API key is missing. These are small but they are not optional if the acceptance tests are to mean anything.

## Minimizing state machinery

- One `UserRequestID`, one immutable body, one claim CAS, one terminal tombstone. No queue, scheduler, background drain, step table, or new `AttemptPhase`.
- The input state machine is small: `staged→claimed→completed|interrupted`; `staged|interrupted→discarded|expired`; reconciliation may complete a staged/interrupted row when the ledger already has the effect; and explicit `interrupted→claimed` retry. Do not add a generic `setState`.
- Process ownership is a lock and a boolean, not a lease/heartbeat/epoch table. The lock answers the only question that matters: is another live store owner present?
- Resume review is one `isResume` flag and one card; it is not a new state.
- The retry warning is UI copy over the existing `.none` effect state; it is not a new journal.
- Voice transcript is a nullable write-once column on the claimed row; no `.transcribing` state. Claim first, then transcribe; on failure `interrupt` and let the explicit retry policy decide.
- The effect ledger stays the only effect authority; the only addition is a read-only `requestState` query. No second effect journal, no fake reply-only attempt.
- Camera is one new body case and a separate view-resume path; it is not an effect and not a workflow.
- Delete `SharedInbox`; keep one ingress path. `busy` clearing only ends work; launch only projects. No automatic resume anywhere.

## Bottom line

A's store is the right base because it makes body ownership and state transitions one atomic resource, and because its effect-state query is the only thing that can honestly distinguish "no action started" from "awaiting card" from "uncertain." B's caller behavior, source enum, accessibility labels, and no-resume safety instinct are worth grafting. Neither design is safe as written: A must not ship its per-instance recovery flag or its resume-time date reinterpretation; B must not ship its file+row orphan race or pre-CAS transcription. The first implementation unit should be the owner-locked `RequestInputStore` and its Linux tests, because that is where the duplicate-effect and duplicate-upload bugs would otherwise be frozen into the schema.
