# Durable explicit request resume, candidate B

Read-only design. No repository file was changed, no test was run, no model or paid API was called, and no agent was started. Source inspection is against `5912cd7` for the review repairs and `2475888` at final read. `AppModel.send` still guards `busy` at `app/PocketGlimmer/AppModel.swift:224`, and `Assistant.handle` still creates its own `UserRequestID` at `core/Sources/PocketCore/Assistant.swift:117`, so the admission seam is unchanged. The parent's earlier review edits are committed, not pending. A Mac worker reported a separate compile fix at `AppModel.swift:206` that is not in this Linux checkout; rebase before touching that file. No Swift toolchain or Xcode is present here.

Evidence labels used below. **Source** means inspected code. **Saved test** means an existing checked-in test, not rerun here. **Proposed test** means a test to write. **Device** means it needs Xcode, a Simulator or the iPhone and is not proven on Linux.

## Problem

`AppModel.send` checks `busy` at `app/PocketGlimmer/AppModel.swift:224` before it stores anything. A typed, shared, voice or intent request that arrives while another turn runs returns a refusal and its body exists only in the caller's local scope. `SharedInbox` is no longer a production path; `sharedText` now travels as a parameter to `Assistant.handle` (`core/Sources/PocketCore/Assistant.swift:112`), so the refusal drops the only copy. The effect journal covers actions and confirmed reply payloads, but it never sees an input that was refused before `Assistant.handle`. Moving a `put` above the guard would not fix it: the running request would still resolve through shared state. The request itself needs durable ownership.

The constraints that shape the answer are already in the code.

- `UserRequestID` exists (`EffectLedger.swift:129`), `DraftCard` carries it (`:234`), `action_attempts.request_id` stores it (`:741`), and `EffectSession.evaluate` and `stageRead` already accept it (`:1430`, `:1570`). `Assistant.handle` creates one internally at `:117`.
- Reply-only confirmations already persist their payload as `_sharedText` in `action_attempts.args_json` (`EffectLedger.swift:1581`). That is the effect journal's confirmation record, not an ingress buffer.
- `EffectLedger.recover` is read-only and reports a claimed attempt as unresolved (`:912-914`). It never replays.
- The checked-in tests are PocketCore only. There is no app test target in `app/project.yml`, so `AppModel` and SwiftUI behavior cannot be claimed as Linux-proven.

## What the current code does

| Concern | Evidence | Consequence |
|---|---|---|
| Busy check before any storage | `AppModel.swift:224` | A refused request is lost |
| Typed field cleared before the async send | `ChatView.swift:31-33` | The typed text is also gone from the field |
| `Assistant` makes its own request ID | `Assistant.swift:117` | The ingress ID cannot join the effect row |
| Reply card persists `_sharedText` | `EffectLedger.swift:1570-1583` | Confirmed reads survive relaunch today |
| Claimed effect is unresolved on recovery | `EffectLedger.swift:912-914` | No replay, but no request-level UI either |
| Voice deletes the WAV before the busy check | `VoiceCapture.swift:51-65`, `:111-115` | A busy voice request has no bytes left |
| Camera runs outside `busy` and outside `send` | `GlimpseView.swift:73-95` | It can overlap and loses view state on dismiss |
| `SharedInbox` remains as dead production code | `Skills.swift:287`; test cleanup only | Delete it with this change, do not build on it |

The parent's committed review fix `5912cd7` adds a shared-text branch for non-tool routes and makes failed reads ambiguous. Those changes are compatible with this design. The admission seam is unchanged.

## Usage (caller's view)

Write these call sites first. The types below are derived from them.

### 1. Typed chat

```swift
// ChatView composer
Button {
    switch model.submit(input) {
    case .started, .deferred:
        input = ""                       // clear only after the store wrote
    case .notSaved(let message):
        model.note(message)              // keep the typed text
    }
}
```

`submit` is synchronous on the main actor. It stages before it consults `busy`. A `.deferred` receipt means "saved, not running." A `.notSaved` receipt means exactly that, and the field is not cleared.

### 2. Share while busy

```swift
// HandleTextIntent.perform, unchanged shape
let reply = await AppModel.shared.send(ask, sharedText: body, source: source)
return .result(value: reply)
```

`send` stages first. If the app is busy it returns "Saved. Open Pocket Glimmer to resume it when the current request finishes." The body is no longer held only by the intent. If staging throws, it returns "I couldn't save that request, so nothing was sent." It never says saved after a failed write.

### 3. Explicit resume or discard

```swift
// PendingInputBar
Button("Resume") { model.resume(item.id) }
    .disabled(model.busy || !item.canResume)
Button("Discard", role: .destructive) { model.discard(item.id) }
```

`resume` is synchronous. It refuses while busy, claims the row atomically, sets `busy`, and starts the turn. `discard` deletes the body and writes a tombstone. Nothing runs from a timer, a scene transition or the end of a previous turn.

### 4. Voice finish

```swift
// MicButton.finish
guard let recording = recorder.stop() else { return }
guard recording.data.count > 44 + 16_000 else { ... }
let receipt = model.submitVoice(recording)
switch receipt {
case .started, .deferred:
    recorder.discard(recording, keep: recorder.keepRecordings)
case .notSaved(let message):
    unsavedRecording = recording        // keep for "Retry save"
    note(message)
}
```

