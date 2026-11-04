# Independent FIX-DIFF review — shared read input, recovery, and outcome copy

Reviewer: DeepSeek V4.1 Flash 1017 through River 08 / OpenCode at max.
Checkout: `/home/habib/.t3/worktrees/pocket-glimmer/t3-bcf5b8aa` at `5912cd7`, working tree clean.
Scope: functional diff `b7f2d37..5912cd7` — `core/Sources/PocketCore/Assistant.swift`,
`core/Sources/PocketCore/EffectLedger.swift`, `app/PocketGlimmer/AppModel.swift`, and the new
`core/Tests/PocketCoreTests/SharedReadRecoveryTests.swift`. Docs were treated as claims, not proof.
No repository edits, commits, pushes, PRs, paid calls, or subagents. Scratch tests live only in
`/tmp/pg-shared-read-fix-review-scratch/core`; logs live only in this directory.
No Mac, Xcode, iOS SDK, or device was available. The app findings below are source inspection,
not Linux-parse-as-typecheck and not a phone run.

## Verdict

- **C1 — PASS (source + core evidence).** The immediate `.local` reply and the confirmed-read
  `.read` reply both carry `cloudPromptSent` into `ChatItem`; the fallback badge is no longer
  "on device"; the privacy button appears whenever the payload is present.
- **C2 — PASS.** Shared text is used on all three non-tool routes, the complete assembled
  document is screened before a cloud send, a late-document sensitive marker withholds, and the
  local fallback retains the document. The route-`tool` limitation is noted below.
- **W1 — PARTIAL.** Cancellation propagates, the row becomes `ambiguous(.claimedWithoutReceipt)`,
  the false "Nothing was sent" copy is gone, and a second confirmation does not replay. But a
  failed/ambiguous read still discards the exact outbound payload, and the app leaves the card's
  old **"on device"** badge beside the new "may already have been sent" summary. That is a real
  P2 transparency gap, not a leak.
- **W4 — PARTIAL.** The confirmation catch now says completion could not be verified and warns
  that the request may already have been sent/acted on; a simulated receipt-write failure after a
  performed effect throws, stays claimed, and does not replay. The `AppModel.edit` catch still
  says **"Nothing was changed."** after `updateAwaiting` may have committed (P3).
- **Overall fix diff: PASS for C1/C2 and for the central W1/W4 false statements; not a complete
  W1/W4 closure.** No new P1 was found. Release readiness is not claimed: C3/C4/W2 and W3 remain
  open, and no device/Xcode behavior is verified.

## Findings, graded

### P2 — Ambiguous terminal read keeps a stale "on device" badge and loses the exact payload

**Where**
- `app/PocketGlimmer/AppModel.swift:246` — a read card is created with `badge: onDevice`.
- `app/PocketGlimmer/AppModel.swift:275-277` — on `.finished` / `.ignoredTerminal`, only
  `card` and `text` change; `badge`, `cloudPromptSent`, and `keptOnDevice` are left as they were.
- `app/PocketGlimmer/AppModel.swift:287-288` — a cancellation/error catch appends a system
  message but leaves the card and its old badge in place.
- `core/Sources/PocketCore/EffectLedger.swift:1173-1175` — the new ambiguous-read summary says a
  cloud request may already have been sent.
- `core/Sources/PocketCore/EffectLedger.swift:1617-1622` — every read error records
  `.ambiguous(.claimedWithoutReceipt)` and discards the in-scope `ReadResult` (including
  `cloudPromptSent`).
- `app/PocketGlimmer/Views/ChatView.swift:94-101` — the privacy button exists only when
  `item.cloudPromptSent != nil`.

**Reachable shape**
A confirmed read (for example `email_digest`, whose confirmation floor is `.always`) can send a
screened document to the cloud and then fail or be cancelled. The row becomes ambiguous. The
summary reads: "The read has no verified result. A cloud request may already have been sent."
The same bubble still displays its original "on device · N ms" badge, and there is no privacy
button because `cloudPromptSent` was discarded. For cancellation the card and badge remain and
the disclosure is a separate system line. The user gets a warning, but the prominent label
contradicts it and the exact text is unavailable.

**Evidence**
- Repository tests verify only the summary strings (`SharedReadRecoveryTests.swift:93-130`), not
  payload retention or app badge projection.
- `/tmp/pg-shared-read-fix-review-20261104/scratch-verification-tests.log`:
  `testConfirmReadRealChainCancellationIsAmbiguousAndTerminal` passes through a real
  `CloudBrainChain` `URLError(.cancelled)` and confirms the ambiguous/no-replay behavior.
  `testReadReceiptWriteFailureLosesExactPayloadButKeepsAmbiguousCopy` confirms that a successful
  read whose receipt write fails becomes ambiguous with no payload in `EffectResult`.
- App projection is source-inspected only; there is no app test target in this checkout.

