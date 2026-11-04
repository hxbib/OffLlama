# Durable explicit request resume

Candidate design for Pocket Glimmer. The assigned grounding commit is `1e5c56e`; all code citations below are at that commit. While this was being written, the parent moved HEAD to `4fda967` with a small shared-read recovery change and docs. That change strengthens the ledger's ambiguous-read state and does not alter the busy-input defect or the store shape proposed here. No repository file was changed by this inspection, no paid call was made, I started no agent or checkout, and no Xcode or Swift build was run in this container. Runtime claims are labeled as such.

Scope of the first slice: typed chat, App Intent text, shared text/files, and voice. Camera is a separate view-only path and is planned as slice 2.

**Short answer.** Use a dedicated `RequestInputStore` over a separate protected SQLite database. `AppModel.send` writes one immutable body keyed by a new `UserRequestID` before it reads `busy`. A deferred request becomes a saved-request card with Resume and Discard. `Assistant.handle` accepts that same ID, so every card and attempt is bound to the ingress. Resume is explicit, never automatic, and only allowed after a read-only query of `EffectLedger` proves no effect attempt exists or shows the existing card. Effects remain entirely in the existing ledger.

## Problem

`AppModel.send` still refuses a request before it stores anything. The busy guard is `AppModel.swift:224`, and the payload reaches `Assistant.handle` only at `AppModel.swift:231`. A share, typed request, or intent that arrives while busy returns a string and has no durable body. `ChatView` clears the field at `ChatView.swift:32` before the async call, so a refused typed request can lose its text. `VoiceRecorder.stop` deletes the WAV at `VoiceCapture.swift:62`, then `MicButton.finish` checks `model.busy` at `:114`, so a busy voice request loses the recording. `GlimpseView.run` (`GlimpseView.swift:73-95`) never checks or sets `busy` and keeps its photo, question, and result in view state.

The current tree no longer uses a production `SharedInbox`; `sharedText` is passed directly to `Assistant.handle`. The old `SharedInbox` class still exists at `Skills.swift:283-303` and its tests still use it. It should be deleted in this change so there is only one ingress path.

`EffectLedger` already persists action drafts, confirmed reply payloads in `_sharedText`, and recovery state (`EffectLedger.swift:739-761`, `:1567-1584`, `:1586-1624`). It does not own the request before `Assistant.handle` runs. `Assistant.handle` also creates a fresh `UserRequestID` internally at `Assistant.swift:117`, so a card cannot be tied to the ingress request.

The missing unit is therefore narrow. It is a pre-handle request body keyed by the same `UserRequestID`, written before admission, plus an explicit resume projection. It is not a queue and not a second effect journal.

## Usage (caller's view)

### 1. Typed chat

The composer keeps its current shape. The only change is that the field is restored only when staging was refused.

```swift
// ChatView.swift, replacing the button action at :31-35
Button {
    let t = input
    input = ""
    Task {
        let receipt = await model.send(t)
        if receipt.outcome == .refused, input.isEmpty { input = t }
    }
} label: {
    Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
}
.disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || model.busy)
```

`send` stages before it reads `busy`. If staging succeeds and the app is busy, the user sees a saved-request card. If staging fails, the call returns `.refused` and the field is restored. Nothing is called saved before the row exists.

### 2. Share or App Intent text

`HandleTextIntent.perform` keeps building the body and the utterance exactly as today (`SkillIntents.swift:57-68`). It only adapts to the typed receipt.

```swift
let receipt = await AppModel.shared.send(
    ask, sharedText: body, origin: .share, sourceLabel: source)
return .result(value: receipt.message)
```

`AskPocketGlimmerIntent` and `RunSkillIntent` use the default `.typed` origin and return `receipt.message`. Their call sites do not need to know about the store.

### 3. Voice

`VoiceRecorder.stop` no longer returns bare bytes and deletes the file. It returns a recording handle and leaves the temporary WAV in place. The caller stages the bytes, then deletes the temporary file only after the stage succeeds.

```swift
// MicButton.finish, replacing :111-132
guard let rec = recorder.stopKeepingFile() else { return }
guard rec.data.count > 44 + 16_000 else {
    recorder.delete(rec)
    note("Hold the mic while you speak.")
    return
}
let receipt = await model.submitVoice(rec.data, duration: rec.duration)
if receipt.outcome == .refused {
    recorder.keepForRetry(rec)       // visible retry, no silent delete
    note(receipt.message)
} else {
    recorder.delete(rec)             // the store owns the bytes now
    note(receipt.message)
}
```

If the app is busy, `submitVoice` stages and returns `.deferred`. The saved card says the recording is kept and will be transcribed only on Resume. If staging fails, the temporary recording is kept for a session retry and the note says nothing was saved and nothing was sent.

### 4. Saved-request projection

A saved request is a normal assistant bubble with a staged projection. It is not a `DraftCard` and it never confirms an effect.