The WAV is staged before any busy check. The immutable payload is the audio. The transcript is derived at admission time and is not persisted in this slice. If transcription fails, the request stays `staged` and Resume tries again, because no Assistant action has begun.

## Shape

### Module map

| File | Ownership after the change |
|---|---|
| `core/Sources/PocketCore/RequestLedger.swift` (new) | Only writer of `request_inputs` and `RequestInputs/` files. Owns staging, claim, settle, expiry, recovery projection |
| `core/Sources/PocketCore/EffectLedger.swift` | Not touched by this design. Still the only writer of `action_attempts`. Joins on `request_id` |
| `core/Sources/PocketCore/Assistant.swift` | `handle` takes the ingress `UserRequestID` instead of making one. No calibration, model, action or contract change |
| `app/PocketGlimmer/AppModel.swift` | Owns the `RequestLedger`, `pendingInputs` and the in-process `busy` flag. `submit`, `send`, `resume`, `discard`, `run` |
| `app/PocketGlimmer/Views/ChatView.swift` | Synchronous submit, field retention on failure, `PendingInputBar`, enabled composer while busy |
| `app/PocketGlimmer/Capture/VoiceCapture.swift` | Stop returns a recording without deleting it. Staging precedes any busy check |
| `app/PocketGlimmer/Views/GlimpseView.swift` | Camera remains view-only. Dismiss guard and explicit "not saved" copy |
| `core/Tests/PocketCoreTests/RequestLedgerTests.swift` (new) | Store lifecycle, CAS, expiry, Unicode, failure, restart |
| `core/Tests/PocketCoreTests/RequestAdmissionTests.swift` (new) | Combined request plus effect interruption, ID binding |

`RequestLedger` is a sibling of `EffectLedger`, not a method on it. The two share one `SQLiteDB`, one `UserRequestID` and one app container, but each owns its own table. This follows the existing `MemoryStore` and `EffectLedger` pattern in the recovery contract: one database, one writer per table, no nested transactions. A merged 2,400-line ledger would hide less and make the request lifecycle look like an attempt.

### Core types

```swift
public enum RequestSource: String, Sendable, Codable, Equatable {
    case typed, share, voice, shortcut
}

public enum RequestPayload: Sendable, Equatable {
    case none
    case text(String)
    case voice(Data, durationSeconds: Double?)
}

public enum RequestTerminal: Sendable, Equatable {
    case completed      // the turn returned; the request handed off successfully
    case interrupted    // the turn began but its outcome is unknown
    case discarded      // the user chose to delete it
    case expired        // the TTL elapsed
    case unreadable     // the saved body is missing or corrupt
}

public enum RequestStatus: Sendable, Equatable {
    case staged
    case claimed
    case terminal(RequestTerminal)
}

public struct StagedRequest: Sendable, Equatable {
    public let id: UserRequestID
    public let utterance: String
    public let payload: RequestPayload
    public let source: RequestSource
    public let createdAt: Date
    public let expiresAt: Date
}

public struct ClaimedRequest: Sendable, Equatable {
    public let requestID: UserRequestID
    public let utterance: String
    public let payload: RequestPayload
    public let source: RequestSource
    public let expiresAt: Date
}

public struct PendingRequest: Identifiable, Sendable, Equatable {
    public var id: UserRequestID { requestID }
    public let requestID: UserRequestID
    public let source: RequestSource
    public let utterancePreview: String     // bounded, 160 characters
    public let payloadPreview: String?      // bounded, 160 characters
    public let payloadSummary: String       // "Shared text · 12,430 characters", "Voice · 38 s"
    public let createdAt: Date
    public let expiresAt: Date
    public let status: RequestStatus
    public let payloadAvailable: Bool
    public var canResume: Bool { status == .staged && payloadAvailable }
}

public enum RequestClaim: Sendable, Equatable {
    case claimed(ClaimedRequest)
    case notResumable(RequestStatus)
    case notFound
}

public enum RequestStoreError: Error, Equatable {
    case alreadyExists
    case payloadTooLarge(limit: Int)
    case tooManyPending(limit: Int)
    case invalidTransition
    case storage(String)
}
```

`RequestStatus.terminal` is one value. It makes "a terminal state never returns to staged" a type-level fact. `RequestTerminal` is the only input to `settle`, so a caller cannot settle to `staged` or `claimed`. The UI maps the terminal cases to copy, not to a second status enum.

### Store API

```swift
public final class RequestLedger: @unchecked Sendable {
    public static let defaultTTL: TimeInterval = 24 * 60 * 60
    public static let maxPending = 8
    public static let maxUtteranceCharacters = 4_000
    public static let maxUtteranceBytes = 256_000
    public static let maxTextCharacters = ActionValidation.sharedTextLimit   // 24_000
    public static let maxTextBytes = 1_000_000
    public static let maxVoiceBytes = 2_000_000
    public static let maxVoiceSeconds: Double = 60

    public init(db: SQLiteDB,
                payloadRoot: URL,
                now: @escaping () -> Date = Date.init) throws

    @discardableResult
    public func stage(_ id: UserRequestID,
                      utterance: String,
                      payload: RequestPayload,
                      source: RequestSource,
                      ttl: TimeInterval = defaultTTL) throws -> StagedRequest

    public func claim(_ id: UserRequestID) throws -> RequestClaim

    public func settle(_ id: UserRequestID, as outcome: RequestTerminal) throws

    public func pending() throws -> [PendingRequest]

    @discardableResult
    public func purgeExpired() throws -> Int

    @discardableResult
    public func recoverClaimed() throws -> Int
}
```

