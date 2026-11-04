# OffLlama fix-diff review v2 (Reviewer A, independent)

Reviewer: fresh independent adversarial reviewer, Muse Wonder 1.0 MAX (user-assigned for this task). No subagents, no model/prompt/calibration changes, no pushes/PRs, no parent-checkout edits.
Checkout (read-only): `/home/habib/.t3/worktrees/pocket-glimmer/t3-c6663d3b` @ `f77e5e8fa3af56999f4f55ebc7c3cc196771e97f` (verified `git rev-parse HEAD`; `git status --porcelain` empty at start and end).
Scratch only: `/tmp/offllama-core-fix-review-v2-20261104/` (`core-clean/`, `core-head/` with added probe files, `core-4542/`, `logs/`).
Method: file-scoped diffs (the named originals `f327cae`/`d99c671` are side branches off `cc839e4`; branch-wide diffs conflate unrelated UI work, so slices were compared per file), source traces through callers, and executable probes against the real `Assistant.handle` / `EffectSession` / `FakePhoneEffects` / `RequestInputStore` interfaces in Docker `swift:6.1-noble`. Linux Swift is not an iOS typecheck; the installed phone still runs `7857cd68` and proves nothing about this diff.

## Verdicts (separate, per slice)

| Slice | Verdict | Basis |
|---|---|---|
| A. Input core (`f327cae` → `4542d69` → HEAD) | **PASS** on Linux evidence; **COULD NOT RUN** for Apple file-protection runtime (F3) | F1/F2/F4 repairs verified in source + 21 maintained store tests + capacity/owner probes. No caller wiring exists, so no voice/camera/ingress durability is claimed. One nit (A-1). Exact Mac checks listed below. |
| B. Messaging (`d99c671` → `7810437` + `f77e5e8`) | **FAIL** (2 warnings, 0 critical) | Old 32 repros: 31 pass, 1 fails only because behavior improved past its assertion (complete card instead of retained draft; the parent already corrected that assertion in the maintained suite). Both parent objections are reachable (B-1, B-2). No wrong execution anywhere: `performCount == 0` before Confirm in every probe. |
| C. Chart/group/repeat (`4afe1d9`, `f77e5e8`) | **FAIL** (2 warnings, 0 critical) | Named-group refusal before binding, literal-body and repeated-message invariants pass. Chart segmentation silently drops supplied numbers for comma-without-space / unpunctuated input (C-1); literal group words behind a bare `that` body marker are refused (C-2). Scripted-flow proof only, not live-model/iPhone proof. |

## Test evidence (actual counts, this session)

Commands (all Docker `swift:6.1-noble`, scratch copies; full logs in `logs/`):

- Pristine HEAD core: `swift test` → **329 executed, 1 skipped (pre-existing opt-in live Meta test), 0 failures**. Matches the parent claim in `docs/verification/message-boundaries-core.txt` and the decision trail.
- HEAD + old messaging repros (`ReviewReproTests.swift` copied in): **361 executed, 1 skipped, 1 failure**. The single failure is `testNoRegistryToolNoneRetainsDraft`, which now receives a complete `imessage_send` review card instead of a retained draft — strictly better than the old assertion; not a defect.
- Old repros alone: 31/32 pass (originally 19 failures / 32).
- Reviewer V2 probes (`core-head/Tests/PocketCoreTests/ReviewV2ProbeTests.swift`, 13 tests): 7 desired-contract failures across B-1 (×2 routes), B-2, C-1 (×2), C-2, A-1; passes include cancel-all safety, semicolon/newline charts, no-data non-rendering, repeat-after-wrong-tool, and candidate coverage prints. Logs: `logs/v2-probes.txt`, `logs/v2-probes2.txt`.
- Decision-trail corroboration: core at `4542d69` rebuilt and run → **256 executed, 1 skipped, 0 failures**, exactly the number recorded in `docs/ORCHESTRATOR_DECISIONS.tsv`. The 314/321 intermediate claims were not re-run; 329 was. No unsupported readiness claim found in the changed decision/feedback docs — they repeatedly state scripted-only, not installed, caller integration unfinished. That labeling is accurate.

## Findings

### B-1 [warning] Complete explicit message + empty candidate set: “tap Confirm” with no card