```swift
// Bubble, assistant branch
if let saved = item.staged {
    VStack(alignment: .leading, spacing: 8) {
        Text(saved.state == .interrupted ? "Request interrupted" : "Saved request")
            .font(.headline)
        Text(saved.preview).font(.callout)
        Text("Expires \(saved.expiresAt.formatted(date: .abbreviated, time: .shortened))")
            .font(.caption2).foregroundStyle(.secondary)
        if let blocked = item.stagedBlocked {
            Text(blocked).font(.caption).foregroundStyle(.orange)
        }
        HStack {
            Button(saved.state == .interrupted ? "Try again" : "Resume") {
                Task { await model.resume(item) }
            }
            .disabled(model.busy || item.stagedBlocked != nil)
            Button("Discard", role: .destructive) { model.discard(item) }
        }
        .buttonStyle(.bordered).controlSize(.small)
    }
    .padding(12)
    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
}
```

`Resume` is disabled while another request is busy. `Discard` is local and can run while busy for a staged or interrupted row. If the row is already claimed by a running resume, `discard` returns `.alreadyClaimed` and the view says the request is already running. A blocked interrupted request shows the ledger's reason and offers only `Discard`.

### 5. Launch recovery

`AppModel.init` opens `RequestInputStore` and calls `recoverOnLaunch` once. That is cheap and does not depend on the model, so a saved request is visible even when model loading later fails. A failure to open the store sets `inputsError`; `send` then refuses every request instead of pretending to save. If the first open fails because the device was locked, `AppModel` retries the open on the first foreground send after activation. It never reopens a store while a resume is live; `recoverOnLaunch` is meaningful only on a fresh process.

`bootOnce` already restores effect cards at `AppModel.swift:169`. Add one reconciliation pass after that.

```swift
restoreEffectCards(a)
reconcileStagedInputs(a)   // reads the ledger and updates projections; never calls a.handle
```

The pass may complete an input whose card already exists, mark a row from a previous process as interrupted, expire old rows, and disable Resume for an uncertain effect. If the model never loads, the cards from `init` remain visible with Resume disabled. No branch calls `Assistant.handle`, `confirmEffect`, or any effect executor.

## Shape

### Core types

One row per request. One body. The body is insert-only. State changes never replace it.

```swift
public struct RequestInputPolicy: Sendable, Equatable {
    public var ttl: TimeInterval                 // 24 h
    public var maxActive: Int                    // 8
    public var maxTotalBytes: Int                // 8 MiB
    public var maxTextCharacters: Int            // 24,000, the existing shared-text limit
    public var maxVoiceBytes: Int                // 2 MiB, about 60 s at 16 kHz mono 16-bit
    public var tombstoneRetention: TimeInterval  // 30 days
    public var previewCharacters: Int            // 160
    public static let standard: RequestInputPolicy
}

public enum RequestInputOrigin: String, Sendable, Codable {
    case typed, share, voice
    // .camera is added in slice 2; the state machine does not change.
}

public enum RequestInputState: String, Sendable, Codable {
    case staged, claimed, interrupted, completed, discarded, expired
}

public enum RequestInputBody: Sendable, Equatable {
    case text(String)
    case sharedText(utterance: String, text: String)
    case voice(wav: Data, duration: TimeInterval)
}

public struct RequestInputSummary: Sendable, Equatable, Identifiable {
    public let id: UserRequestID
    public let origin: RequestInputOrigin
    public let sourceLabel: String
    public let preview: String          // stored at stage, no body load
    public let byteCount: Int
    public let createdAt: Date
    public let expiresAt: Date
    public let state: RequestInputState
    public let interruption: String?    // set only for .interrupted
}

public struct ClaimedRequestInput: Sendable, Equatable {
    public let id: UserRequestID
    public let body: RequestInputBody
    public let sourceLabel: String
    public let transcript: String?      // voice only, derived once
    public let expiresAt: Date
}
```

`RequestInputSummary` is the UI projection. It carries a short preview and no full body, so listing saved requests at boot does not load every payload into memory. `ClaimedRequestInput` is the only value that carries the body, and only one caller can hold it.

### Store

```swift
public final class RequestInputStore: @unchecked Sendable {
    public init(directory: URL,
                policy: RequestInputPolicy = .standard,
                now: @escaping () -> Date = Date.init) throws

    @discardableResult
    public func stage(_ body: RequestInputBody,
                      origin: RequestInputOrigin,
                      sourceLabel: String = "") throws -> RequestInputSummary

    public func claim(_ id: UserRequestID) throws -> ClaimedRequestInput
    public func retryInterrupted(_ id: UserRequestID) throws -> ClaimedRequestInput
    public func setTranscript(_ text: String, for id: UserRequestID) throws

    public func complete(_ id: UserRequestID) throws
    public func interrupt(_ id: UserRequestID, reason: String) throws
    public func discard(_ id: UserRequestID) throws

    public func recoverOnLaunch() throws -> [RequestInputSummary]
    public func summaries() throws -> [RequestInputSummary]
    @discardableResult public func purgeExpired() throws -> Int
}
```

The public surface hides the schema, SQL, validation, size accounting, TTL, claim CAS, secure deletion, and file protection. Callers see request IDs, previews, and one claimed body.

`stage` generates the `UserRequestID` and returns its summary. There is no global slot and no public way to attach a second body to the same ID. A duplicate primary key throws `.alreadyExists`.