Six public operations. The store hides the database schema, the request directory layout, file protection, backup exclusion, the size gates, the pending cap, the expiry policy, the CAS claim and the delete-before-tombstone ordering. Callers never coordinate a file write with a row write.

### AppModel API

```swift
enum SubmitReceipt: Equatable {
    case started(UserRequestID)
    case deferred(UserRequestID)
    case notSaved(String)
}

private(set) var pendingInputs: [PendingRequest] = []
private(set) var busy = false

func submit(_ text: String,
            sharedText: String? = nil,
            source: RequestSource = .typed) -> SubmitReceipt

func submitVoice(_ recording: VoiceRecording,
                 source: RequestSource = .voice) -> SubmitReceipt

func resume(_ id: UserRequestID)
func discard(_ id: UserRequestID)
func refreshPendingInputs()
func purgeExpiredInputs()

// App Intent wrapper; awaits the turn and returns its reply.
func send(_ text: String,
          sharedText: String? = nil,
          source: String = "share") async -> String
```

`submit` and `send` are two caller policies over one core. `submit` is the synchronous UI ingress; it stages, claims if idle, and starts a `Task` that runs the turn. `send` is the async App Intent ingress; it stages, claims if idle, and awaits the same `run`. They share `stage`, `claimIfIdle` and `run`. They are not two storage paths. The App Intent's free-form `source` string maps to `.share` when it names mail or a share sheet and to `.shortcut` otherwise. `RequestSource` is display and audit metadata, never authority.

Both paths validate non-empty input, stage, and only then check `busy` and whether `assistant` is loaded. A missing model leaves the request staged with a "saved, model not ready" message and a Resume that refuses until the model loads. It is never reported as sent. This is the same ownership rule as busy: the input is saved before any condition that can refuse to run it.

`busy` has one writer class. `beginWork` refuses when already busy and sets it; `endWork` clears it, refreshes memory and refreshes pending inputs. `submit`, `submitVoice`, `resume`, `confirm` and `edit` use these helpers. `VoiceCapture` no longer writes `model.busy`. The durable truth for an in-flight request is `request_inputs.status == .claimed`; `busy` is the in-process projection used by SwiftUI. Every stage, settle, discard and resume refreshes `pendingInputs`, so a deferred `send` updates the bar even when no turn runs.

### Assistant binding

```swift
public func handle(_ utterance: String,
                   requestID: UserRequestID,
                   now: Date = Date(),
                   sharedText: String? = nil) async throws -> AssistantTurn
```

Remove `let requestID = UserRequestID()` at `Assistant.swift:117`. Every `skillOverride`, `toolPath`, `planSkillCore`, `stageRead` and `evaluate` call already accepts the value, so the only change is that it comes from ingress. All test call sites add `requestID: UserRequestID()`. This is a mechanical change to roughly forty calls, not a model or action contract change.

The join is then exact. A request staged as `R` and resumed as `R` creates `action_attempts` rows whose `request_id` is `R`. `DraftCard.requestID` is `R`. `recoverEffects` and the request bar can show the same identity without a new mapping table.

### Schema and files

```sql
CREATE TABLE IF NOT EXISTS request_inputs (
  request_id    TEXT PRIMARY KEY,
  status        TEXT NOT NULL,          -- staged | claimed | completed | interrupted | discarded | expired | unreadable
  source        TEXT NOT NULL,
  payload_kind  TEXT NOT NULL,          -- none | text | voice
  payload_chars INTEGER NOT NULL DEFAULT 0,
  payload_bytes INTEGER NOT NULL DEFAULT 0,
  audio_seconds REAL,
  created       REAL NOT NULL,
  updated       REAL NOT NULL,
  expires       REAL NOT NULL,
  settled       REAL
);
CREATE INDEX IF NOT EXISTS request_inputs_status
  ON request_inputs(status, expires);
```

The row contains no user text, no utterance and no file path. The file layout is private to the store.

```
Application Support/PocketGlimmer/RequestInputs/
  <request-uuid>/
    request.json        // utterance, payload kind, text, duration, byte count, created
    voice.wav           // only for .voice
```

The database row and the directory share the request UUID. Completion, discard, expiry and unreadable delete the directory recursively before they write the terminal row. Interruption writes the terminal row and keeps the directory, because the user may need to see what was in flight. A tombstone row keeps `request_id`, status, source, counts and timestamps, and nothing the user wrote. On init, the store removes any `<uuid>` directory with no matching row. Those are pre-commit orphans from a crash between the file write and the row insert, and leaving them would retain text the app never recorded as saved.

### Lifecycle

```
stage:    absent --write body, insert row--> staged
admit:    staged --atomic CAS--> claimed
finish:   claimed --turn returned--> completed   (body deleted)
fail:     claimed --handle threw--> interrupted  (body kept, no resume)
discard:  staged | interrupted --user--> discarded (body deleted)
expire:   staged | interrupted --TTL--> expired (body deleted)
recover:  claimed --new process--> interrupted (body kept, no auto-run)
read fail: staged | claimed --body missing/corrupt--> unreadable (body deleted)
```

