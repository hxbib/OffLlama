# Independent review: RequestInputStore f327cae

Reviewer: fresh subagent, Muse Wonder 1.0 MAX (user-assigned). No subagents, no production edits.
Reviewed (read-only): /home/habib/.t3/worktrees/pocket-glimmer/t3-0d4df96a @ f327cae11301ab097f1ed4f3394cf660647c1e4a
Contract: parent docs/research/REQUEST_INPUT_SYNTHESIS.md + REQUEST_INPUT_CROSS_JUDGE.md.
Parent objections treated as hypotheses. Frozen model/calibration/tau/DecisionPrompt/test120 not examined.
All execution on a scratch copy: /tmp/offllama-input-store-review-20261104/core-copy (worker checkout untouched, git status clean).

## Verdict

NOT ready for caller integration as-is. Two small core repairs are required first (F1, F2).
One privacy repair (F3) must land before any real user input is staged on a device.
F4 is refuted as a safety defect; it is a minor latent race with a cheap fix.
Everything else in the contract's first-unit list passes on executable Linux evidence.
No app wiring is demanded; this was a core-only unit.

## Findings

### F1 [Blocker] claim before first recoverOnLaunch is accepted, then recovery converts the live claim to retryable interrupted

Source:
- RequestInputStore.swift:387-395 claim/retryInterrupted enter claimLocked with no recovery-order check.
- RequestInputStore.swift:395-430 claimLocked checks only ownership (requireOwner, 279-282), state, expiry.
- RequestInputStore.swift:504-518 recoverOnLaunch unconditionally runs
  UPDATE ... SET state='interrupted' WHERE state='claimed' on its first call; didRecover (147, 507) only makes it one-shot, it does not gate claim.

Reproduction (ReviewProbeTests.testP1ClaimBeforeRecover, Linux Docker swift:6.1-noble):
- owner store, stage, claim succeeds: `P1 first claim ok body=text("live body P1")`
- same owner's first recoverOnLaunch: `P1 after recover summaries=["interrupted/appStopped"]`
- retryInterrupted succeeds with the same body a second time: `P1 RETRY SUCCEEDED ... DUPLICATE-CLAIM-WINDOW`

Trigger/consequence: the API relies on a caller rule (worker report step 2, "recover once at open, before claiming") that nothing enforces. A caller that stages+claims at launch before the recovery sweep (the natural submit path) gets its live turn's row marked interrupted; the UI then offers explicit retry, retryInterrupted claims again, and the request can execute twice. This is the duplicate-effect class the cross-judge flagged for candidate A, reachable through ordinary ordering, not misuse.
The live-competing-owner variant is NOT reachable: a second owner cannot exist while the first lives (see F4 evidence), so this is a same-owner ordering defect only.

Smallest fix: enforce the order in the store. Add a recovery-required gate: claimLocked, retryInterrupted, setTranscript, complete, interrupt throw a distinct error (e.g. .recoveryRequired) until recoverOnLaunch has completed on that owner instance. Recovery stays one-shot and idempotent afterwards. Stage/summaries/discard need no gate. Add a regression test: claim before recover throws; after recover, claim works; recover after claim never converts that claim.

### F2 [Blocker] transcript bytes are outside the active total cap; grapheme count is the only transcript limit

Source:
- RequestInputStore.swift:296-300 validateText checks NUL/empty and `value.count > maxTextCharacters` (grapheme clusters) only.
- RequestInputStore.swift:432-451 setTranscript validates that way and writes; byte_count is immutable (trigger 229-231) and is never adjusted.
- RequestInputStore.swift:345-350 stage cap sums byte_count only, so transcripts are invisible to maxTotalBytes. Summary byteCount (730-778) likewise reports body bytes only.

Reproductions (same Docker run):
- Ordinary near-cap (testP2a): policy maxTotalBytes=3000, voice WAV 2900 bytes staged and claimed, then a plain 500-char ASCII transcript accepted. Raw SQL: byte_count=2900, blob=2900, transcript_bytes=500. Actual retained 3400 > 3000 cap.
- Combining characters (testP2b): transcript "e" + 500,000 x U+0301. graphemeCount=1, utf8Count=1,000,001. Accepted against maxTotalBytes=3000. Raw SQL: byte_count=3, transcript_bytes=1,000,001.
- Bound: none in policy. A transcript is at most 24,000 grapheme clusters, each of unbounded length, so retained transcript bytes are bounded only by SQLite/memory, not by maxTotalBytes or any byte ceiling.

Consequence: the synthesis promise "8 MiB total active payload, active includes interrupted" is false for any claimed/interrupted voice row with a transcript. Interrupted rows keep transcripts (schema CHECK line 226), so the excess also survives interruption.

