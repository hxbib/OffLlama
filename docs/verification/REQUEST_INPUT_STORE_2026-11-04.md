Parent repair checkpoint, 2026-11-04. Independent review reproduced two core blockers and one Apple privacy defect in f327cae. Before integration, the parent added an enforced recovery-before-processing gate, transactionally counted transcript UTF-8 bytes in both admission paths, and made Apple protection/backup exclusion throw on failure with attribute readback. Directory protection precedes database opening. Existing database, owner-lock and journal sidecars are covered before/after initialization; later sidecars inherit the protected directory. Owner flag reads/writes now share one lock.

Parent Docker Swift 6.1 verification executed 256 tests, with one pre-existing live-test skip and zero failures. Four new Linux regressions cover claim/recovery ordering, transcript refusal preserving WAV, a single oversized grapheme, and transcript capacity across interruption/deletion. A conditional Apple attribute test is added but has not run on Apple platforms. The first worker's evidence below is historical. The byteCount summary field describes the original immutable body; capacity includes transcript bytes separately. No AppModel/voice/camera caller is wired yet. Fresh fix-diff review and Apple verification remain required before device input staging.

Evidence: [parent full-suite output](request-input-fixed-core.txt), [independent review](REQUEST_INPUT_REVIEW_2026-11-04.md).

# RequestInputStore verification, 2026-11-04

## Scope

First verifiable unit from [REQUEST_INPUT_SYNTHESIS.md](../research/REQUEST_INPUT_SYNTHESIS.md).

Candidate A separate protected SQLite store, plus the cross-judge owner lock, plus candidate B truthful caller semantics as a caller obligation for later units.

Neither original proposal is implemented verbatim.

This unit adds the core store only.

It does not wire `AppModel`, `Assistant`, admission order, resume UI, or the effect ledger.

No file in the effect ledger, planner, captures, views, calibration, or model assets changed.

## Files

- [RequestInputStore.swift](../../core/Sources/PocketCore/RequestInputStore.swift) owns schema, validation, state machine, CAS claim, TTL, caps, and decoding.
- [RequestInputStoreOwner.swift](../../core/Sources/PocketCore/RequestInputStoreOwner.swift) owns the owner lock only.
- [RequestInputStoreTests.swift](../../core/Tests/PocketCoreTests/RequestInputStoreTests.swift) holds the behavioral tests.

`SQLiteDB` is unchanged.

The store opens its own database, then sets `journal_mode=DELETE`, `synchronous=FULL`, `secure_delete=ON`, and `busy_timeout=5000` on its own connection.

The effect database keeps its existing defaults.

## Public API

```swift
public struct RequestInputPolicy: Sendable, Equatable {
    public static let standard: RequestInputPolicy
}

public enum RequestOrigin: String, Sendable, Codable, Equatable {
    case typed, share, voice, shortcut, camera
}

public enum RequestInputState: String, Sendable, Codable, Equatable {
    case staged, claimed, interrupted, completed, discarded, expired
}

public enum RequestInterruption: String, Sendable, Codable, Equatable {
    case appStopped, handleFailed, transcriptionFailed
}

public enum RequestInputBody: Sendable, Equatable {
    case text(String)
    case sharedText(utterance: String, text: String)
    case voice(wav: Data, duration: TimeInterval)
    case camera(jpeg: Data, question: String, concept: String?, mode: String, photoText: String)
}

public struct RequestInputSummary: Sendable, Equatable, Identifiable { /* id, origin, preview, byteCount, createdAt, expiresAt, state, interruption */ }
public struct ClaimedRequestInput: Sendable, Equatable { /* id, body, origin, transcript, createdAt, capturedTimeZoneID, expiresAt */ }

public final class RequestInputStore: @unchecked Sendable {
    public init(directory: URL, policy: RequestInputPolicy = .standard, now: @escaping () -> Date = Date.init) throws
    public var isExclusiveOwner: Bool { get }
    @discardableResult public func stage(_ body: RequestInputBody, origin: RequestOrigin) throws -> RequestInputSummary
    public func claim(_ id: UserRequestID) throws -> ClaimedRequestInput
    public func retryInterrupted(_ id: UserRequestID) throws -> ClaimedRequestInput
    public func setTranscript(_ text: String, for id: UserRequestID) throws
    public func complete(_ id: UserRequestID) throws
    public func interrupt(_ id: UserRequestID, reason: RequestInterruption) throws
    public func discard(_ id: UserRequestID) throws
    public func recoverOnLaunch() throws -> [RequestInputSummary]
    public func summaries() throws -> [RequestInputSummary]
    @discardableResult public func purgeExpired() throws -> Int
    public func close()
}
```