**Focused repair (smallest useful)**
When a terminal/ambiguous reply-only result is projected, clear or replace the badge with an
"unverified · cloud request may have been sent" label and keep any available payload. Preserve
the payload when `read` returned but `ledger.record` failed; for a cancellation thrown after the
send, carry the screened text on a typed cancellation/uncertainty error so the app can expose it.

### P3 — `AppModel.edit` still claims "Nothing was changed" after a possible commit

`core/Sources/PocketCore/EffectLedger.swift:1554-1560` commits `updateAwaiting`, then evaluates
`try ledger.duplicateHint(...)`. If that read fails (storage I/O), `AppModel.edit` catches and
prints `"Couldn't update that card: … Nothing was changed."` at
`app/PocketGlimmer/AppModel.swift:303`. The card edit did persist. This is the remaining
edit-path half of W4; no external effect occurred, so the risk is draft-state transparency rather
than an unsafe write. A narrow fix is to use the same "completion could not be verified" copy, or
make the read failure occur before the commit.

### P3 — Launch recovery silently skips ambiguous read rows

`core/Sources/PocketCore/EffectLedger.swift:915-916` treats `.settled` and `.ambiguous` the same
and skips both. A scratch test (`testAmbiguousReadIsNotSurfacedByLaunchRecovery`) stages a read,
cancels it, reopens the ledger, and confirms both `showAgain` and `unresolved` are empty while the
row is durably ambiguous. The immediate UI disclosure exists, but a kill/relaunch before the
summary is rendered leaves no notice that a cloud request may have gone out. The re-confirm
summary does disclose it; the parent's phrase "restored summaries" is true only in that narrow
sense. The claimed crash gap is similar: `EffectLedger.unresolvedSummary` for reply-only says
"A read was interrupted. It will not run again." without the possible-send sentence
(`EffectLedger.swift:1152-1153`).

### P3 — Immediate share cancellation/error has no payload or possible-send disclosure

The new `Assistant.swift:156-163` branch can send a long shared document to the cloud. If the
read throws (including `URLError(.cancelled)` propagated through `reason`), `AppModel.send` only
prints `"Error: …"` at `app/PocketGlimmer/AppModel.swift:254-257`; there is no `AssistantTurn` and
therefore no `cloudPromptSent`, badge, or privacy sheet. The confirmed-read path now has an
ambiguous summary; the immediate path does not. This is the same transparency class as W1, and it
predates the diff for other read paths, but the new default-share branch makes it reachable
without an explicit skill command.

### P3 — Shared text attached to a route-`tool` request can still be ignored

`Assistant.swift:156` guards on `route.chosen.id != "tool"`. On a `tool` route, a non-skill tool
can still answer or act without the shared document. The fix intentionally covers only non-tool
routes (the tests check A/C/D); the default share phrase is likely non-tool, but the route
classifier is not a guarantee. This is a residual scope limitation of C2, not a new regression.

### P3 — "On device" is not a local-only control

`testOnDeviceInstructionIsNotALocalOnlyControl` in the scratch log passes: a long benign document
shared with "Summarize this on device" is still sent to the configured cloud after screening. The
documented long-document path explicitly allows this, and the resulting badge/privacy sheet
disclose the provider, so it is a behavior note rather than a contract failure. If "on device" is
meant to be a control, it is not implemented.

### Test gaps (not functional failures)

- No app projection test exists for `ChatItem`/privacy-button behavior (C1's review asked for
  one), so a future initializer can drop the field again.
- `testFailedSharedReadKeepsTheOutboundPayloadWithLocalFallback` checks a marker and that a body
  exists, not that `turn.cloudPromptSent == messages.last.content`; the scratch test adds that
  equality.
- The new branch's late-document screening is not in the repository tests; the scratch
  `testDefaultShareScreensTheWholeDocumentThroughTheNewBranch` covers it.
- W1's review asked for a closure that captures a prompt before throwing; the added tests throw
  without preserving one, matching the code's remaining payload gap.

## Verification actually run

Docker image: `swift:6.1-noble`. Docker commands used `--user $(id -u):$(id -g)` and
`HOME=/tmp`; the tracked checkout stayed clean.

| Check | Result | Log |
|---|---|---|
| Full core suite | **PASS**: 189 executed, 1 skipped, 0 failures | `full-core-tests.log` |
| Targeted `SharedReadRecoveryTests` | **PASS**: 6 executed, 0 failures | `shared-read-recovery-tests.log` |
| Independent scratch checks | **PASS**: 9 executed, 0 failures | `scratch-verification-tests.log` |
| App projection / privacy sheet | **SOURCE INSPECTION ONLY**; no iOS SDK/typecheck/device | `app/PocketGlimmer/AppModel.swift`, `Views/ChatView.swift` |
| Xcode build, iPhone install, real Cloud/EventKit/Messages | **COULD NOT RUN** | no Mac/device |

