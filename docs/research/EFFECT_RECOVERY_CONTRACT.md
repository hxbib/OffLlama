# Reviewed effects

> Parent review update, 2026-11-04. This is the original Grok design snapshot. The
> [accepted Muse corrections](MUSE_REVIEW_FINDINGS.md#contract-corrections-accepted-after-the-remaining-reports)
> supersede conflicting sketches below, especially date re-resolution, edit/claim races,
> memory attempt tokens and reply-only confirmation. The planner must honor the configured
> Standard-mode Meta model. Implemented privacy fixes do not prove recovery or phone behavior.

Contract for one Pocket Glimmer feature: durable recovery of the effects the app can actually perform, including a later reviewed workflow saved on top of that same path. Tree `7b8d014ba35f9dec349898be3b4fa9b53fe3c3d3`. Research snapshots remain `d782b81`. The Swift below is the contract. It is not a source file to drop into the tree.

This pass does not build the iOS app, train a model, change τ / priors / prompts / gold artifacts, call a paid API, read a key, push, or edit product source. Mac and iPhone are unavailable. Nothing here is a device result.

Provider, model, and effort stay `grok` / `grok-4.7` / `xhigh`. No delegate.

## Problem

`Assistant.handle` (`core/Sources/PocketCore/Assistant.swift`) and `planSkillCore` (`core/Sources/PocketCore/ActionPlanner.swift`) call `execute` or `actions.perform` as soon as `confirmBeforeAct` returns `act`. `AppModel.confirm` runs only for the in-memory `ChatItem.pending` card, clears that card, and turns any throw into the text `Failed`. A journal wrapped around `AppModel.confirm`, or around a new workflow runner only, leaves reminder, event, shortcut, and URL effects that `handle` already performs unprotected.

`ActionExecutor.perform` and `SkillRunner.run` return arbitrary `String`s. `SystemActions.perform` returns `"Reminder set"` after `EKEventStore.save` and drops the identifier. A missing date becomes `Date() + 3600` seconds for events. `ComposeSheets` already maps Messages and Mail results into sentences; those sentences are not a typed receipt. Permission failures and `"Handed to Shortcut"` are also sentences. Treating any of those strings as a committed success is invalid.

`SkillRegistry.merge` lets a Documents JSON file replace a built-in id. `Skill.confirm` is forced only for categories `message`, `social`, and `email`. Call, FaceTime, and Uber confirmation is JSON data. `SQLiteDB.transaction` issues `BEGIN IMMEDIATE` and then calls `exec`, which takes the same recursive lock; a second `transaction()` inside the body starts a nested `BEGIN`, which SQLite rejects. The lock is held for the whole synchronous body, so a transaction cannot `await`. SQLite and EventKit do not share a transaction.

The frozen 1B, τ = 0.90, priors, and decision templates stay the single-step chooser. An exact phrase the user saves is a separate binding. It does not change a letter probability. `Assistant.reason` and the escalation memory block are not a safe planner transport: `a4e100f` has two failing privacy regressions (sensitive retrieved memory, and document screening of the first 400 characters only). See `/tmp/pocket-glimmer-takeover/privacy-grounding.md`.

## Scores

Scores are 1–5 against this tree. 5 is the favorable end.

| Shape | Complete behavior | Single ownership | App integration | Replay safety | Maintainability |
|---|---:|---:|---:|---:|---:|
| Capability-map EventKit title/time ledger | 3 | 2 | 4 | 2 | 3 |
| Journeys action-attempt journal | 4 | 2 | 5 | 3 | 2 |
| Learned-workflows compiled registry | 3 | 4 | 2 | 3 | 4 |

The EventKit ledger is the right read-back for reminders and events, and it correctly refuses a guessed start. Its idempotency key is skill plus title plus minute. That key is a second identity. Two intentional requests with the same title and time become one write. User JSON can still replace a built-in. Status strings still carry the result. The workflow slice still trusts category confirmation.

The journeys journal is the right place in the app: restore the card, claim before the sheet, and keep an editable message draft when an explicit text is below τ. Its states are strings (`completed` covers delivery, queueing, and a URL open). It journals `AppModel`'s card. `toolPath` still calls `actions.perform` directly when the model says `act`. The same title and time still collapses two requests. Learned JSON still uses the category rule the parent rejected.

The compiled registry is the right authority: effect, confirmation floor, compensation, and satisfying evidence live in Swift. Versions are immutable. A claim commits before the executor. It loses because the proposed deliverable is `Workflow.swift` plus twelve in-memory tests, and `Assistant.handle` keeps performing legacy effects with no ticket. `BoundStep.effect` copied from JSON-time validation can drift from the catalog. `status: String` and `ReceiptKind` stored from a status sentence leak the policy into callers. SHA-256 is an extra identity mechanism. Auto-disable after three ambiguous runs is a second policy. `$digest.when` is an executable model binding. `calendar_find` left in `started` is allowed to run again, which is safe only because it is a pure read; encoding that as a general resume of `started` teaches the wrong rule.

## Synthesis decision

Base: the learned-workflows compiled catalog and immutable approved versions.

Grafted from the journeys journal: one claim path used by `handle`'s immediate act and by the confirm card; launch recovery of `awaitingUser` cards; claimed rows with no receipt stay unresolved; an explicit below-τ message becomes an editable draft and does not execute; MessageUI and Mail results stay distinct from delivery.

Grafted from the capability map: EventKit success is an identifier plus read-back of title and instant; a missing or unparsed time writes nothing and does not become now plus one hour; Shortcut correlation is an unpredictable per-attempt token, exact and one-time; `url` acceptance is only URL acceptance; `sms:` with a body is not a filled message.

Rejected, and not available as a second API:

- A title/time primary key, or any unique constraint on title and minute.
- Wrapping `perform`'s `String` as a receipt. Permission text and handoff text are not success.
- A `WorkflowEngine` or `WorkflowRunner` that performs steps while `Assistant.execute` still can.
- User or model JSON fields `effect`, `confirm`, `permission`, `idempotent`, `compensation`, or `satisfies` as authority.
- Category confirmation as the execution rule. `Skill.confirm` remains a decode residue and is not read by the session.
- Output references such as `$digest.when`, and any model-proposed recipient, body, or date that the user has not seen.
- Nested `SQLiteDB.transaction` calls, in-memory-only acceptance, and a custom hash or a new package for identity.
- Automatic replay, automatic Shortcut reopen, automatic disable, and compensation without a new confirmation plus a fresh read-back.
- Using `Assistant.reason`, `CloudBrainChain`, built-in web search, computer use, or a tool loop as the planner.
- Treating AlarmKit, XCUITest, or a device agent as the Clock app or as shipped execution.
- The twelve in-memory tests as the completed feature.

The public surface is deep enough for this feature and no larger. Callers name a user request, a draft edit, or a saved definition. `EffectSession` hides claim, executor, classification, and receipt. Callers do not set phases, write SQL, or interpret UIKit enums. `EffectLedger` is the only SQL writer. Interface depth is that hide, not a stack of prepare/validate/save types.

## Usage

`AppModel` owns the SQLite file and constructs one ledger on the same `SQLiteDB` as `MemoryStore`. It passes that ledger and one `PhoneEffects` into `Assistant`. Views call `AppModel`. `AppModel` calls `Assistant`. `Assistant` calls `EffectSession`. `EffectSession` calls the ledger and `PhoneEffects`.

Immediate reminder, model says act. The user never sees a card. The claim still commits before EventKit.

```swift
let turn = try await assistant.handle("Remind me to submit the problem set tomorrow at 5pm")
switch turn.reply {
case .acted(let effect):
    // effect.phase is .settled(.committed(.eventKitItem(...))) only after read-back.
    // effect.summary names the title, the resolved instant, and the identifier.
    show(effect.summary)
case .needsConfirmation(let card):
    // Unparsed time, missing title, or the model asked to confirm.
    show(card)
default:
    show(turn)
}
```

Low-confidence explicit message. `handle` returns a card. Nothing is sent. Confirm sends the edited fields through the same session.

```swift
let turn = try await assistant.handle("Text Mom I'll be home by 8")
guard case .needsConfirmation(let card) = turn.reply else { return }
// card.notice says the model was not confident.
// card.canConfirm is false while the contact query matches zero or several people.

let edits = [
    DraftEdit(field: "contact", value: .contactID(chosenIdentifier)),
    DraftEdit(field: "body", value: .text("I'll be home by 8"))
]
let result = await assistant.confirmEffect(card.attemptID, edits: edits)
```

Launch. Read-only recovery. No sheet, no save, no URL.

```swift
let recovery = try assistant.recoverEffects()
for card in recovery.showAgain { chat.restore(card) }
for open in recovery.unresolved { chat.warn(open.summary) }
```

Slice 2, after the types below exist. Exact trigger. The 1B is not asked.

```swift
let draft = try ledger.validate(proposal)          // throws, or a DefinitionDraft
let approved = try ledger.approve(draft)           // immutable version
if let hit = try ledger.matchExact(utterance) {    // equality on SkillRegistry.norm
    let cards = try assistant.stageSaved(hit, requestID: UserRequestID())
    let result = await assistant.confirmEffect(cards[0].attemptID, edits: [])
}
```

`Assistant.stageSaved` forwards to `EffectSession.stageSaved`. The cards show every concrete argument and `CapabilityContract.reviewSentence`. Confirm is what runs the steps. Building the draft does not call `PhoneEffects`.

## Shape

### Module ownership

| Module | File | Owns |
|---|---|---|
| PocketCore | `core/Sources/PocketCore/EffectLedger.swift` | Catalog, bindings, dispositions, ledger, session, summaries, definition versions |
| PocketCore | `core/Sources/PocketCore/SQLiteDB.swift` | Add `changes() -> Int` only |
| PocketCore | `core/Sources/PocketCore/Assistant.swift` | Call the session from `toolPath`, `planSkillCore`'s act/confirm exits, and `confirm`; stop calling `perform` directly |
| PocketCore | `core/Sources/PocketCore/ActionPlanner.swift` | The explicit-message branch stages a draft instead of dropping the parse |
| App | `app/PocketGlimmer/Actions/PocketEffects.swift` | The only `PhoneEffects` |
| App | `app/PocketGlimmer/Actions/SystemActions.swift` | EventKit, Contacts, MessageUI, Mail |
| App | `app/PocketGlimmer/Actions/SkillRunner.swift` | URL open, Shortcut open, autoreply memory write |
| App | `app/PocketGlimmer/AppModel.swift` | Construct the ledger; project cards; pass edits |
| App | `app/PocketGlimmer/Views/ChatView.swift` | Render `DraftCard` and disposition summaries |

`Skill.confirm`, `builtin.json`, and Documents skills do not own effects. `ChatItem.draft` is a projection of a ledger row. `Reply.needsConfirmation(PlannedAction, prompt:)` and `Reply.acted(String)` are removed in the same change as the session, so the old card and the new card cannot both compile.

No new package. No CryptoKit. Approved identity is `(definitionID, version)` plus the stored canonical body bytes.

### Catalog

`CapabilityCatalog.current(id:)` is the highest version. `contract(id:version:)` returns that historical value. Old values stay in the array and are not mutated. Approval stores `current.version`. A run looks up the stored version. An unknown version pauses with `.contractVersionStale` and performs nothing.

Confirmation floor is the only execution gate besides binding:

- `always`: the model cannot choose `act`. The card is required. Compiled for `imessage_send`, `instagram_dm`, `x_dm`, `whatsapp_send`, `email_compose`, `instagram_autoreply`, `call`, `facetime`, `uber_ride`, and every user-authored handoff.
- `modelMayAct`: `confirmBeforeAct` may still ask. It cannot clear `always`. Compiled for reminders, events, the existing Shortcut skills, Maps, web, music, Spotify, Apple TV, Photos, `open_url`, `run_shortcut`, and `create_shortcut`.

`appletv_play` stays `modelMayAct` on the single-step path so the frozen chooser still behaves as it does today. A saved workflow still shows `reviewSentence` before any step runs. That is definition approval, not a second flag.

```swift
public enum EffectClass: Sendable, Equatable {
    case localWrite
    case personOrMoneyHandoff
    case externalHandoff
}

public enum ConfirmationFloor: Sendable, Equatable { case modelMayAct, always }

public enum HandoffWait: Sendable, Equatable {
    case openResultIsFinal
    case waitForCallback
}

public enum CompensationKind: Sendable, Equatable {
    case deleteEventKitItem
    case forgetMemoryFact
}

public struct CapabilityContract: Sendable, Equatable {
    public var id: String
    public var version: Int
    public var effect: EffectClass
    public var confirmation: ConfirmationFloor
    public var compensation: CompensationKind?
    public var wait: HandoffWait
    public var reviewSentence: String
    public var availability: Availability
}

public enum Availability: Sendable, Equatable { case ready, notWired }

public enum ResolvedCapability: Sendable, Equatable {
    case compiled(CapabilityContract)
    case userHandoff(CapabilityContract) // floor always, effect externalHandoff, compensation nil
    case replyOnly
    case rejected(RejectedCapability)
}

public enum RejectedCapability: Sendable, Equatable {
    case unknownNativeHandler(String)
    case cloudStepRequiresPrivacyRepair
    case unknown(String)
}
```

Slice 1 sets every handoff's `wait` to `openResultIsFinal`. Slice 3 changes Shortcut-backed ids to `waitForCallback` by appending a new version. In-flight approvals keep the version they stored.

Reply-only ids, never claimed and never a workflow step in this contract: `email_digest`, `analyze_document`, `translate`, `summarize_text`, `html_viz`, `device_status`, `calendar_find`, `memory_recall`. The first four can reach `Assistant.reason`. They stay on today's reply path until the privacy repair. A workflow proposal that names them fails validation with `cloudStepRequiresPrivacyRepair` for the four cloud-capable ids, and `replyOnly` is simply not a step.

`alarmkit_schedule` is a compiled id at version 1 with `availability: .notWired`, effect `localWrite`, compensation nil, review sentence stating it is this app's alarm and is not wired. `prepare` returns `.failed(.unavailable)` and does not run `alarm_create`. `alarm_create` remains the Clock Shortcut handoff.

A test lists every `BuiltinSkills.all` id exactly once as compiled, user-handoff-eligible, reply-only, or `alarmkit_schedule`. A missing id fails that test.

### Bindings

```swift
public struct UserRequestID: Hashable, Sendable {
    public let raw: UUID
    public init() { raw = UUID() }
    public init(raw: UUID) { self.raw = raw }
}

public struct AttemptID: Hashable, Sendable {
    public let raw: UUID
    public init() { raw = UUID() }
    public init(raw: UUID) { self.raw = raw }
}

public struct ContactCandidate: Sendable, Equatable, Codable {
    public var identifier: String
    public var displayName: String
    public var detail: String
}

public struct ContactBinding: Sendable, Equatable, Codable {
    public var identifier: String
    public var displayName: String
    // Phone and email are resolved at perform time from Contacts.
    // They are absent from approved definition bytes and from receipts.
}

public struct ContactLookup: Sendable, Equatable {
    public var access: AccessLevel
    public var matches: [ContactCandidate]
}

public enum AccessLevel: Sendable, Equatable {
    case full, writeOnly, limited, denied, restricted, notDetermined
}

public enum InstantParse: Sendable, Equatable {
    case missing
    case parsed(Date)
    case unparsed(String)
}

public enum BoundArgument: Sendable, Equatable {
    case text(String)
    case contact(ContactBinding)
    case instant(Date)
    case place(String)
    case url(URL)
    case shortcutName(String)
}

public struct BoundAction: Sendable, Equatable {
    public var capabilityID: String
    public var contractVersion: Int
    public var arguments: [String: BoundArgument]
    public var source: ArgumentSource
}

public enum ArgumentSource: Sendable, Equatable {
    case userUtterance
    case userEdited
    case approvedDefinition
    case modelProposal
}

public struct DraftCard: Sendable, Equatable {
    public var attemptID: AttemptID
    public var requestID: UserRequestID
    public var capabilityID: String
    public var contractVersion: Int
    public var title: String
    public var fields: [DraftField]
    public var notice: String
    public var reviewSentence: String
    public var duplicateHint: DuplicateHint?
    public var canConfirm: Bool
}

public struct DraftField: Sendable, Equatable {
    public var name: String
    public var kind: DraftFieldKind
    public var value: String
    public var choices: [ContactCandidate]
}

public enum DraftFieldKind: Sendable, Equatable { case text, contact, instant, place }

public struct DraftEdit: Sendable, Equatable {
    public var field: String
    public var value: DraftEditValue
}

public enum DraftEditValue: Sendable, Equatable {
    case text(String)
    case contactID(String)
    case instant(Date)
}

public struct DuplicateHint: Sendable, Equatable {
    public var existingAttemptID: AttemptID
    public var title: String
    public var minute: Date?
    public var note: String
}
```

`modelProposal` cannot be claimed. A `$` prefix on a proposed string is an output binding and becomes `UserPause.outputBinding`. Ambiguous contacts (`matches.count != 1`) stay on the card with `canConfirm == false`. The session never selects `matches[0]`. A chosen `contactID` must be a member of that card's choices. At confirm, Contacts is resolved again by identifier. Zero or several matches pause. The displayed name on the card is the name just resolved.

A local write with `InstantParse.missing` or `.unparsed` stages a card whose time field is empty and `canConfirm == false`. `SystemActions` does not substitute `Date()`.

`DuplicateHint` is optional copy. It is not unique and it is not an attempt id. Confirm of a new `UserRequestID` still claims a new `AttemptID`.

Text arguments are at most 2,000 characters each. A definition body is at most 16,000 bytes. Names `authorization`, `apiKey`, `api_key`, `token`, `password`, `bearer`, and `secret` are rejected at validate. The Keychain is not read by the ledger.

### Outcomes

The adapter returns this. It does not return a status sentence.

```swift
public struct EffectReport: Sendable, Equatable {
    public var boundary: EffectBoundary
    public init(boundary: EffectBoundary) { self.boundary = boundary }
}

public enum EffectBoundary: Sendable, Equatable {
    case notStarted(NotStartedReason)
    case startedUnverified(UnverifiedReason)
    case observed(ObservedOutcome)
}

public enum NotStartedReason: Sendable, Equatable {
    case permission(StoreKind, AccessLevel)
    case sheetUnavailable(SheetKind)
    case missingContactMethod
    case bindingRejected
    case unsupportedOnThisOS
}

public enum StoreKind: Sendable, Equatable { case reminders, calendars, contacts }
public enum SheetKind: Sendable, Equatable { case messages, mail }
public enum UnverifiedReason: Sendable, Equatable {
    case eventKitSaveThrew
    case eventKitNoReadBack
    case executorThrew
    case processInterrupted
}

public enum ObservedOutcome: Sendable, Equatable {
    case eventKit(EventKitObservation)
    case memoryFact(id: String, attemptTokenFound: Bool)
    case message(MessageSheetResult)
    case mail(MailSheetResult)
    case url(URLOpenObservation)
}

public struct EventKitObservation: Sendable, Equatable {
    public var identifier: String
    public var title: String
    public var instant: Date?
    public var attemptTokenFound: Bool
}

public enum MessageSheetResult: Sendable, Equatable {
    case acceptedOrQueued   // MessageComposeResult.sent: queued or sent
    case cancelled
    case failed
}

public enum MailSheetResult: Sendable, Equatable {
    case queuedInOutbox     // MFMailComposeResult.sent
    case savedDraft
    case cancelled
    case failed
}

public enum URLOpenObservation: Sendable, Equatable { case systemAccepted, systemRefused }
```

`PhoneEffects.perform` does not throw for a denied permission, a missing sheet, a refused URL, or an EventKit error. Those are reports. An unexpected throw is caught by `EffectSession` and recorded as `startedUnverified(.executorThrew)`.

### Disposition

```swift
public enum AttemptPhase: Sendable, Equatable {
    case awaitingUser(UserPause?)
    case claimed
    case settled(Disposition)
    case ambiguous(AmbiguousReason)
}

public enum Disposition: Sendable, Equatable {
    case committed(CommittedEffect)
    case sheet(SheetObservation)
    case handedOff(HandoffRecord)
    case cancelled(CancelKind)
    case failed(FailureKind)
}

public enum CommittedEffect: Sendable, Equatable {
    case eventKitItem(id: String, title: String, instant: Date?)
    case memoryFact(id: String)
    case deletedEventKitItem(id: String)
    case forgotMemoryFact(id: String)
    case alarmKit(id: String)
}

public enum SheetObservation: Sendable, Equatable {
    case messagesQueuedOrSent
    case mailQueuedInOutbox
    case mailDraftSaved
}

public enum HandoffRecord: Sendable, Equatable {
    case systemAcceptedURL
    case shortcutTextUnverified(String)
}

public enum CancelKind: Sendable, Equatable { case userCard, messageSheet, mailSheet }

public enum FailureKind: Sendable, Equatable {
    case permission(StoreKind, AccessLevel)
    case sheetUnavailable(SheetKind)
    case urlRefused
    case messageSheetFailed
    case mailSheetFailed
    case missingContactMethod
    case objectChanged
    case unavailable
}

public enum AmbiguousReason: Sendable, Equatable {
    case claimedWithoutReceipt
    case saveUnverified
    case shortcutMayHavePartialEffects
    case callbackTimeout
}

public enum UserPause: Sendable, Equatable {
    case needsTime
    case needsContactChoice
    case needsField(String)
    case contractVersionStale
    case privacyRepairRequired
    case outputBinding
}

public struct EffectResult: Sendable, Equatable {
    public var attemptID: AttemptID
    public var phase: AttemptPhase
    public var summary: String
}

public enum Reply: Sendable, Equatable {
    case local(String)
    case cloud(String, provider: String)
    case acted(EffectResult)
    case needsConfirmation(DraftCard)
    case clarify(String)
    case offlineFallback(String)
}
```

`Disposition.classify(contract:report:)` is the only classifier. Rules:

- `notStarted(.permission)` → settled `.failed(.permission)`. Zero saves.
- `notStarted(.sheetUnavailable)` → settled `.failed(.sheetUnavailable)`. The same attempt does not open `sms:`, `mailto:`, or a Shortcut.
- `notStarted(.missingContactMethod)` → settled `.failed(.missingContactMethod)`.
- `startedUnverified` → phase `.ambiguous(.saveUnverified)`. Zero further writes.
- EventKit observation with a non-empty identifier, `attemptTokenFound == true`, and title equal to the bound title → settled `.committed(.eventKitItem)`. Instant, when the bound action has one, must match to the minute. Otherwise `.ambiguous(.saveUnverified)`.
- Memory observation with `attemptTokenFound` → `.committed(.memoryFact)`. Otherwise ambiguous.
- `.message(.acceptedOrQueued)` → `.sheet(.messagesQueuedOrSent)`. This is not `.committed`. The summary says delivery is not confirmed.
- `.message(.cancelled)` → `.cancelled(.messageSheet)`.
- `.message(.failed)` → `.failed(.messageSheetFailed)`.
- `.mail(.queuedInOutbox)` → `.sheet(.mailQueuedInOutbox)`. The summary names the Outbox.
- `.mail(.savedDraft)` → `.sheet(.mailDraftSaved)`. The summary says it was not sent. A draft does not satisfy a step whose review sentence promised a queued message; the run picture stays `partial`.
- `.mail(.cancelled)` → `.cancelled(.mailSheet)`.
- `.mail(.failed)` → `.failed(.mailSheetFailed)`.
- `.url(.systemRefused)` → `.failed(.urlRefused)`.
- `.url(.systemAccepted)` when `wait == .openResultIsFinal` → `.handedOff(.systemAcceptedURL)`.
- `.url(.systemAccepted)` when `wait == .waitForCallback` → phase stays `.claimed`. Open is noted. No success disposition yet.
- A report is never promoted because its summary text contains "sent", "set", or "opened".

`userSummary` lives next to `classify`. Required sentences:

- Messages accepted: `Messages accepted or queued the message to NAME. Delivery is not confirmed.`
- Messages cancelled: `You cancelled the Messages sheet. This attempt did not accept a send.`
- Mail queued: `Mail queued the message to NAME in the Outbox. Delivery is not confirmed.`
- Mail draft: `Mail saved a draft to NAME. It was not sent.`
- URL: `The system accepted a link for TITLE. That does not show what happened in the other app.`
- Shortcut, open final: `Shortcuts was asked to open NAME. This app did not see what the Shortcut did.`
- Ambiguous message: `A message to NAME may already be in Messages. This attempt will not open the sheet again.`
- Ambiguous write: `A reminder or event for this attempt may already exist. This attempt will not write again.`
- Reminders denied: `Reminders access is off. Nothing was saved.`
- Calendars denied: `Calendars access is off. Nothing was saved.`
- Write-only: `Calendar access cannot read this item back. It was not recorded as saved.`

Chat bubbles use `userSummary` only.

### Session and ledger

```swift
public protocol PhoneEffects: Sendable {
    func resolveContacts(_ query: String) async -> ContactLookup
    func contact(identifier: String) async -> ContactLookup
    func resolveInstant(_ phrase: String) -> InstantParse
    func storeAccess(_ store: StoreKind) -> AccessLevel
    func perform(_ action: BoundAction, ticket: ClaimTicket) async -> EffectReport
    func readBack(attemptID: AttemptID, capabilityID: String) async -> EffectReport
}

public struct ClaimTicket: Hashable, Sendable {
    public let attemptID: AttemptID
    public let requestID: UserRequestID
    public let capabilityID: String
    public let contractVersion: Int
    internal init(attemptID: AttemptID, requestID: UserRequestID, capabilityID: String, contractVersion: Int)
}

public struct LaunchRecovery: Sendable, Equatable {
    public var showAgain: [DraftCard]
    public var unresolved: [UnresolvedAttempt]
}

public struct UnresolvedAttempt: Sendable, Equatable {
    public var attemptID: AttemptID
    public var capabilityID: String
    public var summary: String
}

public enum UnresolvedChoice: Sendable, Equatable {
    case leaveUnresolved
    case startNewRequest
}

public enum SessionResult: Sendable, Equatable {
    case staged(DraftCard)
    case finished(EffectResult)
    case ignoredTerminal(EffectResult)
}

public enum EffectSession {
    public static func evaluate(
        ledger: EffectLedger,
        effects: PhoneEffects,
        requestID: UserRequestID,
        capability: ResolvedCapability,
        raw: PlannedAction,
        modelAskedConfirm: Bool,
        explicitDraft: Bool
    ) async -> SessionResult

    public static func confirm(
        ledger: EffectLedger,
        effects: PhoneEffects,
        attemptID: AttemptID,
        edits: [DraftEdit]
    ) async -> SessionResult

    public static func cancel(ledger: EffectLedger, attemptID: AttemptID) throws

    public static func resolveClaimed(
        ledger: EffectLedger,
        attemptID: AttemptID,
        choice: UnresolvedChoice
    ) throws -> SessionResult

    public static func attachVerifiedReadBack(
        ledger: EffectLedger,
        effects: PhoneEffects,
        attemptID: AttemptID
    ) async -> SessionResult

    public static func stageSaved(
        ledger: EffectLedger,
        definition: ApprovedDefinition,
        requestID: UserRequestID
    ) throws -> [DraftCard]
}
```

`evaluate` binds arguments, then:

1. Reply-only and rejected capabilities return a clarify or the existing reply path and insert no row.
2. `availability == .notWired` settles nothing externally and returns a failed unavailable result without a Shortcut substitution.
3. Unresolved time, ambiguous or missing contact, `modelProposal`, or an output binding inserts `awaitingUser` and returns `.staged`. `perform` is not called.
4. `confirmation == .always`, or `modelAskedConfirm`, or `explicitDraft`, inserts `awaitingUser` and returns `.staged`. `explicitDraft` sets `notice` to say the model was below τ and the user is confirming a draft. `confirmBeforeAct` is not called again to promote it.
5. Otherwise `claim` commits, then `perform`, then `record`.

`confirm` loads `awaitingUser` only. It applies edits, re-resolves the contact identifier and the instant, and returns `.staged` if `canConfirm` is still false. A ready card is claimed and performed. `claim` on a row that is already `claimed`, `settled`, or `ambiguous` returns `.ignoredTerminal` and does not call `perform`.

`cancel` is legal only from `awaitingUser`. It settles `.cancelled(.userCard)`.

`resolveClaimed(.leaveUnresolved)` moves `claimed` to `ambiguous(.claimedWithoutReceipt)`. `.startNewRequest` does that and inserts a new `awaitingUser` row with a new `AttemptID` and a new `UserRequestID`. It does not perform.

`attachVerifiedReadBack` is a read. If `readBack` returns a matching observation and the phase is still `claimed`, `record` stores the committed receipt. If the read finds nothing, the phase stays `claimed`. It never calls `perform`.

`Assistant.handle` creates one `UserRequestID` per utterance. `toolPath` and `planSkillCore` both call `evaluate` for effect capabilities. Reply-only reads (`search_memory`, `calendar_find`, `device_status`, charts, and the cloud-capable skills still on the old path) return `.local(String)` with today's wording. `.acted` is only an `EffectResult` from the ledger. The direct `actions.perform` branch in `toolPath` is deleted.

`Assistant` maps `SessionResult` in one place: `.staged` becomes `.needsConfirmation`, and `.finished` or `.ignoredTerminal` becomes `.acted`.

`Assistant` holds `ledger` and `effects`. Its public methods `recoverEffects`, `confirmEffect`, `cancelEffect`, `resolveUnresolvedEffect`, `attachReadBack`, and `stageSaved` pass those dependencies into `EffectSession`. They do not switch on capability id. `AppModel.confirm` calls `confirmEffect` and renders `SessionResult`. It does not clear a card and then ignore a throw. The bubble shows `summary`.

An active `awaitingUser` draft is cancelled when `send` receives an utterance that is not an exact display name of one offered contact choice. Field edits go through `DraftEdit` on the card. The utterance `yes` is not special and does not execute the draft.

### Definitions

```swift
public struct ProposedStep: Codable, Sendable, Equatable {
    public var capabilityID: String
    public var arguments: [String: String]
}

public struct WorkflowProposal: Codable, Sendable, Equatable {
    public var title: String
    public var trigger: String
    public var steps: [ProposedStep]
}

public struct DefinitionDraft: Sendable, Equatable {
    public var id: String
    public var version: Int
    public var title: String
    public var triggerNorm: String
    public var steps: [BoundAction]
    public var canonicalBody: Data
}

public struct ApprovedDefinition: Sendable, Equatable {
    public var id: String
    public var version: Int
    public var title: String
    public var triggerNorm: String
    public var canonicalBody: Data
}

public enum DefinitionPhase: Sendable, Equatable { case draft, approved, disabled }

public enum DefinitionError: Error, Equatable {
    case empty
    case tooLong
    case unknownCapability(String)
    case rejected(RejectedCapability)
    case unresolved(UserPause)
    case credentialKey(String)
    case immutable(id: String, version: Int)
    case notApproved
}

extension EffectLedger {
    public func validate(_ proposal: WorkflowProposal) throws -> DefinitionDraft
    public func approve(_ draft: DefinitionDraft) throws -> ApprovedDefinition
    public func disable(id: String, version: Int) throws
    public func matchExact(_ utterance: String) throws -> ApprovedDefinition?
    public func definition(id: String, version: Int) throws -> ApprovedDefinition?
}
```

`validate` decodes only `title`, `trigger`, and `steps[].capabilityID` plus string arguments. Extra keys are dropped. A compiled id forces the catalog contract even when the dropped key said `effect: read` or `confirm: false`. A new id is `userHandoff` only for a URL or Shortcut template the user file already stored; a new native handler is `unknownNativeHandler`. Steps: 1 through 8. Each local-write date is a resolved instant the draft displays. Each person argument is a `ContactBinding` the user already picked. `approve` inserts a new version. Updating an approved `canonicalBody` throws `immutable`. `disable` changes phase only. Canonical bytes are JSON with sorted keys, compact encoding, step order preserved, and no effect or confirm fields. Equality is `Data` equality of that body.

`matchExact` compares `SkillRegistry.norm(utterance)` to `triggerNorm`. There is no fuzzy execute and no scored "did you mean". The user can also start a definition by id from a saved-items control. That path uses the id, not a text score.

`stageSaved` inserts one `awaitingUser` row per step under one fresh `UserRequestID`, in order, with `source: .approvedDefinition`. It does not perform. `confirmEffect` on the first step claims and performs it, then the next `awaitingUser` step. A `failed`, `cancelled`, or `ambiguous` step leaves later steps `awaitingUser` and the session stops. Later steps are not performed. The run picture is the pure fold `RunPicture.fold([AttemptRecord])` over that `requestID`. There is no second status column.

```swift
public enum RunPicture: Sendable, Equatable {
    case awaitingConfirm
    case inProgress
    case paused(UserPause)
    case completed
    case partial
    case cancelled
    case failed
    case ambiguous
}
```

`completed` means every step is settled inside its own contract: a local write is `committed`; Messages accepted-or-queued and Mail queued are `sheet`; a URL open is `handedOff`. A saved Mail draft leaves the picture `partial`. `completed` is not delivery, playback, or a Clock alarm. `stageSaved` returns every step card and performs nothing. `confirmEffect` on the first card is what runs that step.

### Callback values

Slice 3 uses these. Slice 1 creates the nullable column and does not register a scheme.

```swift
public struct CallbackClaim: Sendable, Equatable {
    public var token: String
    public var kind: CallbackKind
    public var text: String?
}

public enum CallbackKind: Sendable, Equatable { case successText, cancel, error }

public enum CallbackDecision: Sendable, Equatable {
    case recorded(AttemptID, AttemptPhase)
    case ignored(CallbackIgnore)
}

public enum CallbackIgnore: Sendable, Equatable {
    case unknownToken, alreadyConsumed, attemptNotWaiting, malformed
}

extension EffectSession {
    public static func consumeCallback(ledger: EffectLedger, claim: CallbackClaim) throws -> CallbackDecision
    public static func expireWaitingCallback(ledger: EffectLedger, attemptID: AttemptID, now: Date) throws -> SessionResult
}
```

The token is `UUID().uuidString`, created inside the claim transaction, stored on that attempt, and placed by the app on `x-success`, `x-cancel`, and `x-error`. Match is exact string equality. `consumeCallback` is one transaction: unknown, mismatched, or already consumed tokens return `ignored` and write nothing. The first match sets consumed and records the phase. A second delivery of the same token is ignored.

`successText` becomes `.handedOff(.shortcutTextUnverified(text))`. The summary quotes the text and says it is unauthenticated Shortcut output, not playback or delivery. `cancel` and `error` become `.ambiguous(.shortcutMayHavePartialEffects)`. `expireWaitingCallback` becomes `.ambiguous(.callbackTimeout)`. None of the three opens the Shortcut again.

Scheme, registered in slice 3 only: `pocketglimmer`.

- `pocketglimmer://shortcut/success?token=UUID`
- `pocketglimmer://shortcut/cancel?token=UUID`
- `pocketglimmer://shortcut/error?token=UUID`

Shortcuts may append `result` or `errorMessage`. The custom scheme does not authenticate the sender. The token is an id, not a credential. No message body, key, or phone number is added to the callback URL.

### Screened planner

Not constructed in slices 1–3. Signature reserved so slice 4 cannot invent another:

```swift
public struct ScreenedPrompt: Sendable {
    internal let text: String
    internal let screeningRevision: String
    internal init(unsafeTestFixture text: String) {
        self.text = text
        self.screeningRevision = "test-only"
    }
}

public protocol WorkflowProposing: Sendable {
    func propose(_ prompt: ScreenedPrompt) async throws -> WorkflowProposal
}
```

There is no public initializer. `unsafeTestFixture` is internal and is not a production screen. The privacy repair owns the future constructor, shaped as `screenForPlanner(_:) async -> ScreenedPrompt?`, returning nil when the call must not happen. This contract does not add that function and does not treat `Assistant.reason` or category checks as a substitute.

When that constructor exists, the proposer posts `POST https://api.meta.ai/v1/chat/completions` for model id `muse-spark-1.3` only, with `response_format.type = json_schema` and `response_format.json_schema` (`name`, `schema`, and structured-output `strict: true` on that json_schema object). The schema is a flat object: `title`, `trigger`, `steps[]` of `capabilityID` and string `arguments`. `additionalProperties` is false. The request omits `tools`, so `tools[].function.strict` is not sent. It omits built-in web search and computer use. It does not use `CloudBrainChain`, Responses `text.format`, or `store: true`. Prose, tool calls, unknown ids, and failed local `validate` produce no approved row. The bearer token stays in the request header the app already builds for chat completions. It is not written to the proposal, the definition, or the receipt.

## State

```
awaitingUser --cancel--> settled(cancelled)          terminal, no effect
awaitingUser --confirm--> claimed                    transaction committed first
claimed --report--> settled(disposition)             terminal for this attempt id
claimed --throw, kill, timeout, callback cancel/error--> ambiguous
                                                      terminal, no replay
ambiguous --user starts again--> new attempt id      old row stays ambiguous
```

A settled or ambiguous attempt never returns to `claimed`. Compensation is a new attempt. Reads are not attempts.

```
definition draft --approve--> approved version N     body insert-only
approved N --edit--> draft version N+1                N remains
approved N --user disables--> disabled                body unchanged
```

No automatic disable.

## Write ownership

| State | Writer | Everyone else |
|---|---|---|
| `action_attempts`, `workflow_definitions` | `EffectLedger` | Reads or calls a method |
| Attempt phase transitions | `EffectSession` | Does not set phase |
| Definition bytes | `validate` / `approve` / `disable` | JSON files do not update an approved version |
| EventKit / MessageUI / URLs | `PhoneEffects.perform` after a `ClaimTicket` | No ticket, no call |
| Chat cards | Projection of `recover` and `SessionResult` | Not restored as the source of truth |
| Effect policy | `CapabilityCatalog` | Skill JSON cannot change it |

`MemoryStore` and `EffectLedger` share one `SQLiteDB`. Neither calls the other inside `transaction`. The memory write for `instagram_autoreply` happens in `perform`, after `claim` has committed and released the lock.

## SQLite

`SQLiteDB.changes()` returns `sqlite3_changes` and may lock recursively. Call it immediately after the claim `UPDATE`, before another statement.

```sql
CREATE TABLE action_attempts (
  attempt_id TEXT PRIMARY KEY,
  request_id TEXT NOT NULL,
  step_index INTEGER NOT NULL DEFAULT 0,
  definition_id TEXT,
  definition_version INTEGER,
  capability_id TEXT NOT NULL,
  contract_version INTEGER NOT NULL,
  phase TEXT NOT NULL,
  pause TEXT,
  disposition TEXT,
  args_json TEXT NOT NULL,
  normalized_title TEXT,
  minute_epoch INTEGER,
  callback_token TEXT,
  callback_consumed INTEGER NOT NULL DEFAULT 0,
  handoff_opened INTEGER NOT NULL DEFAULT 0,
  receipt_json TEXT,
  created REAL NOT NULL,
  updated REAL NOT NULL
);
CREATE UNIQUE INDEX action_attempts_callback
  ON action_attempts(callback_token) WHERE callback_token IS NOT NULL;

CREATE TABLE workflow_definitions (
  definition_id TEXT NOT NULL,
  version INTEGER NOT NULL,
  phase TEXT NOT NULL,
  title TEXT NOT NULL,
  trigger_norm TEXT NOT NULL,
  body_json TEXT NOT NULL,
  created REAL NOT NULL,
  PRIMARY KEY (definition_id, version)
);
```

Phase text is private storage. A row that does not decode to `AttemptPhase` is surfaced as `ambiguous(.claimedWithoutReceipt)`, never as success. `normalized_title` and `minute_epoch` are not unique.

Claim, inside one `db.transaction`, using `run` / `query` / `changes` only:

```sql
UPDATE action_attempts
SET phase = 'claimed', updated = ?
WHERE attempt_id = ? AND phase = 'awaitingUser';
```

`changes() == 1` yields a `ClaimTicket`. Any other count loads the current row and returns it as terminal. The executor runs after that transaction returns.

Record is a second transaction. Crash between them leaves `claimed`. `recover` only reads. It does not perform and it does not mark ambiguous by itself.

EventKit order: commit the claim; save an item whose notes contain `pg-attempt:<attemptID>`; fetch by `calendarItemIdentifier`; accept the receipt only when the title, the minute, and the token match. Write-only access cannot fetch: report `eventKitNoReadBack`. A throw from `save` is `eventKitSaveThrew`. Resume may call `attachVerifiedReadBack`, which searches notes and does not save.

File-backed tests drop every reference to the first `SQLiteDB`, then open the same path. `:memory:` does not count as reopen. Concurrent confirm starts two threads on one ledger and one `awaitingUser` row; exactly one `ClaimTicket` is issued and the fake `perform` count is one. The crash-gap test claims, discards the process image by skipping `record`, reopens, and asserts `perform` is still zero.

`transaction` is not called from inside `transaction`. The body does not `await`.

## App adapter mapping

`PocketEffects.perform` switches on `capabilityID` from the ticket. It ignores `Skill.invocation` when the catalog has that id.

Contacts: `CNAuthorizationStatus` maps to `AccessLevel`. `.limited` returns only the visible matches. The copy says the list is the set this app can see. Denied and restricted perform nothing.

Reminders and calendars: check `EKAuthorizationStatus` before save. Denied and restricted return `notStarted(.permission)`. Full access saves, then fetches. The fetch compares title and `pg-attempt` token.

Messages: `MFMessageComposeViewController.canSendText()` false, or no presenter, returns `sheetUnavailable(.messages)`. There is no `sms:&body=` call and no Shortcut call inside this attempt. The delegate maps `.sent` to `acceptedOrQueued`, `.cancelled` to `cancelled`, and `.failed` to `failed`.

Mail: `canSendMail()` false returns `sheetUnavailable(.mail)`. There is no `mailto:` fallback inside the attempt. `.sent` → `queuedInOutbox`, `.saved` → `savedDraft`, `.cancelled` → `cancelled`, `.failed` → `failed`.

URL skills: `UIApplication.shared.open`'s `Bool` maps to `systemAccepted` or `systemRefused`. Clipboard copy for Instagram remains a local side effect described in the summary. It is not a sent DM.

Shortcut skills, slice 1: build today's `shortcuts://run-shortcut` URL. Open true with `openResultIsFinal` is `handedOff`. Open false is `urlRefused`. Slice 3 builds `shortcuts://x-callback-url/run-shortcut` with the tokenized callbacks and leaves the attempt `claimed` after open true.

`instagram_autoreply` upserts a memory fact whose text contains `pg-attempt:<attemptID>`, then returns that fact id. It does not send a message.

A user who needs the Shortcut after Messages is unavailable confirms a new request. That is a new attempt.

## Compatibility

Documents `Skills/*.json` still merges into `SkillRegistry` for retrieval text. Execution asks `CapabilityCatalog` first. A file that replaces `imessage_send` with a URL and `"confirm": false` still presents MessageUI after a card. A file that adds a new URL or Shortcut id runs as `userHandoff` with `always` and `systemAcceptedURL` evidence only. A file that adds `native("send_message")` under a new id is rejected at execution.

Single-step `modelMayAct` skills still follow `confirmBeforeAct` when the binding is complete. That includes a parsed reminder time the user spoke. The new behavior on that path is the claim, the read-back, and the refusal to invent a time. Person, money, and explicit low-confidence message drafts always show a card.

Old presets do not get a second confirmation policy. `Skill.init`'s category force stays so old JSON still decodes. `EffectSession` does not read it.

The GGUF, `defaultTau`, priors, prompt templates, and gold files are untouched. Exact trigger match happens before `handle` only in slice 2, and only for an approved definition. A miss falls through to today's `handle`.

## Slices

### Slice 1, first working app slice

Land the catalog, ledger, session, `PhoneEffects`, and the `Assistant` / `AppModel` / `ChatView` call sites together. A core-only commit is not this slice.

Accomplished when tests and the wired call sites show:

- A model `act` on `create_reminder` or `create_event` claims a file-backed row before the fake or real save, stores the identifier only after read-back, and does not save when the time does not parse.
- The same title and minute produces a hint and still allows a second `UserRequestID`.
- `handle` below τ for an explicit message with a parsed recipient and body returns `needsConfirmation` and calls `perform` zero times. Two contacts named Sam cannot confirm until one identifier is chosen. Confirm re-resolves that identifier.
- Messages and Mail map to `accepted` or `failed` or `cancelled`, including sheet unavailable, with no `sms:` or `mailto:` inside the attempt.
- URL open true is `handedOff`. A permission report is `failed` and the save count is zero.
- Relaunch shows `awaitingUser` cards. A claimed row with no receipt is unresolved, and `perform` is not called again.
- Two concurrent confirms produce one `perform`.
- `AppModel.confirm` surfaces `userSummary` when the adapter returns a failure report.

Still unfinished after slice 1: saved multi-step definitions, exact triggers, the URL scheme, Muse, AlarmKit, compensation, voice, and the morning-brief model split.

### Slice 2, reviewed definitions

Implement `validate`, `approve`, `disable`, `matchExact`, and `stageSaved`. App UI lists saved definitions and shows `reviewSentence` plus concrete arguments. Tests: effect key ignored, unknown id rejected, output binding paused, approved body immutable, exact trigger does not fire on a nearby sentence, `approve` performs zero effects, a running request keeps its stored contract version.

### Slice 3, Shortcut callbacks

`app/project.yml` gains the `pocketglimmer` URL type. `PocketGlimmerApp` handles the URL and calls `consumeCallback`. Shortcut capabilities bump to `waitForCallback`. Tests use parsed URL values, not a device: matching token records once; unknown, duplicate, and malformed tokens write nothing; error and cancel become ambiguous; timeout does not set `handoff_opened` again.

### Slice 4, Muse proposal

Blocked until the privacy repair ships a real `ScreenedPrompt` constructor and the two regressions pass. Then add `MetaStructuredProposer` in PocketCore, Standard mode only, schema above, local `validate`, user approval before `approve`. No tool loop.

### Slice 5, AlarmKit

Append `alarmkit_schedule` version 2 with `availability: .ready` behind `if #available(iOS 26, *)`. Add `NSAlarmKitUsageDescription` in `app/project.yml`. Authorization denial is `notStarted(.permission)`. Success is `committed(.alarmKit(id:))` from `AlarmManager`, followed by a list query that contains that id. Cancel removes that id. Denied authorization does not run `alarm_create` unless the user confirms that Shortcut as a new request. Focus and silent-mode behavior stay device-unverified. The deployment target stays iOS 18.

### Slice 6, compensation

`prepareCompensation` offers `deleteEventKitItem` or `forgetMemoryFact` only for a `committed` receipt of that kind. The user confirms a new attempt. `perform` reads the object again. Title, minute, and attempt token must match. A mismatch returns `objectChanged` and does not delete. Messages, Mail, URLs, Shortcuts, rides, and alarms have no compensation offer.

## Acceptance gates

Linux `swift test` for PocketCore, file-backed where noted:

1. `testFileReopenRestoresAwaitingCard`
2. `testConcurrentConfirmPerformsOnce`
3. `testClaimWithoutReceiptReopensUnresolved`
4. `testModelActClaimsBeforeEventSave`
5. `testUnparsedEventDoesNotSaveOrInventTime`
6. `testSameTitleIsHintAndSecondRequestClaims`
7. `testPermissionReportIsFailedAndSaveCountStaysZero`
8. `testMessageAcceptedIsNotCommittedDelivery`
9. `testMailQueuedIsNotDeliveryAndDraftIsNotSent`
10. `testUrlAcceptedDoesNotSatisfySend`
11. `testExplicitMessageDraftPerformsZeroTimes`
12. `testAmbiguousContactDoesNotBindFirst`
13. `testUserJSONCannotDowngradeIMessage`
14. `testStartedHandoffIsNotReplayed`

Slice 2 adds `testModelEffectKeyDropped`, `testOutputBindingPauses`, `testApprovedBodyImmutable`, `testExactTriggerDoesNotFuzzyExecute`, `testApproveDoesNotPerform`.

Slice 3 adds `testCallbackTokenOneTime`, `testUnknownCallbackIgnored`, `testCallbackErrorStaysAmbiguous`.

Slice 4 adds `testSensitiveFixtureDoesNotCallTransport` using `unsafeTestFixture` only as a negative control that the proposer is not invoked when the screen returns nil. It does not call Meta.

Slice 6 adds `testCompensationStopsWhenObjectChanged`.

Update `TakeoverRegressionTests` message assertions to `DraftCard` fields, and the Apple TV act assertion to one claim plus a `handedOff` summary. Do not keep `"ran: appletv_play"` as success.

Device gates stay in `docs/research/IOS27_END_TO_END_JOURNEYS.md` A1–A20. They are not run by this contract. A Simulator or XCUITest result does not close them.

## Tradeoffs accepted

- A confident, fully parsed reminder can still save without a card. The user spoke the time. The claim, the stored instant, and the read-back are the protection. A model-filled or unparsed time cannot take that path.
- `appletv_play` can still open without a card when `confirmBeforeAct` says `act`. Saved workflows show the handoff sentence first. Single-step behavior stays on the frozen chooser.
- Reply-only cloud skills stay on the unsafe `reason` path until the privacy repair. This feature does not journal them as successes and does not reroute them.
- `ambiguous` blocks that attempt forever. The user starts a new request. Some of those rows will be false alarms when EventKit `save` threw before anything was written. That is the cost of refusing a silent second write.
- Messages sheet unavailable no longer falls through to `sms:` or `PG Send Message` inside the same attempt. The user confirms any next channel.
- Historical contract structs accumulate in the catalog. Pending runs keep the rules the user saw.
- The callback token is unguessable and one-time, and it still is not proof of who called the URL.

## Alternatives considered

One larger `WorkflowEngine` with string transitions, a separate runner, and the old `perform() -> String` left in place. Callers would have to know which path journals. It hides less and leaves `handle` unprotected. It lost.

An EventKit-only ledger keyed by title and minute, with workflows as more skill JSON. The public surface is smaller, and it cannot say which receipt a message sheet produced or stop JSON from replacing `imessage_send`. It lost.

Keeping `ChatItem.pending` as the authority and writing SQLite as a log after `perform`. A kill between the effect and the log looks like nothing happened, so the next launch retries. It lost.

## Limits

No signed iOS 27.0.1 build exists for this tree. EventKit, MessageUI, Shortcuts, and AlarmKit mappings are specified from Apple's documented results and this source. They are device-unverified. `NSDataDetector` results for "Friday" and "at 8" are device-unverified and must be shown once parsed.

`MessageComposeResult.sent` means the composition was queued or sent. `MFMailComposeResult.sent` means Mail queued it in the Outbox. Neither is delivery. `UIApplication.open` true means the system accepted the URL. Shortcut `result` text is the Shortcut's text. A custom scheme does not authenticate the caller. Siri AI's third-party App Intents preview is the 27.3 beta (`https://developer.apple.com/news/?id=gdk2umrf`), not 27.0.1. Describe a Shortcut is a Shortcuts editor feature, not an API this process can read.

Screening is not a claim that every private fact is detected. The planner waits on the privacy repair. Full message bodies stay in the local attempt row. Distillation export stays on decision rows and does not gain workflow bodies.

XCUITest and agent-device are not product execution. This feature does not tap another app, read its screen, or promise recovery of Instagram, Uber, playback, Focus, or the Mail inbox.

## Next implementation step

Add `EffectLedger.swift` and the `changes()` helper, then switch `toolPath` and `planSkillCore` to `EffectSession.evaluate` with a fake `PhoneEffects` and the file-backed tests 1–14 before any SwiftUI work.