Identity reuses the existing `UserRequestID` from [EffectLedger.swift](../../core/Sources/PocketCore/EffectLedger.swift).

`close()` is the one addition beyond the cross-judge API.

It gives a caller and a test a deterministic owner release instead of depending on deinit timing.

## Ownership

One canonical store directory has one owner.

The owner holds two things for its whole lifetime.

- A process-local registry entry keyed by the canonical directory path.
- An exclusive non-blocking `flock` on `owner.lock` in that directory.

`isExclusiveOwner` is true only while both are held and the store is open.

Lock acquisition is the proof that a prior owner is gone.

No epoch, PID, heartbeat, or timestamp is used as that proof.

Only the owner may run `recoverOnLaunch`, `claim`, `retryInterrupted`, `setTranscript`, `complete`, and `interrupt`.

A non-owner may `stage`, read `summaries`, `purgeExpired`, and `discard`.

Discard still accepts only staged or interrupted rows, so a non-owner cannot discard a live claim either.

`recoverOnLaunch` is one-shot per owner instance.

Its first call converts claimed rows to interrupted with `RequestInterruption.appStopped`.

Later calls on the same instance only expire and list, so an owner never interrupts its own live claim by calling it again.

Staged rows are never claimed by recovery or by `summaries`.

Nothing in this store executes a request.

## State and storage rules

One row holds one immutable body and its metadata in one insert.

Body and metadata commit together, or neither commits.

| Rule | Value |
|---|---|
| Text, share, and voice TTL | 24 hours |
| Camera TTL | 1 hour |
| Active cap | 8 rows |
| Active byte cap | 8 MiB |
| Text cap per field | 24,000 characters |
| Voice cap | 2 MiB per WAV |
| Camera cap | 1 MiB per JPEG |
| Tombstone retention | 30 days |
| Preview | 160 characters, staged rows only |

Active means staged, claimed, and interrupted.

A stage that would pass either cap throws `capacity` and writes nothing.

No saved request is evicted to make room.

Allowed transitions are `staged` to claimed, discarded, or expired; `claimed` to completed or interrupted; and `interrupted` to claimed, discarded, or expired.

Claim and retry are one guarded update each.

Exactly one caller wins; later callers get `alreadyClaimed`.

The transcript is voice-only, claimed-only, and write-once.

A second write throws `transcriptAlreadySet`, and a database trigger backs that rule.

Terminal transitions clear utterance, payload text, payload blob, voice duration, camera concept and mode, transcript, preview, and interruption code in the same update.

The tombstone keeps only the request ID, coded state, origin, payload kind, byte count, timestamps, and capture time-zone identifier.

It holds no user text.

Triggers reject body replacement, body resurrection on a tombstone, identity or expiry rewrites, illegal state transitions, and a second transcript.

Decoding is strict.

Unknown coded values, missing or empty bodies, state and body mismatches, byte-count mismatches, malformed timestamps, and text whose stored byte length disagrees with its decoded length all throw `corrupt`.

NUL characters, empty required text, and invalid voice duration throw `invalidPayload` at stage time.

Oversize text, WAV, or JPEG input throws `tooLarge` before any row is written.

Camera is a reserved payload in the same bounded schema.

It has its own byte cap and TTL and round-trips through claim.

No camera view, capture flow, or resume route is wired, and this unit does not claim durable camera capture in the app.

## Tests

New maintained tests: 17 in `RequestInputStoreTests`.

They cover each item below through the public API, except the two storage-boundary checks, which write through a second `SQLiteDB` connection to prove the triggers hold outside the Swift API.

