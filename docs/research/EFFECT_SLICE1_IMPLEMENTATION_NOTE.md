# Effect recovery — Slice 1 implementation note

Historical checkpoint: the implementation and test counts below describe the
original Slice 1 integration. Production shared reads now pass `sharedText`
directly; the former `SharedInbox` handoff described here is no longer used.
For current repairs, test evidence, and remaining gaps, see
[Action review repairs](../verification/REVIEW_REPAIR_STATUS.md) and the
[orchestrator ledger](../../ORCHESTRATOR_LEDGER.md).

Status: Slice 1 integrated into the prepared `t3/635e8031` checkout at base
`4bf72c9`. The recovery snapshot from the cancelled run (`009430f` plus
uncommitted work) was hash-checked against its manifest, applied with
`git apply --3way` for tracked files, and its five new files were extracted.
Overlaps with the newer privacy repairs were resolved in favour of the current
`CloudTurnComposer` path while keeping the typed `ReadResult` metadata.

This note covers the Linux `PocketCore` suite and Swift frontend syntax parsing.
There is no Xcode typecheck, signed build, Simulator run, device result, or
model/calibration/prompt change. No later Slice 2+ schema, workflow engine,
callback scheme, AlarmKit manager, compensation, or Muse proposer was added.

## Implemented

- `core/Sources/PocketCore/EffectLedger.swift` owns the compiled capability
  catalog, typed bindings, persistent `action_attempts`, claim/receipt
  classification, launch recovery, draft cards, edits, cancellation, and the
  one `EffectSession` used by both immediate model acts and confirmation.
- `core/Sources/PocketCore/Assistant.swift` creates one `UserRequestID` per
  utterance. `toolPath` and `planSkillCore` route compiled/user-handoff effects
  through the session. The old `assistant.confirm(PlannedAction)` and
  `ActionExecutor.perform` path is removed. `confirmEffect`, `editEffect`,
  `cancelEffect`, and `recoverEffects` are the app-facing surface.
- `core/Sources/PocketCore/ActionPlanner.swift` keeps binding schemas from the
  compiled catalog, routes explicit “Email …” requests to compiled
  `email_compose` (BF-1), and reads `memory_recall` from `MemoryStore` instead
  of the old placeholder (BF-2).
- `CloudPrivacy.swift` keeps the current full-text, windowed, fail-closed
  screening. The only additive change is an optional `onDecision` observer so
  `reason` can return the sensitivity decisions in `ReadResult` without a
  mutable last-result field. `ActionPlanner.reason` now returns `ReadResult`
  with provider, scrubbed payload, withheld flag, and decisions on the
  immediate and confirm read paths (BF-3). Privacy policy, model, prompts, and
  thresholds are unchanged.
- `app/PocketGlimmer/Actions/PocketEffects.swift` is the only `PhoneEffects`.
  EventKit saves use the bound concrete `Date`, append a `pg-attempt:` note,
  read back by identifier/title/minute/token, and treat write-only access as
  unverified. Messages and Mail return typed sheet results with the exact
  selected labelled destination and no `sms:`/`mailto:`/Shortcut fallback
  inside an attempt. URL/Shortcut acceptance is only a handoff.
- `SystemActions.swift`, `SkillRunner.swift`, `AppModel.swift`, and
  `ChatView.swift` are migrated to the ledger path. Cards survive relaunch,
  show the resolved full date/time/timezone, allow body/contact/method/time
  edits, and surface `userSummary` instead of a swallowed failure. Cancel
  settles the durable row.
- Contact binding stores the contact identifier plus the exact labelled
  method/value. Confirm re-resolves the identifier and revalidates that exact
  method; it never selects the first method or falls back to another one.
  Removing or relabelling the method pauses with refreshed choices.
- Reply-only `email_digest`/`analyze_document` confirmations are staged with a
  copied payload so they survive relaunch, but they settle as `.read` and never
  call `PhoneEffects` (F7). A second confirmation is `ignoredTerminal`.
- Auto-reply memory uses a semantic postcondition (an active fact with the same
  subject/attribute/value) and does not put attempt UUIDs in user-visible fact
  text (F6).
- Custom URL templates are limited to http/https, reject contact/raw-URL
  placeholders, show the actual host as the card title and destination, and
  persist the concrete template before approval (F14).
- `SkillArgs.time` now preserves explicit zone/city qualifiers for Shortcut
  handoff phrases as well as the EventKit heuristic extractor.

## Deliberate differences and limits

1. **Reply-only confirmation uses the attempt table.** `email_digest` and
   `analyze_document` may be staged as `awaitingUser` rows with copied payload
   and later confirmed to `.read`. They are not effects and never reach
   `PhoneEffects`. This is a narrow exception to “reads are not attempts”.