No edge leaves a terminal state except `interrupted -> discarded` and `interrupted -> expired`, both of which delete the body. The effect ledger's ambiguous attempt remains after either, so discarding the input does not erase the effect uncertainty. A retry is a new `UserRequestID`; it is not a transition.

The launch sequence is important.

1. `bootOnce` creates `RequestLedger` on the existing `SQLiteDB`.
2. `recoverClaimed()` changes every `claimed` row to `interrupted`. This is a write, but it never calls `Assistant`, `EffectSession` or `PhoneEffects`. It only stops a dead process from looking live.
3. `purgeExpired()` deletes expired staged and interrupted bodies.
4. `refreshPendingInputs()` reads the projection.
5. The UI shows the bar. Nothing runs.

`busy` clearing only runs `endWork`. It never calls `resume` or `admit`. A scene becoming active calls `purgeExpired` and `refreshPendingInputs`, not `resume`. `refreshPendingInputs` calls `purgeExpired` before it reads, so a TTL that passes while the app stays open also deletes the body. These are the no-auto-run invariants.

The claim is one guarded update inside one transaction:

```sql
UPDATE request_inputs
SET status = 'claimed', updated = ?
WHERE request_id = ? AND status = 'staged' AND expires > ?;
```

`SQLiteDB.changes() == 1` is the only winning condition. The loser reloads the row and gets `.notResumable(.claimed)`, `.notResumable(.terminal(...))` or `.notFound`. The file read happens after the CAS, so a losing duplicate never reads a payload it will not use. If the file read fails after the CAS, the row becomes `.terminal(.unreadable)` and the caller gets `.notResumable`. That state is honest and cannot replay.

`settle(.completed)`, `.discarded`, `.expired` and `.unreadable` delete the body before they write the terminal row. A crash between those two steps leaves the prior status with no body. The next `pending` shows `payloadAvailable == false`; `claim` marks it unreadable. The body is gone, which is the privacy-safe failure direction. `.interrupted` is the exception. It writes the terminal row and keeps the body, so the user can see what was in flight. Discard or the TTL removes that body later. That is why the deletion requirement names completed, discarded and expired, not interrupted.

### Size, TTL and protection policy

| Data | Limit | TTL | Backup | Protection |
|---|---|---|---|---|
| Typed utterance | 4,000 characters / 256 KB UTF-8 | 24 h | excluded | `NSFileProtectionComplete` |
| Shared text | 24,000 characters and 1 MB UTF-8 | 24 h | excluded | `NSFileProtectionComplete` |
| Voice WAV | 60 s and 2 MB | 24 h | excluded | `NSFileProtectionComplete` |
| Staged request count | 8 | n/a | n/a | n/a |
| Camera JPEG | not stored in this slice | n/a | n/a | n/a |

`RequestInputs/` is marked `isExcludedFromBackup = true`. Staged user text and audio are device-local working data, not a user document. A restore to another phone does not restore a half-finished request. The row metadata may survive in the main database; if its body is absent, the UI says "Saved data is unavailable; nothing will run" and offers Discard. That is better than a restored row that silently runs old text.

The main `pocket.sqlite` still holds `action_attempts.args_json`, including `_sharedText` for a confirmed reply card. That is the existing effect journal, not this store. Its body is not excluded from backup by this design, and it currently has no TTL. This is a real remaining privacy gap. The smallest follow-up is to null `_sharedText` when a reply attempt settles or is cancelled and add a body TTL to the ledger. It should not block the admission fix, but the parent should not describe the whole app as backup-clean until it lands.

The request store does not log bodies. User-facing errors name the request source and a generic reason, never the text. The preview is visual only; the accessibility label uses the source and size, not the body.

### UI projection

`PendingInputBar` sits above the composer and shows the staged items, at most eight, plus any interrupted items (those are terminal and expire on their own schedule).

- Staged, payload available: source icon, utterance preview, payload preview or summary, "Saved until <time>", Resume, Discard.
- Staged, payload missing: "Saved data is unavailable; nothing will run", Discard only.
- Interrupted: "Interrupted. Outcome unknown; nothing was re-run", Discard only. No Resume.
- Busy: Resume disabled with the reason "Finish the current request first." Discard remains available for staged items.
- After Resume: the bar item disappears, a user bubble appears when the turn starts, and the normal busy indicator runs.
- After Discard: a system line "Discarded saved input." For an interrupted item, add "The earlier outcome is still unknown." The item disappears.

A restored effect card and an interrupted request can share a request ID. The card owns the action; the bar owns the input. Discarding the bar does not cancel the card, and cancelling the card does not delete the request body. The UI should not merge them into one control.

The composer's send button is enabled while busy. The point is that a second request can be saved. The button stays disabled for empty input. The typed field is cleared only on `.started` or `.deferred`.

VoiceOver labels say "Resume saved request from share, 12,430 characters" and "Discard saved request." They do not read the document body.

### Voice ownership