- Stage, claim, and complete round-trip for text, shared text, and voice.
- Per-request isolation with no shared slot.
- Eight concurrent claims with exactly one winner.
- A second instance in the same process is not owner, cannot recover, claim, retry, complete, or interrupt a live claim, and cannot discard it.
- A non-owner can still stage, list, and discard its own staged row.
- Releasing the owner lets the next instance recover a claimed row as interrupted and retry the same body and transcript.
- Recovery is one-shot and never claims a staged row.
- `summaries` returns staged rows without claiming them.
- A direct body replacement through the storage boundary is rejected.
- Terminal rows hold no sensitive fields and cannot regain a body.
- Discard accepts only staged or interrupted rows and is repeatable.
- Transcript is write-once and survives interrupt and retry.
- Interrupted rows and total bytes both count toward the caps.
- Expiry clears the body, a later claim reports the tombstone, and tombstones are deleted after 30 days.
- Unicode round-trips exactly; NUL, empty, and oversize inputs are refused with nothing staged.
- Planted malformed rows fail closed in both `claim` and `summaries`.
- Camera payload is bounded, expires after one hour, and round-trips.
- `complete` and `interrupt` are idempotent in their own direction.

Commands run in the `swift:6.1-noble` Docker image against `core/`.

```bash
docker run --rm -v "$PWD/core:/src" -w /src swift:6.1-noble swift test --filter RequestInputStoreTests
docker run --rm -v "$PWD/core:/src" -w /src swift:6.1-noble swift test
docker run --rm -v "$PWD/core:/src" -w /src swift:6.1-noble swift build
```

Observed results on 2026-11-04.

- Targeted run: 17 tests, 0 failures.
- Full run: 220 tests executed, 1 skipped, 0 failures. The skip is the pre-existing opt-in live Meta API test.
- Build: no warnings in the new files.

The same tests were run before the store existed and failed to compile because `RequestInputStore` was not in scope.

That is the expected red state for a new type, not a behavioral baseline.

## Cross-process probe

Committed XCTest cases cover two instances in one process.

A separate throwaway probe under `/tmp/pg-xproc` covered two real processes on Linux.

It is not part of the repository and is not a maintained test.

The probe built a small executable against PocketCore, then ran three processes against one store directory.

1. A holder process became owner, staged, and claimed a request, then waited.
2. A second process opened the same directory while the holder lived. It was not owner, `recoverOnLaunch` and `claim` both threw `notOwner`, it staged its own request, and its summaries showed only that staged row.
3. The holder exited with the claim still open. A third process became owner, recovered the claim as interrupted with `appStopped`, and retried the same body.

Observed output: `XPROC-PROBE-OK`.

## Not verified

- iOS file protection and backup exclusion are configured behind `#if os(iOS)` and related guards. Linux compiles the guarded-out path only. No iPhone or Simulator proof exists for `FileProtectionType.complete` or `isExcludedFromBackup` on this store.
- No Xcode build was run. Darwin compilation of the `flock` path is unverified.
- No process kill on iOS was tested. Recovery semantics are proven against store close and Linux process exit only.
- Logical deletion uses `secure_delete=ON` on this connection. No forensic erasure claim is made, and no `VACUUM` schedule is included.
- Whether an App Intent runs in the app process on the target OS is still open. The owner lock is correct in either case, but caller behavior in a second process is a later unit.

## Caller integration requirements

The next unit must do all of the following. None of it is in this commit.

1. Create the `UserRequestID` only through `stage`, before any busy or model-readiness check, and pass that same ID into `Assistant.handle`. Remove the internal ID creation there with no production default.
2. Call `recoverOnLaunch` once at open, before claiming anything in that process, and project the returned summaries without running any of them.
3. Run owner-only operations only on the instance whose `isExclusiveOwner` is true. A non-owner stages and reports the request as saved for later explicit resume.
4. Claim before transcription, reuse a saved transcript on retry, and never transcribe a staged voice request before its claim.
5. Complete or interrupt every claimed request exactly through the owner. Interrupt reasons are the coded `RequestInterruption` values, never free-form error text.
6. Treat `capacity`, `tooLarge`, `invalidPayload`, `corrupt`, and `storage` as "not saved; nothing was sent." Keep the caller's typed text or temporary recording in those cases.
7. Add the read-only effect-ledger query and resume policy before enabling retry in the UI. An interrupted retry may repeat a cloud read, memory write, or transcription; the caller must disclose that and must never retry automatically.
8. Force a review card for any resumed request that selects a capability with a datetime argument, showing capture time and the newly resolved instant.
9. Keep camera on its own resume route through a Glimpse flow. Do not route a JPEG through text handling.
10. Pass an origin that matches the staged body kind. The store treats origin as caller-declared audit metadata and does not infer it.