`claim` accepts only `.staged` and only before `expiresAt`. `retryInterrupted` accepts only `.interrupted` and performs the same atomic transition to `.claimed`. `complete`, `interrupt`, and `discard` are idempotent state transitions. `recoverOnLaunch` is one-shot per store instance. Its first call converts every `.claimed` row from a previous process to `.interrupted`, expires old rows, purges old tombstones, and returns active summaries. A second call on the same instance only expires and lists, so it can never turn a live claim into an interruption. `summaries` does the same expiry and purge without the claimed conversion.

The error type is domain-level, not SQLite-level.

```swift
public enum RequestInputError: Error, Equatable, CustomStringConvertible {
    case alreadyExists
    case notFound
    case expired
    case alreadyClaimed
    case notResumable
    case invalidPayload(String)
    case tooLarge
    case capacity
    case storage(String)
}
```

### Effect query and resume policy

The input store does not know about effects. The ledger stays the only owner of effect state. Add one read-only query.

```swift
public enum RequestEffectState: Sendable, Equatable {
    case none
    case awaiting(DraftCard)
    case settled
    case uncertain(String)   // claimed or ambiguous, or an undecodable row
}

extension EffectLedger {
    public func requestState(for requestID: UserRequestID) throws -> RequestEffectState
}
```

The query reuses the existing `action_attempts` index on `request_id` (`EffectLedger.swift:759`), the existing decoder, `EffectLedger.contract(for:)`, and `EffectLedger.card(for:)`. It adds no columns and no phase. Any `.claimed` or `.ambiguous` row wins as `.uncertain`. Otherwise an `.awaitingUser` row becomes `.awaiting(card)`. Settled-only rows become `.settled`. No rows become `.none`.

The UI decision is a pure function, so it is testable on Linux.

```swift
public enum ResumeDisposition: Sendable, Equatable {
    case run
    case showCard(DraftCard)   // caller completes the input and shows the card
    case alreadyFinished       // caller completes the input, no new card
    case blocked(String)       // caller keeps the input for Discard only
}

public enum RequestResumePolicy {
    public static func disposition(input: RequestInputState,
                                   effect: RequestEffectState) -> ResumeDisposition
}
```

Rules:

| Input state | Effect state | Disposition |
|---|---|---|
| `.staged` | `.none` | `.run` |
| `.staged` | `.awaiting(card)` | `.showCard(card)` |
| `.staged` | `.settled` | `.alreadyFinished` |
| `.staged` | `.uncertain(reason)` | `.blocked(reason)` |
| `.interrupted` | `.none` | `.run` (UI label "Try again") |
| `.interrupted` | `.awaiting(card)` | `.showCard(card)` |
| `.interrupted` | `.settled` | `.alreadyFinished` |
| `.interrupted` | `.uncertain(reason)` | `.blocked(reason)` |
| anything else | anything | `.blocked("This saved request is not resumable.")` |

This is the rule that keeps an interrupted action from silently re-running. The store cannot prove whether an effect ran. The ledger can. If the ledger has any claimed or ambiguous attempt for that request ID, Resume is blocked. Only a request with no ledger attempt at all can be explicitly retried.

### AppModel surface

```swift
struct SendReceipt: Sendable, Equatable {
    enum Outcome: Sendable, Equatable { case handled, deferred, refused }
    let outcome: Outcome
    let requestID: UserRequestID?
    let message: String
}

// AppModel
private(set) var inputs: RequestInputStore?
private(set) var inputsError: String?

@discardableResult
func send(_ text: String,
          sharedText: String? = nil,
          origin: RequestInputOrigin = .typed,
          sourceLabel: String = "") async -> SendReceipt

@discardableResult
func submitVoice(_ wav: Data, duration: TimeInterval) async -> SendReceipt

func resume(_ item: ChatItem) async
func discard(_ item: ChatItem)
```

`ChatItem` gains two optional fields, both projections only:

```swift
var staged: RequestInputSummary? = nil
var stagedBlocked: String? = nil
```

`send` and `submitVoice` share one private `runClaimed` path. `send` stages, then either defers or claims and runs. `resume` claims an interrupted row only after `RequestResumePolicy` says `.run`. There is no second runner.

### Assistant binding

`Assistant.handle` accepts the ingress identity. The body still arrives as a direct parameter; there is no resolver and no new global.

```swift
public func handle(_ utterance: String,
                   now: Date = Date(),
                   sharedText: String? = nil,
                   requestID: UserRequestID = UserRequestID()) async throws -> AssistantTurn
```

Delete the local `let requestID = UserRequestID()` at `Assistant.swift:117`. Every existing call to `planSkillCore`, `toolPath`, `stageRead`, and `EffectSession.evaluate` already threads the ID. The default preserves the existing test call sites. A resumed request passes the original ID, so its `DraftCard.requestID`, `action_attempts.request_id`, and receipt all match the ingress.

The shared-text length check at `Assistant.swift:113` stays. The store also checks the same `ActionValidation.sharedTextLimit` so an oversized share is refused before a row is written.

## Module map