- **Location**: [ActionPlanner.swift](/home/habib/.t3/worktrees/pocket-glimmer/t3-c6663d3b/core/Sources/PocketCore/ActionPlanner.swift:124) `planSkillCore` no-candidate branch; text from [MessageDraft.swift](/home/habib/.t3/worktrees/pocket-glimmer/t3-c6663d3b/core/Sources/PocketCore/MessageDraft.swift:112) `question()` (`.none` case, line 126). Call chains: `Assistant.handle` → `skillOverride` ([Assistant.swift](/home/habib/.t3/worktrees/pocket-glimmer/t3-c6663d3b/core/Sources/PocketCore/Assistant.swift:102)) and `toolPath` → `shouldUseSkills` → `planSkill`.
- **Evidence (executable)**: With `SkillRegistry(skills: [])`, both the `answer_local` route and the `tool`/`none` route for `text Dana saying hi` returned `clarify("I might have misunderstood — review the message and tap Confirm to open the compose sheet.")` with a **complete** `pendingDraft` (contact+channel+body, `lastAsked == nil`) and no `DraftCard`. There is nothing on screen to confirm; a following short answer is then treated as a contact candidate against the already-complete draft. Probe prints in `logs/v2-probes.txt` / `v2-probes2.txt` (`testEmptyRegistryCompleteMessageGetsCardNotConfirmWithNoCard`, `testEmptyRegistryToolNoneCompleteMessageGetsCard`).
- **Reachability bound**: sampled exotic utterances against the shipping registry always returned candidates (`logs/v2-probes2.txt`), so today this needs an empty/custom registry. It is still a supported configuration of a public type, and the branch's own contract (“a staged card or a retained typed draft”) is violated for complete drafts.
- **Impact**: user is told to tap a Confirm that does not exist; the completed message can only proceed by restating it.
- **Smallest repair**: in the no-candidate branch, if `retained.isComplete`, route to `sendMessageToolPath` (compiled catalog) as the wrong-skill guard at ActionPlanner.swift:166 already does; only retain incomplete drafts with `question()`.

### B-2 [warning] Body word “email” behind a bare `that` marker strips explicit-message status (parent objection 2 — confirmed)

- **Location**: [MessageDraft.swift](/home/habib/.t3/worktrees/pocket-glimmer/t3-c6663d3b/core/Sources/PocketCore/MessageDraft.swift:494) `isEmailHead` over `head()` (lines 485–492), which cuts at `saying|that says|to say|with the message|quote|colon` but **not** bare `that`, while [ActionPlanner.swift](/home/habib/.t3/worktrees/pocket-glimmer/t3-c6663d3b/core/Sources/PocketCore/ActionPlanner.swift:414) `SkillArgs.body` treats bare `that` as a body marker. Gate consumed at MessageDraft.swift:499–502.
- **Evidence (executable)**: `isExplicitMessageRequest("text Dana that email is down") == false`; `Assistant.handle` answered `clarify("Did you mean: Write an email, Create a note or Send an iMessage / text?")` — no card, no draft (on an `answer_local` route the same loss of explicit status reaches chat generation). Quoted/colon/`saying` bodies containing “email” are safe; only the bare-`that` (and unmarked) forms leak.
- **Impact**: a complete explicit text loses truthful review-card routing because its message text mentions email.
- **Smallest repair**: cut `head()` at bare `\bthat\b` as a body marker too, or make `isEmailHead` inspect only the segment before any body marker that `SkillArgs.body` recognizes. Add the probe utterance as a regression.

### C-1 [warning] Chart parser drops supplied numbers for comma-without-space and unpunctuated lists

- **Location**: [Skills.swift](/home/habib/.t3/worktrees/pocket-glimmer/t3-c6663d3b/core/Sources/PocketCore/Skills.swift:326) `HTMLViz.pairs` — segments split on `", "` (comma+space) and only the **last** number per segment is kept (line 331). Reached via [Assistant.swift](/home/habib/.t3/worktrees/pocket-glimmer/t3-c6663d3b/core/Sources/PocketCore/Assistant.swift:193) before any classifier branch, so every route is affected identically.
- **Evidence (executable)**: `Make a chart: rent1200,food400,transit130` and `Make a chart: rent 1200 food 400 transit 130` both rendered **“1 bars”** — a single bar valued 130 labeled `rent1200 food400` / `food 400 transit` — while claiming “Chart ready”. The maintained spaced form (`rent 1200, food 400, transit 130`), semicolons, newlines and `label: value` forms render correctly (3/2 bars).
- **Impact**: inline chart silently omits/mislabels supplied numbers instead of asking again — the exact failure class this feature exists to remove.
- **Smallest repair**: split segments on commas with optional surrounding whitespace and on label boundaries; keep every `label number` pair per segment. Add both probe strings to `ChartRequestTests`.