`VoiceRecorder.stop()` returns a `VoiceRecording` with the WAV data, duration and temporary URL. It does not delete the temporary file. `MicButton` is enabled while busy; its input is durable now. It calls `submitVoice` before any busy check. On a successful stage it calls `recorder.discard(recording, keep:)`, which either moves the file to `Documents/Recordings` when the user opted in or deletes it. On a failed stage it keeps the recording in `@State` and shows "Retry save" and "Delete." The user's captured audio is never silently deleted before a save decision.

The transcript is derived. The immutable payload is the WAV. At admission, the app transcribes while the request is still `staged`, then claims and calls `Assistant.handle`. A transcription failure leaves the request staged, so Resume can retry. A failure inside `Assistant.handle` makes it interrupted, because an effect may have started. This is the same distinction the effect journal already makes.

### Camera ownership

Camera remains a separate view-only path in this slice. It is not written to `RequestInputs` and the UI must not call it saved.

- `GlimpseView` blocks interactive dismissal while `running`, and the `Done` button is disabled while `running`.
- `Done` while a photo or question is unsent asks "Discard this photo and question? Photos are not saved."
- The view copy says "This glimpse is not saved. Closing it loses the photo and question."
- The camera button stays disabled while `busy`, as today. The camera still does not set `busy` and can overlap a text turn. That is a known separate-path behavior, not a claim of admission.

A future slice can add `RequestPayload.photo(Data)` with a 1 MB cap, a 1 h TTL and the same protected directory. The photo is already downscaled to at most 1024 px and stripped of EXIF. That is a real option, not a silent omission.

### Why this is not a workflow engine

There is one row, one immutable payload and one claim per request. There are no steps, no ordering, no retries, no scheduler and no background drain. `RequestLedger` never calls `Assistant`, `EffectSession` or `PhoneEffects`. The effect ledger remains the only executor and the only effect recovery. The request ID is a join key, not a workflow ID. A resumed request goes through the exact same `Assistant.handle` and `confirmEffect` path as a fresh one.

## Synthesis decision

### Chosen: sibling `RequestLedger` on the effect journal's database

This candidate makes the admission boundary a small, durable, single-writer module next to the effect journal. It reuses `UserRequestID`, the existing `SQLiteDB`, the existing claim idiom and the existing recovery rule that a claimed row is never replayed. It adds only the ingress record and the explicit resume projection. It keeps the reply-only confirmation payload where it already lives and does not touch the effect state machine.

The caller surface is six store methods plus the AppModel ingress and projection methods. Behind it are the file layout, protection, backup exclusion, size gates, pending cap, CAS claim, delete-before-tombstone ordering and crash recovery. That is a deep module with a small interface.

### Rejected: standalone `RequestInbox` actor with its own store and auto-drain

A separate actor with its own UUID, JSON store and a queue that drains when `busy` clears is structurally distinct. It loses for four reasons.

1. A second identity cannot join `action_attempts.request_id` or `DraftCard.requestID`. The task requires one `UserRequestID`.
2. Auto-drain is explicitly forbidden. It also turns a saved input into an unreviewed action after a busy-clear or a launch.
3. A queue invites ordering, retries and background behavior. That is a workflow engine in embryo.
4. A separate transaction boundary makes crash states harder to reason about. The same database and the same claim idiom keep the request row and the effect row visible together.

It would be simpler in isolation and worse at the boundary the product needs.

### Also rejected

- **Keep `SharedInbox` and key it by request ID.** One global slot still allows a later request to overwrite an earlier one. Delete the class instead.
- **Create a fake reply-only `action_attempt` before the busy check.** Reply-only ids are deliberately not effects. A fake attempt pollutes the journal, the claim rules and recovery.
- **Move `put` above the guard.** Rejected in the Muse review. The running request would still read the shared slot at execution time.

## Tests

### PocketCore tests (Linux, no Xcode)