| File | Change | Rough size |
|---|---|---:|
| `core/Sources/PocketCore/RequestInputStore.swift` (new) | Schema, state machine, claim CAS, size/TTL policy, protected database, `RequestResumePolicy` | 280 lines |
| `core/Sources/PocketCore/EffectLedger.swift` | Read-only `requestState(for:)` using the existing decoder and card builder | 35 lines |
| `core/Sources/PocketCore/Assistant.swift` | Add defaulted `requestID` to `handle`; remove the internal ID creation | 3 lines |
| `core/Sources/PocketCore/Skills.swift` | Delete the dead `SharedInbox` class | -20 lines |
| `app/PocketGlimmer/AppModel.swift` | Open the store, stage-first `send`, `submitVoice`, `resume`, `discard`, launch reconciliation | 140 lines |
| `app/PocketGlimmer/Views/ChatView.swift` | Saved-request card, input restore on refusal | 70 lines |
| `app/PocketGlimmer/Capture/VoiceCapture.swift` | Keep the WAV until staging succeeds, stage before busy, resume transcription helper | 80 lines |
| `app/PocketGlimmer/Intents/Intents.swift`, `SkillIntents.swift` | Adapt to `SendReceipt`, pass `.share` origin | 10 lines |
| `core/Tests/PocketCoreTests/RequestInputStoreTests.swift` (new) | Store, TTL, claim, Unicode, failure, deletion | 300 lines |
| `core/Tests/PocketCoreTests/EffectRecoveryTests.swift` | Request-state and resume-policy tests | 80 lines |
| `docs/research/EFFECT_RECOVERY_CONTRACT.md` | Amend line 604: ingress creates the ID; `handle` accepts it | 15 lines |

There is no new capability, no new `AttemptPhase`, no new `DraftCard` field, and no schema change to `action_attempts`.

## Lifecycle

### Text and share

1. `send` trims and validates. Empty text and empty shared text are refused before staging.
2. `inputs.stage(...)` inserts one row. The body, preview, byte count, source, creation time, and expiry are committed together. A failure returns `.refused`; no card is shown.
3. If `busy` is true, or `assistant` is nil, append a saved-request card and return `.deferred`. No claim.
4. Otherwise `runClaimed` re-checks `busy`, calls `inputs.claim(id)` before any await, sets `busy = true`, loads scrubber names, and calls `assistant.handle(utterance, sharedText: body, requestID: id)`.
5. On return, render the turn, then `inputs.complete(id)`. Completion nulls the body and keeps a tombstone. If a card was staged, the ledger already holds `_sharedText`; ownership has moved. If `complete` itself fails, the row stays claimed and the next launch reconciles it against the ledger, so the result is not lost and the body is not left behind indefinitely.
6. On throw, `inputs.interrupt(id, reason:)`. The body is kept and the card becomes interrupted. The error is shown. No automatic retry.
7. `defer` clears `busy` and refreshes memory and telemetry. It never scans, claims, or resumes saved requests.

### Voice

1. `VoiceRecorder.stopKeepingFile` stops the recorder and returns `(data, temporaryURL, duration)`. It does not delete the file.
2. `submitVoice` stages `.voice(wav, duration)` before it checks `busy`. On stage failure it returns `.refused`; the caller keeps the temporary file and shows a retry note.
3. On stage success the caller deletes the temporary file. The store owns the WAV.
4. When idle, `runClaimed` sets busy, claims, and calls the extracted `VoiceIngress.transcribe`. If `claimed.transcript` is already present, it is used. Otherwise the existing `MultimodalGate` transcription runs, the transcript is written once with `setTranscript`, and `assistant.handle(transcript, requestID: id)` runs.
5. On return, `complete` deletes the WAV. On transcription or handle failure, `interrupt` keeps the WAV. The card says the recording is saved as interrupted. The user can try again or discard.
6. A crash after `setTranscript` but before `complete` reopens to an interrupted record with a transcript, so the cloud transcription is not paid for twice. A crash before `setTranscript` repeats the transcription on explicit retry. That is the accepted cost of not writing a transcript before the cloud call returns.

`VoiceIngress` is the existing transcription block from `MicButton.finish`, moved to one place so the first run and the resume path are identical. It does not introduce a new model or change `MultimodalGate`.

### Restart and reconciliation

`recoverOnLaunch` performs four steps in order:

1. `state = claimed` becomes `interrupted` with the reason "The app stopped while this request was running."
2. `staged` or `interrupted` rows past `expiresAt` become `expired`, and their bodies are nulled.
3. Terminal tombstones older than `tombstoneRetention` are deleted.
4. Active summaries are returned.

`AppModel.init` calls it and shows those summaries immediately. When the assistant is available, `AppModel.reconcileStagedInputs` checks each summary with `EffectLedger.requestState`:

- `.awaiting(card)`: complete the input and let `restoreEffectCards` show the existing card. The body is not duplicated.
- `.settled`: complete the input. The request already finished.
- `.uncertain(reason)`: show the input card as interrupted with `reason` and disable Resume. Only Discard is offered.
- `.none`: show the input as staged or interrupted. If interrupted, Resume is labeled "Try again" and is allowed only after the explicit tap.