2. **No later-slice schema or API.** No workflow definitions, callback columns
   or URL scheme, `RunPicture`, claimed read-back attachment, AlarmKit manager,
   or compensation. `alarmkit_schedule` is compiled at version 1 with
   `availability: .notWired` and fails `.unavailable`; it never substitutes
   `alarm_create`.
3. **EventKit evidence still requires the attempt token.** The token check was
   not weakened based on unverified sync-stripping conjecture. Immediate and
   confirm paths require identifier + title + minute + `pg-attempt:` token.
   Notes are appended, not overwritten.
4. **Sheet contention is non-terminal.** `notStarted(.sheetBusy)` returns the
   card to `awaitingUser` with a retryable notice; denied access and
   `canSendText()/canSendMail()` false are terminal failures. Sheet task
   cancellation dismisses and resumes the owned continuation once. UIKit
   behaviour is not device-tested.
5. **Reply-only email digests keep their SharedInbox copy but do not consume
   the in-memory inbox at stage time.** The copied text lives in the durable
   row. No queue or reorder of busy input was added.
6. **No automatic card cancellation.** An unrelated `send` does not cancel an
   active card. The card remains until Confirm or Cancel.
7. **Unknown policy versions stay visible.** Launch recovery surfaces an
   unknown-version pending row in `LaunchRecovery.unresolved` with a “policy
   version this build does not have” warning. Confirm renders a non-confirmable
   stale card and performs nothing. A claimed row with no receipt is also
   unresolved and is never replayed. Added
   `testUnknownContractVersionStaysVisibleAndNeverExecutes`.
8. **Input ownership is intentionally untouched.** `AppModel.send` returns
   while `busy` before `SharedInbox.put`, so a busy request can lose its shared
   text. Moving the put before the guard would overwrite the active request’s
   single-slot document. The parent owns the durable request-bound input
   repair; this slice only records the gap in a code comment and here.
9. **Body edits are applied at Confirm.** Contact/method/time choices persist
   immediately through the revision-guarded edit path. Free-text body edits
   live in `ChatView` state and are sent with the confirmation, so they are not
   durable while the user is still typing. The original staged body does
   survive relaunch.
10. **Attempt bodies are not purged.** Full message/document text remains local
    in `args_json` (Slice 6/F13 work).
11. **Read-path privacy ownership.** BF-3 metadata now travels on the typed
    read result, but the separate export-null-context and memory-alias omissions
    remain parent-owned and are not claimed fixed here. No read-path parity
    beyond the current privacy repair is claimed.
12. **Reply-only cloud skills** stay on the current reply path; they are not
    journaled as effects or workflow steps.

## Verification actually run

```
docker run --rm -v "$PWD/core:/src" -w /src swift:6.1-noble \
  bash -lc 'swift build --scratch-path /tmp/pg-build-slice1 && \
  swift test --scratch-path /tmp/pg-build-slice1'
```

- 172 tests executed, 1 skipped (the opt-in live Meta API test), 0 failures.
- The two old privacy regressions from `009430f` now pass because the prepared
  checkout already contains the newer privacy repairs. They were not weakened
  or deleted; only `reason` assertions migrated from `String` to
  `ReadResult.text`.
- `EffectRecoveryTests` covers the Slice 1 gates: file reopen, concurrent
  confirm, claim-without-receipt, claim-before-EventKit, unparsed time,
  same-title hint plus a second request, permission zero saves,
  Messages/Mail typed results, URL-vs-send, explicit draft, ambiguous and
  multi-method contacts, user JSON override, started-handoff replay, past
  instant correction, concurrent conflicting edits, compiled schema drops,
  autoreply postcondition, reply-only payload reopen, sheet busy/cancel, user
  handoff host/snapshot, mismatched evidence, explicit zone phrase, and
  unknown-version visibility.
- `SkillsTests`/`TakeoverRegressionTests` cover the email route, memory recall,
  low-confidence message draft, and cloud metadata on immediate and confirm
  read paths.
- App Swift files were parsed with:
  `find app/PocketGlimmer -name "*.swift" -print0 | xargs -0 swiftc -frontend -parse`
  (exit 0). This is syntax only; no UIKit/EventKit/SwiftUI typecheck or build
  was possible here.

## Still open before this is a shipped phone result

- Xcode build/typecheck, signed install, and the device gates in
  `docs/research/IOS27_END_TO_END_JOURNEYS.md` A1–A20.
- EventKit notes/token round-trip and `calendarItem(withIdentifier:)` behaviour
  on local and synced calendars; write-only read-back; DST/timezone phase.
- Contacts unified identifier stability after linking/limited-set changes;
  exact labelled method resolution on device.
- MessageUI/Mail contention and cancellation on device; Shortcut handoff
  results; alarm Shortcut phrase compatibility.
- Parent-owned input deferral, export null-context, and memory-alias omissions.
- Slice 2 definitions/triggers, Slice 3 callbacks, AlarmKit, compensation,
  retention/purge.