1. `testStagedRequestSurvivesReopenWithoutClaiming`. File-backed SQLite plus a temp payload root. Stage, drop every reference, reopen, `pending()` returns the item, `claim` is still possible, and no `request_inputs` row is claimed. **Proves** restart durability at the store level. **Does not prove** AppModel boot or an iOS process kill.
2. `testConcurrentClaimYieldsOneWinner`. Two detached tasks call `claim` on one ledger. Exactly one returns `.claimed`; the other returns `.notResumable(.claimed)`. **Proves** the CAS. **Does not prove** a double tap in SwiftUI.
3. `testTwoDistinctDocumentsKeepTheirOwnPayloads`. Stage A with text A and B with text B. Claim A returns A, claim B returns B. Complete A. B is still staged with B. **Proves** no global slot and no cross-request overwrite.
4. `testInterruptedRequestDoesNotResumeAndItsEffectStaysAmbiguous`. Stage R, claim R, create an effect attempt with `requestID: R`, record an ambiguous effect, skip settling R, drop and reopen. `recoverClaimed` turns R into interrupted. The effect ledger's `recover` reports the attempt unresolved. `claim(R)` returns `.notResumable(.terminal(.interrupted))`. The saved body is still present after interruption and is removed only by discard or expiry. Reopening issues no second `perform`. **Proves** no automatic replay and the shared identity. **Does not prove** a real iOS kill.
5. `testStageFailureLeavesNoRowOrBody`. Replace the payload root with a regular file after init. `stage` throws `.storage`. `pending` is empty, no directory exists, and no row was inserted. **Proves** the store refuses instead of pretending. The AppModel's "not saved" copy needs Xcode or a code review.
6. `testExpiredRequestDeletesBodyAndKeepsOnlyTombstone`. Inject a clock, stage, advance past the TTL, `purgeExpired`. `pending` is empty, the request directory is gone, and the row is `.terminal(.expired)` with no body. **Proves** physical deletion, not logical hiding.
7. `testUnicodePayloadRoundTripsExactly`. A payload with emoji, ZWJ sequences, flags, combining marks, Arabic, Hebrew and CJK round-trips with exact `String` equality and byte count. A 24,000-character payload passes; 24,001 throws `.payloadTooLarge`; a text payload over 1 MB throws. **Proves** Unicode safety and the size gate.
8. `testBusyInputCanBeStagedWhileAnotherIsClaimed`. Stage A and claim A. Stage B while A is claimed. B is `staged`; A's payload is unchanged; `pending` shows B only. `complete A`; B remains B. **Proves** staging does not need the global slot. **Does not prove** `AppModel.send`'s guard order.
9. `testMissingBodyBecomesUnreadableNotResumed`. Stage, delete the directory by hand, `claim` returns `.notResumable(.terminal(.unreadable))`, and no payload is read. **Proves** a corrupted record cannot run.
10. `testDiscardDeletesOnlyTheChosenRequest`. Stage A and B, discard A. A's directory is gone, B's payload still reads, and B can still be claimed. **Proves** per-request delete scope.
11. `testPendingCapRefusesNinthWithoutWriting`. Stage eight text requests. The ninth throws `.tooManyPending`; no ninth directory or row exists; the first eight still read. **Proves** the size policy is a real gate, not a UI-only warning.

### Xcode or device tests

These are not Linux claims.

- Typed field retention. Submit while busy, confirm the field clears and the bar shows the saved item. Force a stage failure and confirm the field is still there with a "not saved" message.
- Share intent while busy. Deliver `HandleTextIntent` from the share sheet during a running turn. The reply says saved, the app opens, and the bar shows the item.
- Resume and duplicate resume. Two rapid taps on Resume produce one user bubble and one effect attempt. The second tap is disabled or refused.
- Launch recovery. Kill the app after a busy save, relaunch, and confirm the bar shows the item and no turn runs. Repeat with a kill during `handle`; the item says interrupted and the effect card says unresolved.
- Voice. Record while a turn is running, release, confirm the WAV is saved and the bar shows it. Force a transcription failure and confirm Resume retries. Confirm the recording is not deleted before the save decision.
- Camera. Run a glimpse, try to dismiss while running, and confirm the photo/question is retained or the discard confirmation appears. Kill the app and confirm the copy says photos are not saved.
- File protection and backup. On a real device, confirm the request directory is `NSFileProtectionComplete` and excluded from backup. The Simulator and Linux do not establish this.
- Accessibility. VoiceOver labels for Resume and Discard, including the saved-source and size summary.

### Requirement to test map

| Requirement | Test |
|---|---|
| One immutable payload per ID | 3, 7, 8, 10 |
| Stage before busy | 8 plus the Xcode busy test |
| Resume/Discard projection | Xcode launch and bar test |
| No auto-run on launch or busy-clear | 1, 4 plus the Xcode launch test |
| Failed save is not called saved | 5 plus the Xcode field test |
| Atomic claim against double resume | 2 plus the Xcode duplicate tap test |
| Interrupted in-flight is visibly uncertain | 4 plus the Xcode kill test |
| Reuse the effect journal | 4 and the unchanged `EffectLedger` tests |
| Bind `Assistant` to the ingress ID | 4 plus a compile-time call-site change |
| Size, TTL, deletion, protection | 5, 6, 7, 9, 10, 11 plus the device protection test |
| Voice and camera ownership | Xcode voice and camera tests |

## Design red-flag review

- **Shallow module.** Six public methods hide the file and database coordination, the CAS, the expiry and the privacy policy. The caller never coordinates a body write with a row write. Pass.
- **Information leakage.** The schema, directory name and file protection are private. `RequestPayload.voice` carries bytes, not a URL. `PendingRequest` carries previews, not the full body. `Assistant.handle` sees only the ID and the shared text. Pass.
- **Temporal decomposition.** One module owns the entire request lifecycle. There is no separate stage, validate and save module repeating the same representation. Pass.
- **Pass-through method.** `send` is a thin async wrapper over `submit`'s core for App Intents. It adds the await-the-reply policy that the UI does not need. This is the one pass-through-shaped seam and it is justified by the caller contract. The store has no pass-through methods.
- **Split ownership.** `RequestLedger` is the only writer of `request_inputs` and `RequestInputs/`; `EffectLedger` remains the only writer of `action_attempts`; `AppModel` is the only writer of `busy`. Pass.
- **Two ways to do one task.** `SharedInbox` is deleted. The request store is the only ingress buffer. `submit` and `send` share one core. Pass.
- **Importable internals.** The store's database and file helpers are private. The public surface is domain values. Pass.
- **Hand-synced list.** `RequestStatus` is the only status enum. `RequestTerminal` is the settle input and maps to the terminal arm. There is no second list of pending states. Pass.

## Tradeoffs accepted