Smallest fix (bounds retained input, deletes nothing saved): inside the setTranscript transaction, before the UPDATE, compute text.utf8.count and refuse with .tooLarge/.capacity when SUM(byte_count + COALESCE(length(CAST(transcript AS BLOB)),0)) over staged|claimed|interrupted rows plus the new bytes would exceed maxTotalBytes. Refusal leaves the claimed voice row and WAV intact for retry or discard. Optionally also reject a single transcript whose utf8 count alone exceeds maxTotalBytes. Keep the 24,000-grapheme check as the character limit. Add tests mirroring both probes.

### F3 [Major] file protection / backup exclusion failures are silently ignored; protection applied after DB creation, sidecars uncovered

Source:
- RequestInputStore.swift:252-265 applyFileProtection uses try? for both setAttributes(.protectionKey=.complete) and setResourceValues(isExcludedFromBackup) on iOS/tvOS/watchOS; macOS branch also try?.
- RequestInputStore.swift:160-169 init creates the directory, acquires the lock, opens the DB (SQLiteDB init sets journal_mode=WAL, SQLiteDB.swift:26) and runs schema, and only then applies protection to the directory and the main DB file. owner.lock, -journal, -wal, -shm are never named.

Assessment: init succeeds with a fully usable store if either Apple protection call fails. That is fail-open for the store's stated protection contract. Linux evidence proves nothing here: the iOS branch is compiled out on Linux, and this review makes no iOS attribute claim. Two ordering facts are source-certain and platform-independent: the DB file exists and is written (schema) before protection is applied, and journal sidecars created by later transactions are covered only if directory inheritance works as intended on device, which is unverified.
Precondition check: createDirectory itself throws and init fails closed (160-161, catch 170-176 releases the lock and rethrows as .storage). The gap is only the two try? calls.

Feasible fail-closed fix: on iOS, apply protection+exclusion to the directory before opening the DB and throw .storage if either call throws; after DB creation, apply to the DB file and any existing -journal/-wal/-shm sidecars, throwing on failure; read back attributes/resource values and throw on mismatch. Keep the Linux/macOS behavior unchanged. This is a small init change, no schema or API change.

### F4 [Minor, largely refuted] owner registry reads/writes isOwner under different locks; no double-owner reproduced

Source facts (objection confirmed as written):
- RequestInputStoreOwner.swift:17-21 isOwner is a plain var. acquire reads it under registryLock (32, 54); release writes it under the per-instance gate (67-75); RequestInputStore reads it under the store gate (RequestInputStore.swift:149-152) and in requireOwner (279-282). No single lock guards all accesses: a genuine Swift data race on the flag.

Why it is not a safety break (executable evidence, Linux):
- ReviewProbeTests.testP4ConcurrentOpenNeverTwoOwners: 30 rounds x 8 simultaneous opens of one directory, never two isExclusiveOwner=true.
- ReviewProbeTests.testP4ChurnCompetitorCannotClaimOrRecover: 40 concurrent opens/closes against a live claimed row; competitor recover/claim/retry never succeeded; owner completed the claim afterwards. violations=0.
- ReviewProbeTests.testP4SymlinkAlias: opening via a symlinked path yields a non-owner (store canonicalizes at RequestInputStore.swift:156; owner key is the canonical path, Owner.swift:29-30). Case-variant paths on a case-insensitive Darwin filesystem would miss the registry key, but flock on the same file still conflicts, so the registry is not the safety mechanism.
- Fresh 3-process Linux probe (artifacts below): holder claims and lives; second process is non-owner, recoverOnLaunch and claim throw .notOwner, it stages its own row and sees only it; holder exits with claim open; third process becomes owner, recovers as interrupted/appStopped, retries the same body. Output XPROC-REVIEW-OK.
- flock is the authoritative guard: a second in-process flock(LOCK_EX|LOCK_NB) on a separately opened fd fails EWOULDBLOCK (Owner.swift:43-50), and any other flock error throws .storage. The registry is only a shortcut.

Residual risk: the unsynchronized flag plus the release ordering (isOwner cleared and registry entry removed at Owner.swift:71-80 before flock unlock at 82-85) can produce a spurious non-owner for a racing opener. That is an availability nit, never a second owner, on Linux evidence. Darwin flock semantics and ThreadSanitizer cleanliness are unverified (no Xcode run; a syntax parse would not be an iOS typecheck and none is claimed).

Smallest fix: make isOwner a lock-protected accessor used by every reader and writer (one lock, e.g. the instance gate exposed via a method, or registryLock for all accesses), and in release drop the flock before clearing the registry entry to shrink the spurious window. Add the concurrent-open/churn probes as maintained tests.

## Remaining contract checks (all pass on Linux evidence unless noted)