### C-2 [warning] Literal “group chat” in a bare-`that` body is refused as a group destination

- **Location**: [ActionValidation.swift](/home/habib/.t3/worktrees/pocket-glimmer/t3-c6663d3b/core/Sources/PocketCore/ActionValidation.swift:198) `messageOptionsIssue` group head strips `saying|that says|to say|with the message|colon` and quoted spans, but not bare `that`; enforced pre-draft at [Assistant.swift](/home/habib/.t3/worktrees/pocket-glimmer/t3-c6663d3b/core/Sources/PocketCore/Assistant.swift:129).
- **Evidence (executable)**: `text Dana that the group chat moved to 7` → `clarify("OffLlama can't address an existing group by its name… No recipient was selected.")`. The `saying` form of the same sentence stages a card with the literal body (maintained test passes). Named-group destinations themselves refuse before any individual binding in all four maintained shapes, and a group-name recipient answer does not bind — those parts pass.
- **Impact**: a one-person message about a group chat is refused; inconsistent with the stated “literal group chat in message body must not refuse”.
- **Smallest repair**: strip from bare `\bthat\b` onward in the group-head computation, matching `SkillArgs.body`. (Same root shape as B-2; one shared head/marker definition would prevent both.)

### A-1 [nit] `RequestInputSummary.byteCount` still excludes transcript bytes

- **Location**: [RequestInputStore.swift](/home/habib/.t3/worktrees/pocket-glimmer/t3-c6663d3b/core/Sources/PocketCore/RequestInputStore.swift:759) `decodeSummary` (returns body `byte_count` at line 803). Capacity accounting itself is correct — `stage` (line 369) and `setTranscript` (lines 470–474) total `byte_count + length(transcript)` transactionally, refusal preserves the WAV, and the huge-grapheme case is refused (all covered by maintained tests).
- **Evidence (executable)**: stage 100-byte WAV → claim → 50-byte transcript → interrupt → `summaries().first.byteCount == 100`, retained is 150 (`logs/v2-probes.txt`).
- **Impact**: any future caller/UI reading `byteCount` as retained size understates it. No production caller exists today.
- **Smallest repair**: include transcript length in the summary query/value, or rename/document the field as body bytes before caller integration.

## Slice A verification detail (F1–F4)

- **F1 recovery ordering — fixed.** `requireRecoveredOwner()` ([RequestInputStore.swift](/home/habib/.t3/worktrees/pocket-glimmer/t3-c6663d3b/core/Sources/PocketCore/RequestInputStore.swift:303)) gates `claim`/`retryInterrupted`/`setTranscript`/`complete`/`interrupt`; `didRecover` flips only after the one-shot sweep (lines 533–547), under the same recursive gate, so a later recovery cannot interrupt a live claim. Maintained test `testProcessingRequiresRecoveryAndLaterRecoveryCannotInterruptLiveClaim` passes. `stage`/`discard`/`summaries` remain ungated, matching the prior review's accepted fix scope. Race/reopen: claim CAS + `changes()==1` unchanged; reopen recovery covered by maintained tests.
- **F2 transcript cap — fixed.** UTF-8 body+transcript totals enforced inside the `setTranscript` transaction and at `stage`; capacity refusal throws `.capacity` before any UPDATE and preserves the WAV (`testTranscriptCapacityRefusalPreservesTheSavedAudio`, `testTranscriptByteCapIncludesOneOversizedGrapheme`, `testNewStageCountsInterruptedTranscriptsUntilBodyDeletion` pass).
- **F3 Apple protection — source-fixed, runtime COULD NOT RUN.** `protectFiles` throws and verifies read-back of `.complete` + backup exclusion before DB open, after open, and after schema, naming DB/journal/WAL/SHM/`owner.lock` (lines 164–172, 256–284). Linux compiles both branches out, so none of this was executed. **Exact remaining Mac/device tests for the Mac worker/parent**: (1) Xcode iOS-SDK typecheck + `PocketCore` tests (Darwin `flock` path); (2) on a real device, after init **and after a later write transaction**, confirm directory, DB, `-journal`/`-wal`/`-shm`, `owner.lock` carry `FileProtectionType.complete` and `isExcludedFromBackup` (sidecars created after init rely on directory inheritance — unverified); (3) behavior when the store is first opened before first unlock; (4) kill (not close) mid-claim, relaunch, confirm the row becomes `interrupted/appStopped` only under the new owner; (5) same owner behavior if an App Intent can run in a separate process; (6) optional ThreadSanitizer stress of owner open/close.
- **F4 owner flag — fixed.** Single gate-protected `ownsLock` accessor ([RequestInputStoreOwner.swift](/home/habib/.t3/worktrees/pocket-glimmer/t3-c6663d3b/core/Sources/PocketCore/RequestInputStoreOwner.swift:21)); release now unlocks `flock` before registry removal. Live-owner exclusion holds (non-owner `recoverOnLaunch`/`claim` throw `.notOwner`; maintained same-process test passes). Residual spurious non-owner during a racing release remains an availability nit only, as in the prior review.
- **Effects idempotence**: late recovery never replays — store recovery only flips `claimed → interrupted`; `EffectSession.evaluate` stages message capabilities (confirmation floor `.always`) and `performCount == 0` before Confirm held in every probe; double-confirm performs once (maintained).