Scratch checks (in `/tmp/pg-shared-read-fix-review-scratch/core/Tests/PocketCoreTests/ReviewScratchTests.swift`):

1. Default share on all three non-tool routes uses the document.
2. Failed cloud fallback retains the exact transmitted user message.
3. A sensitive marker after the local 2,500-character window withholds the cloud send through the
   new branch.
4. Confirm-read success retains the payload.
5. A real cloud-chain cancellation makes the read ambiguous and a second confirm does not replay.
6. A provider HTTP failure through a confirmed read returns the local fallback with the exact
   payload.
7. A receipt-write failure after a successful read keeps the honest ambiguous copy but loses the
   payload.
8. A receipt-write failure after a performed effect throws, stays claimed, and does not replay.
9. An ambiguous read is durable but not surfaced by launch recovery.

## Contract-by-contract evidence

### C1 — immediate and confirmed local fallback payload
- `AppModel.swift:237-241` passes `turn.cloudPromptSent` and selects the fallback badge when it is
  non-nil; `:278-285` does the same for `.read`.
- `ChatView.swift:95-101` makes the badge a privacy button exactly when
  `cloudPromptSent != nil`; `:116` feeds that text to `PrivacySheet`.
- Core evidence: scratch tests 2, 4, and 6 compare the transport's user message to
  `cloudPromptSent` exactly; repository test 55-68 also checks equality on success.
- Remaining: P2 badge/payload gap for terminal ambiguous reads; no app runtime test.

### C2 — shared documents on non-tool routes
- `Assistant.swift:156-163` calls `reason(utterance, text: sharedText)` after the skill override
  and before the route switch for every non-tool route.
- `ActionPlanner.reason` (`ActionPlanner.swift:289-315`) sends only through
  `CloudTurnComposer.prepareDocument`; `CloudPrivacy.swift:95-113` composes the instruction and
  the whole supplied text; `prepare` masks first, bounds, windows, screens every window, and
  withholds on uncertainty/sensitivity/scan failure.
- Repository tests 43-91 cover A/C/D, cloud payload capture, withholding, and fallback; scratch
  tests 1-3 add exact fallback text and a late-tail sensitive marker.
- Residual: route-`tool` shared text and no app-intent-level test. The new branch also executes
  `reason` directly instead of `stageRead`, so it does not run `confirmBeforeAct`; the share action
  is explicit and the cloud send is fully screened, so this is a product/consent-path choice, not
  a reproduced defect. A short document is answered locally by design.

### W1 — cancelled/failed read
- `EffectLedger.swift:1612-1623` records `.ambiguous(.claimedWithoutReceipt)` on any read error,
  rethrows cancellation, and returns the summary for non-cancellation failure.
- `EffectLedger.swift:1173-1175` supplies the "cloud request may already have been sent" copy for
  reply-only attempts.
- Repository tests 93-130 verify cancellation propagation, the ambiguous row, no replay, and the
  absence of "Nothing was sent". Scratch test 5 repeats this through a real cloud chain.
- Missing: exact payload retention (P2), stale app badge (P2), launch notice (P3), immediate-path
  disclosure (P3).

### W4 — effect receipt-write failure
- `AppModel.swift:287-288` replaces the false "Nothing was changed" confirmation copy with the
  may-have-been-sent/acted-on warning.
- Scratch test 8 simulates a receipt-write failure after a performed reminder: `confirm` throws,
  `performCount` stays 1, the row stays claimed, and a second confirm is terminal with no replay.
- Missing: `AppModel.edit` still claims nothing changed (P3); terminal effect/read badges remain
  stale (P2/P3).

## Not re-reviewed / still open

- C3 (calendar constraints), C4 (time extraction), and W2 (recipient/attachment variants) are
  unchanged and remain open per the assignment; they were not rediscovered here.
- W3 (provider-attempt attribution) remains open. The new local-fallback badge is still
  provider-agnostic, and the privacy sheet header is that badge.
- Xcode build/typecheck, signed install, iPhone launch, privacy-sheet interaction, Cloud providers,
  EventKit, Messages/Mail sheets, and latency/memory behavior remain unverified.

## Comment check

No new code-comment lines were added in the functional diff (`AppModel.swift`, `Assistant.swift`,
`EffectLedger.swift`, `SharedReadRecoveryTests.swift`). The only added comment-like text is in
documentation, not code comments. No comment-sicko finding applies.

## Logs

- `/tmp/pg-shared-read-fix-review-20261104/full-core-tests.log`
- `/tmp/pg-shared-read-fix-review-20261104/shared-read-recovery-tests.log`
- `/tmp/pg-shared-read-fix-review-20261104/scratch-verification-tests.log`
- Scratch source: `/tmp/pg-shared-read-fix-review-scratch/core/Tests/PocketCoreTests/ReviewScratchTests.swift`