- We accept a directory per request in exchange for one delete unit, exact payload isolation and easy backup exclusion. The database stays small and text-free.
- We accept a 24-hour TTL in exchange for a forgiving resume window. Sensitive text sits on disk longer than the old 15-minute in-memory window, but it is protected, excluded from backup and physically deleted on completion, discard or expiry.
- We accept an eight-request cap in exchange for bounded disk use and no unbounded queue.
- We accept that voice transcription may be attempted twice after a failure in exchange for never deleting the only recording before a save decision.
- We accept that camera is not durable in this slice in exchange for a small change. The UI says so and blocks accidental dismissal during a run.
- We accept that the effect ledger's `_sharedText` still outlives the request and is still in the backed-up main database. That is the existing journal's gap, not a reason to duplicate it.
- We accept that `Assistant.handle`'s signature changes and about forty tests need a mechanical `requestID:` argument. The alternative is a default ID that can silently unlink the ingress from the effect row.

## Open questions and risks

1. Is 24 hours the right TTL for a busy-deferred share, or should it be 1 hour? The longer window is kinder to a user who is interrupted; it is worse for sensitive text. This is a product call.
2. Is eight the right pending cap? It bounds disk and attention, but a power user could hit it. The UI needs a clear "finish or discard one" message.
3. Should the confirmed reply payload (`_sharedText`) get the same delete-on-settle treatment? Today it lives in `action_attempts.args_json` indefinitely. This design flags it but does not change the effect journal. A follow-up is needed before calling the whole app retention-complete.
4. Should the request body be encrypted with a Keychain-held key in addition to file protection? File protection is the native boundary. Encryption would help if the backup exclusion or protection attribute were wrong, but it adds key management and CPU. This is a risk decision, not a blocker.
5. Does `NSFileProtectionComplete` break an App Intent that stages while the device is locked? `openAppWhenRun = true` should mean the app is foreground and unlocked, but this needs a device check. If it fails, the intent must report "not saved," never "saved."
6. The parent's review fixes in `5912cd7` change shared-text routing and read failure semantics. The admission design is compatible, but the implementation should rebase on `5912cd7`. The `Assistant.handle` request-ID line is the only overlapping line.
7. The camera remains a real loss path on process death. The explicit copy and dismiss guard reduce surprise but do not preserve the photo. Is that acceptable for the demo, or does camera need a durable slice too?
8. A Mac worker reported a compile fix at `AppModel.swift:206` (`loadScrubberNames`) while this design was being written. The admission change touches `send`, `bootOnce` and the UI, not that line, but the Mac branch and this Linux checkout can diverge. Rebase on the Mac branch and re-read the file before editing.

## Attention audit: parent run65 trail

Scope. `docs/ORCHESTRATOR_DECISIONS.tsv` rows from `2026-11-04T20:04:14+00:00` through `2026-11-04T20:21:46+00:00` (the run65 block). Parent thread `4311f30f-96dc-4e78-9f19-860e3bbea796`, positions 2600 through 2830 in bounded message and activity reads. Repository at `4fda967`; the saved logs `docs/verification/run65-core-tests.txt` and `run65-app-parse.txt` were read. No phone, Xcode or paid evidence was produced by this audit.

| Row | Claim | Observed evidence | Verdict |
|---|---|---|---|
| start | Resume at clean `1e5c56e`; preserve writers and paid allocations; app unbuilt | `git log` at 2613 shows `1e5c56e`; ledger read at 2617; parent statement at 2631 | Supported for the pickup. "Clean" was not independently shown in the bounded read, but the later docs writes are visible |
| mac-link | Mac linked with full access; parent device list has no iOS host; ask for worker assignment | `t3_environment_links` at 2605 shows reachable/full-access Mac; `device_list` at 2612 shows local iOS unavailable, Android available; user assignment request at 2620 | Supported |
| acceptance-docs | Update stale Mac availability and action-journal acceptance statements; device checks remain NOT RUN | Docs diff changes `FINAL_HOURS.md`, `PROJECT_STATUS.md`, `DEVICE_ACCEPTANCE.md`; P16 now says integrated journal but still NOT RUN; P09 now requires deferred input | Supported by the docs themselves. The "6 PM leeway" reason is not visible in positions 2600-2760; the user message at 2670 only assigns GPT 6.1 Terra. Treat the leeway as unverified in this range, not false |
| mac-dispatch | Dispatch GPT 6.1 Terra at high effort on the linked Mac; running, no build result | `delegate_task` at 2674 targets `gpt-6.1-terra`, `reasoningEffort: high`, Mac environment; result at 2675 says no build | Supported |
| mac-preflight | Disk below model size; unbundled GGUF and missing provenance block the build; model/calibration verified | First worker result at 2675 matches; Mac activity read at 2715 | Supported |
| packaging-fix | Drain native inspection output; require a defined text symbol; 88 fixtures pass; Mac retest pending | Reproduction at 2710 shows `producer=141 matcher=0`; commit `571d80d` at 2730; log at 2721 says 88 passed; later v2 worker at 2742 confirms the symbol check but still lacks provenance | Supported. The 88 fixtures are a Linux/mock run, not a Mac build. The later partial Mac retest confirms the symbol check, not the full fixture suite |
| input-design | Dispatch two read-only designs under River02/River03 DeepSeek V4.1 Flash1017 max; implementation pending | `delegate_task` at 2685 and 2687; `run65_dispatches.json` lists both providers, models and `variant: max`; no implementation exists | Supported |
| follow-through | First worker stopped before compile; parent fixed a reproduced packaging defect; Terra high and River04 max running; acceptance open | First worker status is completed, not stopped, and it did not compile; `571d80d` exists; `delegate_task` at 2741 and 2743; acceptance still NOT RUN | Substantively supported. "Stopped" is imprecise; it returned without compiling |
| review-repairs | Preserve shared document input and disclose uncertain cloud/action outcomes; 189 Swift tests with 1 skip and 0 failures; app syntax only; independent recheck pending | `REVIEW_REPAIR_STATUS.md`; `run65-core-tests.txt` tail says 189 executed, 1 skipped, 0 failures at 20:18:18; `run65-app-parse.txt` exists; parent message at 2807 matches; `run65_dispatches.json` lists the River08 recheck running | Supported for the Linux/mock suite and syntax parse. The row correctly does not claim a phone or Apple SDK typecheck. Independent recheck is still open |
| mac-restart | Hold remote execution until the user reports the Mac back; both Mac tasks terminal; no active Mac build/install; Terra target unchanged | User restart message at 2812; parent reply at 2815; `run65_dispatches.json` shows both Mac jobs completed | Supported |
| action-followup | Dispatch focused time/constraint implementation and independent shared-read recheck; River05 implementation and River08 review both max; no paid training jobs added | `run65_dispatches.json` lists `river05` and `river08` with `variant: max`; `5912cd7` is the review-repair commit; `REVIEW_REPAIR_STATUS.md` lists C3/C4/W2 open | Supported for the recorded dispatch list. "No paid training jobs added" is true of this JSON; it is not a global budget audit |

