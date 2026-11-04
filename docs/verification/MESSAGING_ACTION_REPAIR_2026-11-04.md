Parent integration checkpoint, 2026-11-04. Do not treat the original worker report below as independent release approval. A fresh review reproduced 19 failures in 32 probes against d99c671; the parent reproduced the same 19 failures on the combined source before repairing it. The delivered review file is literally truncated after M3. The parent used its intact high findings, final summary and full executable repros rather than inventing the missing text.

The repairs make asked-field context govern follow-ups, preserve lowercase names and question/imperative bodies, isolate channel parsing from marked message text, handle named cancellation and stale-draft continuation, and keep explicit messages away from unrelated confident skill picks. A compiled message can now produce a review card without the optional registry. One review assertion was corrected to accept that complete card instead of requiring an unfinished draft; it now also checks the original tool-choice miss, preserved body and zero execution. Two print-only probes were removed from the maintained suite. Three additional regressions cover literal bodies and Contacts refresh after grant/denial.

Diagnostics now contain UUIDs and closed capability/phase/outcome enums; an arbitrary capability string is rejected at the recording boundary. Settings exposes diagnostics export/share. Contact cards expose Allow Contacts/Refresh contact and an iOS Settings link for denied access. Refresh rebinds the original search on the same attempt and revision and never performs an action. Existing drafts are retained at the five-draft cap rather than silently evicting one.

Parent full suite: 314 executed, one pre-existing opt-in live skip, zero failures. Evidence: [before repair](messaging-parent-before.txt), [after repair](messaging-parent-fixed.txt), [app syntax check](messaging-app-parse.txt). The suite uses scripted model choices and fake phone effects. A Linux parse is not an iOS typecheck. Independent fix-diff review, Xcode build and real phone messaging remain pending. Incomplete message drafts are still session memory; input-store caller integration is separate and unfinished.

---

# Messaging action repair (implementation worker)

Date: 2026-11-04. Scope: reported two-turn messaging failure in core/app logic,
including clarification follow-ups. No push or PR; parent integrates.

## Traced root cause

Turn 1 (`text Dana`) ended in a bare `.clarify` string on every path: the trained
tool path asked for the body and the skill path asked
`Did you mean ...? restate with app name, recipient and message` when skillPick
missed. Nothing was retained. Turn 2 (the details reply) entered a stateless
`Assistant.handle`, routed to `answer_local`, and generated `Hi Dana!` as chat.
The intent was lost at turn-2 routing, not turn-1 parsing. A regex-only fix
cannot recover it. All model decisions below are scripted test doubles, not
real-model behavior.

## Behavior contract now

- An explicit message command ends as an editable staged card, a retained typed
  draft plus a precise question, or a precise unsupported response. It never
  reaches chat generation on any route, with or without the skill registry.
- The pending shape is `MessageDraft`: request-bound, with optional contact,
  channel, body, a low-confidence flag, last-asked field, and creation time.
  There is no global text slot.
- The follow-up is classified deterministically: complete, update, cancel,
  keep-and-ask, disambiguate, or fall through as a new/unrelated request.
  Unrelated, new, and negative utterances never fill the draft. Multiple or
  stale drafts ask which one. Completion stages through the existing ledger
  session; only an explicit Confirm tap acts.
- No guessed recipient or channel. Bare `dm` asks for the app. Low-confidence
  retention is labeled and keeps the model decision evidence.
- Existing guarantees preserved: contact/method binding, body review, native
  composer, honest accepted/cancelled/failed outcomes, no automatic send.

## Changed files

- `core/Sources/PocketCore/MessageDraft.swift` (new): `MessageChannel`,
  `MessageDraft`, `MessageCommand` detector, `MessageFollowUp` binder.
- `core/Sources/PocketCore/ActionDiagnostics.swift` (new): bounded secret-free
  event ring (request/attempt ID, capability, phase, fixed code) with JSONL export.
- `core/Sources/PocketCore/ActionPlanner.swift`: detector delegates to the shared
  command parser; skill path retains drafts on missing args, below-tau picks,
  and empty retrieval; contraction guard in name extraction.
- `core/Sources/PocketCore/Assistant.swift`: `handle(pendingDrafts:)`, follow-up
  interception, explicit-misroute guard, `sendMessageToolPath`,
  `stageCompletedDraft`, recipient-first extraction.
- `core/Sources/PocketCore/EffectLedger.swift`: `notDetermined` contacts pause
  with a precise notice; stored specific notices win over generic re-derived
  ones on cards. No time guard/parser change.
- `app/PocketGlimmer/AppModel.swift`: `send` carries up to 5 drafts, applies
  consume/update results, tags deterministic follow-up badges, records card
  projection, exports `action-diagnostics.jsonl` to Documents.
- `app/PocketGlimmer/Actions/SystemActions.swift`: compose callbacks verify
  controller identity (late/wrong-controller callbacks are ignored and logged);
  explicit `requestContactsAccess()` for user-visible retry.
- `app/PocketGlimmer/Actions/PocketEffects.swift`: presentation
  requested/accepted/cancelled/failed/unavailable/busy diagnostics with ticket IDs.
- Tests: `core/Tests/PocketCoreTests/MessageDraftTests.swift` (new, 25 tests);
  `SkillsTests` below-tau message case now pins draft retention, and the
  choices-clarify case moved to a non-message utterance.

## Tests (scripted, Docker swift:6.1-noble)

Full core suite: 228 tests, 1 opt-in live skip, 0 failures. Baseline before the
fix was 203 with the same skip. New coverage: polite/recipient-first detection
and extraction, first-turn retention (body/recipient/channel), follow-up
completion into a confirmable card with zero generation calls, short-answer
binding, unrelated/new/negative isolation, multi-draft and stale disambiguation,
low-confidence labeling with decision evidence, channel-answer flow, misrouted
tool recovery, email exclusion, double confirm (one perform), contacts
not-determined/denied notices, unavailable composer, no-registry bypass, and
secret-free diagnostics export.

iOS app sources: `swiftc -frontend -parse` passes on the three touched files.
Parse is not a typecheck; the Mac owner compiles the integrated result.

## Limits and next verification

- No real-model measurement: routing under the shipping model, calibration,
  and tau is unproven. Run the scripted utterances against the real model and
  record route/toolChoice/skillPick outcomes before claiming device behavior.
- No device proof: no composer presentation, no accepted/cancelled/failed
  observation, no permission-prompt flow. Needs the Mac build plus the
  `action-diagnostics.jsonl` export and manual send-or-cancel runs. No real
  personal message was sent here.
- Text follow-ups do not pick among staged card choices (contact ambiguity
  still resolves by tapping the card) and do not confirm staged cards (`yes`
  stays chat). Email keeps bare clarification without drafts.
- Parent-owned follow-ups: `AppModel.confirm/edit` privacy work, cloud/read
  recovery, `requestContactsAccess` UI wiring, and the send-error projection
  helper were not touched.