- One CAS winner: claimLocked guarded UPDATE ... WHERE state=? with changes()==1 (RequestInputStore.swift:416-419) inside the owner gate; testConcurrentClaimsHaveExactlyOneWinner (8 contenders, 1 body, 7 alreadyClaimed) passes.
- Live competing owner cannot recover or claim: same-process test, churn probe, and 3-process probe above. PASS.
- Immutability and terminal resurrection: triggers at 229-250; raw-connection tests testBodyCannotBeReplacedThroughStorageBoundary and testTerminalRowsDeleteSensitiveFieldsAndCannotRegainBody pass, including a raw resurrection UPDATE being rejected. PASS.
- Terminal deletion: terminateLocked (569-577) clears utterance, payload text/blob, voice duration, camera concept/mode, transcript, preview, interruption in the terminal UPDATE; schema CHECK 212-216 enforces it. Tombstone retains only id, state, origin, kind, byte_count, timestamps, captured_tz, per synthesis. Raw test verifies sensitive fields are .null. PASS.
- Corruption fails closed: decodeFull/decodeSummary strict checks (649-778); planted malformed and byte-count-mismatched rows throw .corrupt in claim and summaries (testCorruptRowsFailClosed). PASS. Observation only: recoverOnLaunch converts claimed rows without decoding first, so a corrupt claimed row becomes interrupted and then surfaces as .corrupt at read; still fail-closed, not a blocker.
- TTL, count and byte caps including interrupted: stage sums staged|claimed|interrupted for both caps (345-350); testInterruptedRowsCountTowardActiveCaps passes; expiry and 30-day tombstone deletion pass (testExpiryRemovesBodyAndTombstoneExpiresAfterThirtyDays). Caveat: the byte cap is defeated only through transcripts (F2). Observation only: expireLocked (554-567) expires staged/interrupted, never a live claimed row, so a claim held past TTL completes normally; acceptable for an in-flight turn.
- Transcript once-only: API check plus trigger 237-240; voice-only, claimed-only; survives interrupt and retry (testTranscriptIsWriteOnceAndSurvivesInterruptRetry). PASS, subject to F2's byte accounting.
- Close/reopen: close is idempotent, closed store throws .closed, next instance acquires ownership and recovers (testReleasingOwnerLetsNextInstanceRecoverClaimAsInterrupted, testRecoverIsOneShotAndNeverClaimsStagedRows). PASS.
- No automatic execution: the two store files contain no reference to Assistant, EffectLedger, handle, timers or tasks (grep, zero matches); summaries and recovery never claim staged rows. PASS.
- Camera: 1 MiB JPEG cap and 1-hour TTL round-trip (testCameraPayloadIsBoundedAndExpiresAfterOneHour). PASS for this core unit. Minor note: camera text fields are each allowed 24,000 graphemes on top of the JPEG cap, but their bytes are counted in byte_count and therefore in the total cap, so retention stays bounded.

## Test evidence

Environment: Docker swift:6.1-noble, scratch copy of worker core plus ReviewProbeTests.swift (6 probes). Worker checkout never written to.

- Filtered run: RequestInputStoreTests 17/17 pass; ReviewProbeTests 6/6 pass (probe prints quoted above).
- Full suite on the copy: 226 tests executed, 1 skipped (pre-existing opt-in live Meta API test), 0 failures. That is the worker's reported 220 plus my 6 probes, independently confirming the worker's count.
- Cross-process probe rebuilt fresh against the scratch copy and re-run: XPROC-REVIEW-OK (holder/second/recoverer sequence above). The worker's original /tmp/pg-xproc/main.swift was read and matched this behavior; its prose was not relied on.
- No Xcode, Simulator, or device run. Darwin compilation of the flock path and all iOS file-protection behavior are unverified, consistent with the worker report's Not verified section.

## Artifacts and commands

- Probe tests: /tmp/offllama-input-store-review-20261104/core-copy/Tests/PocketCoreTests/ReviewProbeTests.swift
- Cross-process probe: /tmp/offllama-input-store-review-20261104/xproc/Sources/xproc/main.swift
- Commands:
  - docker run --rm -v /tmp/offllama-input-store-review-20261104/core-copy:/src -w /src swift:6.1-noble sh -c 'rm -rf .build && swift test --filter "RequestInputStoreTests|ReviewProbeTests"'
  - docker run --rm -v /tmp/offllama-input-store-review-20261104/core-copy:/src -w /src swift:6.1-noble swift test
  - docker run --rm -v .../core-copy:/core-copy -v .../xproc:/xproc -w /xproc swift:6.1-noble sh -c '<build, holder/second/recoverer sequence>' (sequence preserved in xproc/main.swift modes)
- This report: /tmp/offllama-input-store-review-20261104/findings.md

## Precise remaining Apple checks (for the parent, after F1-F3 repairs)

1. Xcode typecheck and test run of PocketCore on the iOS SDK (Darwin flock import path, Owner.swift:4-6), not a syntax parse.
2. On a real device: directory, DB file and -journal sidecars actually carry FileProtectionType.complete and isExcludedFromBackup after the fail-closed init; behavior when the device is locked before first unlock.
3. Kill (not close) the app mid-claim on device, relaunch, confirm claimed becomes interrupted only under the new owner.
4. Whether App Intent execution runs in the app process on the target OS; if it can run separately, the same owner-lock behavior must be exercised from that process.
5. Optional: ThreadSanitizer run of the owner open/close stress on macOS after the F4 accessor fix.