Trail findings.

1. **The run65 timestamps are append times, not event times.** The `mac-link` row is stamped 20:04:14 but the user assignment request is at 20:05:08. The `input-design` row is stamped 20:11:17 but the two design dispatches are at 20:07:22 and 20:07:29. The rows were written in a batch after the events. That does not make the claims false, but it breaks the trail's ordering guarantee. A reader cannot use the TSV to reconstruct what was known when.
2. **The brief's baseline was stale from the start of the bounded read.** The task said the parent's pending edits were docs only. At 20:14 the working tree had uncommitted `AppModel.swift`, `Assistant.swift`, `EffectLedger.swift` and a new `SharedReadRecoveryTests.swift`. The parent then committed the fixes as `5912cd7` and the handoff as `4fda967`. The admission seam is still unchanged at `AppModel.send:224` and `Assistant.handle:117`, but a reader using the original brief would diff the wrong tree. State the baseline commit, not "docs only."
3. **The 6 PM leeway claim is not visible in the bounded user evidence.** `FINAL_HOURS.md` says the working-demo target is 6:00 PM ET with leeway, and the `acceptance-docs` reason cites it. The user message at 2670 assigns the model but does not mention 6 PM. It may be earlier in the thread; this audit did not see it. Flag as unverified in range, not as a failed claim.
4. **The review-result gap was real at 20:14 and is now closed.** At 20:14:38 the last row was `follow-through` and the independent review result at 20:13:40 had no row. The parent has since added `review-repairs` at 20:19:24, `mac-restart` and `action-followup` at 20:21:46. The new rows are supported by the saved 189-test log, the user restart message at 2812 and the dispatch JSON. The earlier gap is worth remembering, but it is no longer a missing row.
5. **The `follow-through` row's "stopped" wording is wrong.** The first Mac worker returned a completed result; it did not stop or crash. The substantive point, that it did not compile, is true.
6. **The `packaging-fix` "Mac retest pending" is accurate at the row time but stale now.** The v2 worker later confirmed the patched symbol check and still reported absent provenance. If the parent summarizes run65, it should say "symbol check retested on the Mac; full fixture suite and provenance remain open," not "Mac retest pending" or "packaging fixed."
7. **The 20:22:34 summary merges a Linux/mock suite with a narrow Mac check.** It says "All 88 packaging checks pass; the Mac retest confirms the fix." The saved evidence is 88 Linux/mock fixtures plus a Mac run confirming the defined llama symbol. It is not an 88-check Mac run. The TSV's `packaging-fix` row is more precise. Keep the distinction in any handoff.
8. **Post-scope note.** After the 20:21:46 rows the parent added `mac-resume` at 20:29:02. It is supported by the user message "MacBook + iPhone are back" at 2832 and the worker's 8.1 GiB report at 2842. The same worker reported a compile fix at `AppModel.swift:206` at 2852. That is a code edit outside the design's original baseline. The admission change should rebase on it before implementation.

No pass is claimed for phone acceptance, compile, install, file protection, backup or process-kill recovery. Those remain unverified.

## Next implementation step

Write `RequestLedger` and its PocketCore tests first, with no AppModel changes. Land the table, the file store, the CAS claim, expiry and the restart test. Then change `Assistant.handle` to take the ingress `UserRequestID`, wire `submit`, `resume`, `discard` and the pending bar, and leave voice and camera to the second commit. That keeps the first verifiable unit small and keeps the effect journal's state machine untouched.