No branch calls `handle`.

### Explicit resume

1. The user taps Resume or Try again.
2. `resume` refuses immediately if `busy`. It does not claim and then wait.
3. It reads `requestState` and applies `RequestResumePolicy`.
4. `.blocked` updates the card's blocked reason.
5. `.showCard` completes the input and appends the card if it is not already visible.
6. `.alreadyFinished` completes the input and removes the card with a system note.
7. `.run` calls `claim` for `.staged` or `retryInterrupted` for `.interrupted`. The CAS decides the winner. A second tap gets `.alreadyClaimed` and a note that the request is already running.
8. `runClaimed` proceeds exactly as the first run.

### Interrupted effect

The input store never decides that an action happened. The effect ledger does. If the app dies after an effect claim, the ledger's `recover` already exposes an unresolved attempt (`EffectLedger.swift:890-920`). `requestState` returns `.uncertain` for that request ID. The input card is shown as interrupted and Resume is disabled. The user sees both the unresolved effect summary and the request that produced it. Nothing re-runs.

If the app dies before any ledger row exists, `requestState` returns `.none`. The input is still interrupted, but an explicit Try again is safe with respect to external actions. Local memory writes before the crash may repeat. That is the only duplicate work this design accepts, and it is visible to the user as a retry.

### Camera, planned separately

Slice 1 does not include camera. `GlimpseView` stays view-only, and the existing loss on sheet dismissal or process death remains. This design does not claim otherwise. The camera button remains disabled while `model.busy`, so the first slice does not make that path worse. If camera is required in the same change, it must be a separate commit with its own view-resume route; camera must not be routed through `Assistant.handle` just to reuse the text resume card.

Slice 2 adds a `.camera(jpeg: Data, question: String, concept: String?, mode: String, photoText: String)` body and the same store lifecycle. `GlimpseView.run` stages before its cloud call, defers if busy, claims when idle, and completes on a result. A throw interrupts and keeps the JPEG. A saved camera card resumes by reopening `GlimpseView` with the stored JPEG and question; it does not go through `Assistant.handle` and does not create a fake `PlannedAction` or effect attempt. The photo text is stored because it is the on-device sensitivity input and must not be silently recomputed differently. The camera image gets a 1 MiB cap, the same 24 h TTL, and the same protected, backup-excluded store. This keeps camera's separate view and cloud path while giving its captured bytes an owner.

## Storage, size, TTL, and deletion

The store is a separate SQLite database, not a table in `pocket.sqlite`.

| Concern | Policy |
|---|---|
| Location | `Application Support/PocketGlimmer/RequestInputs/request-inputs.sqlite` |
| Owner | `RequestInputStore` only. No other module opens this file. |
| SQLite mode | `journal_mode=DELETE`, `synchronous=FULL`, `secure_delete=ON` |
| File protection | iOS `.complete` on the directory and database. New files inherit the directory class. Reapplied at open. |
| Backup | `isExcludedFromBackup = true` on the directory and database. A staged request does not enter iCloud or iTunes backup. |
| Active cap | 8 rows and 8 MiB total body bytes. A new stage that would exceed either is refused with `.capacity`; nothing is evicted. |
| Text cap | 24,000 characters for the utterance and for shared text, matching `ActionValidation.sharedTextLimit`. |
| Voice cap | 2 MiB, about the 60 s recorder limit. |
| TTL | 24 hours from stage. The card shows the absolute expiry. Logical expiry is immediate; physical purge happens on the next store access or launch. |
| Body deletion | `complete`, `discard`, and `expired` null the utterance, payload text, payload blob, payload metadata, transcript, and preview in one update. `secure_delete` zeroes the old cells. |
| Tombstone | `request_id`, terminal state, timestamps, origin, and byte count remain for 30 days. No body and no preview. |
| Vacuum | After a purge deletes rows, `VACUUM` outside the transaction to reclaim pages. |
| Locked device | `.complete` means the store cannot be opened or written while the device is locked. The ingress returns "not saved" and does not claim success. |

The table shape is deliberately small. It is one row per request and one body per row.

```sql
CREATE TABLE request_inputs (
  request_id TEXT PRIMARY KEY,
  state TEXT NOT NULL,
  origin TEXT NOT NULL,
  source_label TEXT NOT NULL DEFAULT '',
  preview TEXT NOT NULL,
  byte_count INTEGER NOT NULL,
  utterance TEXT,
  payload_kind TEXT NOT NULL,
  payload_text TEXT,
  payload_blob BLOB,
  payload_meta TEXT,
  transcript TEXT,
  created REAL NOT NULL,
  expires REAL NOT NULL,
  claimed_at REAL,
  updated REAL NOT NULL,
  interrupt_reason TEXT
);
CREATE INDEX request_inputs_active ON request_inputs(state, created);

CREATE TRIGGER request_inputs_body_immutable
BEFORE UPDATE OF utterance, payload_text, payload_blob, payload_meta, created, expires
ON request_inputs
FOR EACH ROW
WHEN (OLD.utterance IS NOT NULL OR OLD.payload_text IS NOT NULL OR OLD.payload_blob IS NOT NULL)
 AND (NEW.utterance IS NOT NULL OR NEW.payload_text IS NOT NULL OR NEW.payload_blob IS NOT NULL)
BEGIN
  SELECT RAISE(ABORT, 'request input body is immutable');
END;
```