## Slice B verification detail (beyond findings)

Passing through `Assistant.handle`/`EffectSession`/`FakeEffects` and projections: lowercase/`to dana`/apostrophe/handle contact answers, question/imperative/app-word bodies, `no worries` bodies, stale-draft continue/cancel (no loop), explicit restatement vs new draft (different body falls through as a new request without `clarifyKeep`), `sms`/`WhatsApp` verbs, wrong high-confidence **tool** and **skill** picks with and without registry, `none` choice with and without registry (subject to B-1's empty-candidate hole), multiple pending drafts (named cancel cancels exactly one; `cancel all` safely disambiguates rather than guessing — no cancel-all exists), typed diagnostics (arbitrary capability strings are classified to a closed enum or dropped at the record boundary), Contacts permission refresh re-binding the **same** attempt/revision after grant and refusing to bind after denial (core `editEffect` level; `AppModel.refreshContacts` wiring is source-traced only — iOS, COULD NOT RUN), late compose-callback identity (`ComposeSheets.finish` requires `p.controller === controller`, source-traced only, iOS COULD NOT RUN). `AppModel.send` removes only `consumedDrafts`, replaces/keeps drafts by `requestID`, and at the 5-draft cap explicitly says the new draft was not saved rather than silently evicting — source-traced (app target does not build on Linux). Changed comments introduce no deliberation/history violations; the one history-referencing comment (below-tau branch) is a concise rationale, not a blocker. No file crosses the 1k-line threshold in this diff; no code-judo blocker found — the B-2/C-2 pair does argue for one shared body-marker definition (see repairs).

## Slice C verification detail (beyond findings)

`Make a chart: rent 1200, food 400, transit 130` renders inline fenced HTML for every scripted route with zero generation and zero effects; shared-text numeric data renders; finite extremes render without overflow and non-finite input is refused; a chart instruction inside a message body stages the message card; a chart request while a draft is pending renders without consuming the draft; a no-data chart request renders no markup (it falls through to conversation rather than asking for numbers — recorded as behavior, not counted as a finding). Group and repeat invariants as in the verdict. HTML renderer isolation was not re-reviewed (already independently verified on macOS WebKit).

## COULD NOT RUN (explicit)

iOS/Xcode typecheck of any target; Apple file-protection/backup attributes and journal inheritance on device; Contacts permission prompt + compose-sheet presentation/callback behavior on device; live-model routing on the phone (installed build predates this diff). Each needs the Mac worker/device steps named under F3 and in the parent docs; nothing above presents Linux results as device proof.

## Artifacts

- This file: `/tmp/offllama-core-fix-review-v2-20261104/findings.md`
- Probes: `/tmp/offllama-core-fix-review-v2-20261104/core-head/Tests/PocketCoreTests/ReviewV2ProbeTests.swift` (plus copied `ReviewReproTests.swift` in the same directory)
- Logs: `/tmp/offllama-core-fix-review-v2-20261104/logs/` (`full-head-clean.txt`, `full-head-with-oldrepro.txt`, `v2-probes.txt`, `v2-probes2.txt`, `core-4542.txt`)
- Baseline: `f77e5e8fa3af56999f4f55ebc7c3cc196771e97f`; parent checkout left clean and unmodified.