Terminal deletion sets every body field to null in one update, so the `WHEN` clause is false and the trigger allows the clear. Any attempt to replace a live body with a different one aborts. `transcript` is not in the trigger's column list because it is a one-time derived field, written before `handle`.

The database is not additionally encrypted. It relies on iOS Data Protection plus backup exclusion. That is a deliberate first-slice boundary, not a claim of forensic erasure. If the threat model includes a jailbroken device or extraction from a backup, a Keychain-wrapped key is a follow-up.

`pocket.sqlite` already contains `_sharedText` in confirmed read cards and memory/telemetry. That file remains backed up as before. This slice does not widen that surface for long-lived data, but it does not repair it either. The pre-handle copy is in the excluded store and is deleted after handoff.

## Invariants

1. Every accepted request has a durable row before `busy` is read.
2. Every request has one `UserRequestID`, created at ingress, and the same ID reaches `Assistant.handle`, every card, and every `action_attempts.request_id`.
3. A request has one immutable body. The only body update is deletion to null. The database trigger rejects replacement.
4. No global current-request slot exists. Every lookup is by request ID. `SharedInbox` is deleted.
5. `claim` and `retryInterrupted` are compare-and-swap transitions. At most one caller holds a body for a given ID.
6. App launch and busy-clear are projection-only. They never call `handle`, confirm an effect, or perform an action.
7. A row left `claimed` by a previous process becomes `interrupted`. It is never automatically re-run.
8. An interrupted input may be explicitly retried only when the ledger has no attempt for that request ID. An awaiting card is shown instead. A claimed or ambiguous attempt blocks retry.
9. A persistence failure returns `.refused` and is never described as saved. Typed input is restored when possible, voice keeps its temporary recording, and a share returns an explicit failure.
10. `complete`, `discard`, and `expired` delete the body and keep only a non-sensitive tombstone.
11. Limits refuse new work; they never evict an existing saved request.
12. The input store never claims, performs, or records an effect. The effect ledger never owns pre-handle input.

## Why this shape

**Data structures first.** The dominant access patterns are insert by new ID, scan active rows at launch, claim one row by primary key, and expire or delete by state and time. One table with a primary key on `request_id` and an index on `(state, created)` serves all four. There is no later map, cache, or queue to add. The preview column exists so the launch scan does not load bodies.

**Interface depth and boundary discipline.** The store's ten methods hide a schema, a six-state machine, validation, UTF-8 byte accounting, capacity accounting, claim CAS, TTL, secure deletion, file protection, and backup exclusion. The caller does not coordinate a load, validate, save, and claim sequence. One `stage` and one `claim` complete each operation. External text, files, audio, and SQL rows are parsed at the store boundary. Inside the app, callers handle `RequestInputBody` and `ClaimedRequestInput`, not SQL. The resumability decision lives in the pure `RequestResumePolicy`, not in a view.

**Single source of truth and idempotence.** The input store owns "does the pre-handle body exist." The effect ledger owns "did an effect start or finish." The store never copies a receipt. The ledger never copies a pre-handle body. `complete`, `discard`, and `interrupt` converge on repeat. `claim` is the one non-idempotent operation, and its second call is a typed `.alreadyClaimed`, which the UI can explain. A crash at any point leaves a state that recovery can classify without guessing.

**Small change against the deadline.** The effect journal is untouched except for one read query. The planner, calibration, model options, action validation, contracts, and confirmation state machine are unchanged. The new code is one store, one policy function, one projection card, and one voice refactor. The call chain stays UI to `AppModel` to `RequestInputStore` and `Assistant` to `EffectLedger`, with no background worker or scheduler.

## Alternatives considered

### Journal-integrated intake (rejected)

This alternative puts the request body in the existing effect journal. It has two concrete forms.

**A. A new `.intake` phase on `action_attempts`.** `AppModel.send` inserts an attempt row before the busy check, with a placeholder capability and the body in `args_json`. On resume, the row transitions from `.intake` to the normal planning and claim path.

Why it loses: an input exists before a capability, a `BoundAction`, a confirmation floor, or an effect class exists. `insertAwaiting` requires a capability and an action (`EffectLedger.swift:769-789`). Adding `.intake` forces every exhaustive switch over `AttemptPhase`, plus `readiness`, `card`, `recover`, `result`, `cancel`, and `duplicateHint`, to handle a row that is not an effect. That is a wide blast radius for a deadline. It also conflates "the body is saved" with "an action is pending," which is exactly the distinction the accepted Muse requirement draws (`MUSE_REVIEW_FINDINGS.md:26-29`). The contract already says reply-only reads are never claimed and never a workflow step (`EFFECT_RECOVERY_CONTRACT.md:201`).

**B. A `request_inputs` table inside `pocket.sqlite`, still owned by `EffectLedger`.** This is structurally closer to the chosen design, but it co-locates the sensitive body with the effect journal.

Why it loses: `pocket.sqlite` is backed up and has one protection class for memory, telemetry, and confirmed effect cards. The input body needs a shorter TTL, a smaller cap, and an excluded backup. Putting it in the same file either weakens that policy or forces a whole-database protection change that affects unrelated features. The shared transaction benefit is small because the effect journal already classifies a crash between claim and receipt as uncertain (`EffectLedger.swift:890-920`). The chosen design gets the same recovery guarantee without making the ledger a second kind of store.

The chosen design does accept two SQLite files and no cross-database transaction. That is deliberate. The effect ledger's claim is the authority for whether an action started. The input store's claim is the authority for whether a body was handed to the planner. Every interleaving is recoverable by reading both, and the reconciliation table above specifies each one.

### A file-per-request JSON store

Considered and folded into the storage choice. It would make file protection and deletion obvious, but claim atomicity would depend on atomic rename plus a process lock, and crash durability would be weaker than a `synchronous=FULL` SQLite transaction. The separate SQLite file keeps the same isolation with a stronger claim primitive and the existing `SQLiteDB` API.

## Design red-flag check

| Red flag | Verdict |
|---|---|
| Shallow module | Pass. Ten methods hide schema, state, validation, caps, TTL, CAS, secure deletion, and protection. |
| Information leakage | Pass. SQL, table names, paths, and the journal mode stay private. Public types are domain IDs, bodies, summaries, and errors. |
| Temporal decomposition | Pass. The store owns the whole input lifecycle. `AppModel` owns admission and UI projection, not a second copy of the state rules. |
| Pass-through method | Pass. `requestState` performs a real query, decode, and card build. `RequestResumePolicy` is pure policy. Neither merely forwards arguments. |
| Split ownership | Pass with a named handoff. The input store owns the body before `handle`; the effect ledger owns the card payload after `handle`. `complete` follows the awaited handoff. Neither writes the other's state. |
| Two ways to do one task | Pass. `send` is the single text ingress. Voice stages then uses the same `runClaimed` path. `SharedInbox` is deleted. There is no in-memory fallback. |
| Importable internals | Pass. The database handle, schema, encoder, and file paths are private to the store. |
| Hand-synced list | Pass. `RequestInputBody` drives encoding and decoding. Limits live in one `RequestInputPolicy`. The camera case in slice 2 will force an exhaustive switch at compile time. |

The one residual structural cost is two SQLite files. It is a deliberate ownership boundary, not an accidental split. The reconciliation matrix and the request-state query are the proof that the boundary is closed.

## Tests

No Swift toolchain is present in this container, so none of these were run here. The parent's existing suite is reported at 136 tests with one skipped in the project record. At the newer `4fda967`, `SharedReadRecoveryTests.swift` already covers the failed-read ambiguous state; do not duplicate it. The tests below add the request-input store, the ingress ID binding, and the resume policy.

### Core tests, Linux or macOS `swift test`

`RequestInputStoreTests.swift`

| Test | Proves |
|---|---|
| `testStageClaimCompleteDeletesBody` | Stage, claim, complete, reopen. Raw database bytes no longer contain the body; a second claim is impossible; the summary list is empty. |
| `testRestartRestoresStagedWithoutClaim` | Stage, drop, reopen, `recoverOnLaunch` returns `.staged`. No claim occurs until `claim` is called. |
| `testReopenTurnsClaimedIntoInterrupted` | Stage, claim, drop, reopen. `recoverOnLaunch` returns `.interrupted`; `claim` throws; `retryInterrupted` works only explicitly. A second `recoverOnLaunch` does not convert a live claim. |
| `testConcurrentClaimWinsOnce` | Eight concurrent claims. One body is returned; the rest throw `.alreadyClaimed`. |
| `testTwoDistinctSharedTextsStayDistinct` | Stage A and B. Claim A, assert A. Claim B, assert B. Complete A, assert B is unchanged. |
| `testExpiryPurgesBody` | Inject a clock, pass the TTL, call `summaries`. State is `.expired`, `claim` throws, raw payload is absent. |
| `testUnicodePayloadRoundTrips` | Emoji ZWJ, combining accent, Arabic, CJK. Exact body equality, UTF-8 byte count, and a grapheme-safe preview. |
| `testNulIsRejected` | U+0000 throws `.invalidPayload`. `SQLiteDB` binds text with length -1, so a NUL would truncate. |
| `testCapacityAndOversizeRefuse` | `maxActive = 1` refuses a second row; 24,001 shared characters and a 2 MiB+ voice body refuse. The first body is untouched. |
| `testDiscardDeletesBodyAndIsIdempotent` | Discard twice. The second call is a no-op and the body bytes are gone. |
| `testTranscriptIsWrittenOnce` | A voice transcript is accepted once; a different second value is rejected; reopen returns the same transcript. |

`EffectRecoveryTests.swift` additions

| Test | Proves |
|---|---|
| `testRequestStateDistinguishesFourStates` | None, awaiting, settled, and uncertain for one request ID using the existing fake effects. |
| `testInterruptedEffectBlocksResume` | Claim an input and a ledger attempt for the same ID, leave both. Reopen. Input is `.interrupted`, ledger is `.uncertain`, policy is `.blocked`, executor count is zero. |
| `testAwaitingCardWinsOverInputRetry` | A staging card for the same ID yields `.showCard`; no retry is offered. |
| `testAssistantUsesIngressRequestID` | `handle(..., requestID:)` produces a `DraftCard.requestID` and ledger row matching the ingress ID. |
| `testTwoDocumentCardsKeepTheirOwnPayloads` | Reply-only cards A and B use their own shared text at confirm. Replaces the old `SharedInbox` global-read test. |

### App tests, Xcode or Simulator only

The app target has no test target today (`app/project.yml` declares only the application). Add `PocketGlimmerTests` or run these manually in the Simulator. They cannot be claimed as Linux proof. They need one small `#if DEBUG` seam: an `AppModel` initializer that accepts an injected `RequestInputStore` and assistant, or launch arguments that seed a staged row or force busy. Keep the seam out of release builds.

| Test | Proves |
|---|---|
| `testBusySendStagesBeforeTheGuard` | Busy send shows a saved card and no assistant bubble. Clearing busy does not run it. Resume runs exactly once. |
| `testRefusedStageKeepsTypedText` | A throwing store restores the field, shows no saved card, and says nothing was sent. |
| `testDoubleResumeRunsOnce` | Two quick Resume taps produce one claim and one handle call. |
| `testVoiceBusyKeepsRecording` | Busy recording is staged; the temporary file is not the only copy; Resume transcribes and handles once. |
| `testVoiceStageFailureKeepsRetry` | A failing stage keeps the temporary recording and never says saved. |
| `testLaunchShowsSavedCardWithoutRunning` | A seeded row appears after relaunch with no handle call. |
| `testKillDuringHandleShowsInterrupted` | A kill during a slow fake handle reopens interrupted; Resume is disabled when the ledger has a claimed attempt. |

### iPhone checks

File protection is actually `.complete` on the database and journal; backup exclusion survives a real backup. A share App Intent while locked returns "not saved." A busy share survives a real process kill and relaunch. Voice permission, recording, transcription, and route changes still work with the new stopping order. Camera is unchanged in slice 1; slice 2 needs its own photo, OCR, dismissal, and kill checks.

## Tradeoffs accepted

- We accept a second SQLite file and no cross-database transaction in exchange for an independent TTL, size cap, backup exclusion, and protection class. The ledger remains the authority for effects; the store remains the authority for pre-handle input.
- We accept a 24-hour TTL and an 8 MiB active cap in exchange for bounded sensitive-data retention. New requests are refused when full; existing saved requests are never evicted.
- We accept `.complete` file protection, so staging an App Intent while the phone is locked fails honestly. If locked-device sharing is required, the policy must move to `.completeUntilFirstUserAuthentication` or a Keychain-wrapped key, and that is a product and security decision.
- We accept a short window where the body exists in both the input store and the ledger during `Assistant.handle`. The input copy is deleted immediately after the awaited handoff.
- We accept that relative times are interpreted at resume time, not capture time. The confirmation card shows the resolved instant before any effect, so the user can correct it.
- We accept that a retry after an interruption with no ledger attempt may repeat local memory work. It cannot repeat a ledger-tracked external action.
- We accept that camera is not preserved in slice 1. The limitation is named, not hidden. Slice 2 uses the same store without making camera an effect.
- We accept that the tombstone is audit and duplicate protection, not a security boundary. Request IDs are UUIDs and are never reused, so the tombstone is not a replay-proof receipt.

## Open questions and risks

- Is 24 hours the right TTL, and is 8 MiB the right active cap? These are product choices. They are visible in the UI and easy to tune through `RequestInputPolicy`.
- Does a share need to work while the device is locked? If yes, `.complete` is too strict. The alternative is weaker protection or a Keychain-wrapped key.
- Is a second SQLite file acceptable operationally, or must everything stay in `pocket.sqlite`? The design prefers isolation because the retention and backup policies differ.
- Should the existing `_sharedText` in confirmed read cards also get a TTL and backup exclusion? It is outside this slice, but it is the larger long-lived sensitive-text surface.
- Is the app guaranteed to be one process for App Intents? `openAppWhenRun = true` suggests it. If an intent can stage from a second process, or if the store must reopen in the same process while a resume is live, `recoverOnLaunch` could mark a live claim as interrupted. A process-epoch column is the fix.
- Does the user want a persistent "1 saved request" badge outside the chat? Slice 1 uses chat cards only.
- The store performs synchronous SQLite writes on the main actor, matching `EffectLedger` usage. A 2 MiB voice insert may cause a visible frame hitch. Measure on device; if needed, move only the stage call to a utility queue and keep the claim ordering on the main actor.

## Next implementation step

Write `RequestInputStore` and its core tests first, including the reopen, concurrent claim, expiry, Unicode, and deletion cases. Then add `requestID` to `Assistant.handle` and the read-only `EffectLedger.requestState`. Wire `AppModel.send` and the saved-request card only after those two pieces are green. Leave camera and the `SharedInbox` test migration for the second commit in the same change.
