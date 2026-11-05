import Foundation

// MARK: - Compiled capability policy
//
// Slice 1 effect path. The catalog is the only authority for confirmation, effect class, invocation,
// argument kinds and evidence. A Documents JSON skill is used only to propose text retrieval and, for a
// URL/Shortcut id that is not compiled here, a user-authored handoff. It never replaces the invocation of
// a compiled id and never lowers a confirmation floor.

public enum EffectClass: Sendable, Equatable, Codable {
    case localWrite
    case personOrMoneyHandoff
    case externalHandoff
}

public enum ConfirmationFloor: Sendable, Equatable, Codable { case modelMayAct, always }

public enum Availability: Sendable, Equatable, Codable { case ready, notWired }

public enum ContactMethodKind: String, Sendable, Equatable, Codable { case phone, email }

public struct ContactMethod: Sendable, Equatable, Codable, Hashable {
    public var kind: ContactMethodKind
    public var label: String      // localized Contacts label ("mobile", "home", "work")
    public var value: String      // exact destination: dialable phone digits or the email address (lowercased for comparison)
    public var display: String    // human text: "mobile ···1234" / "work dana@example.com"
    public init(kind: ContactMethodKind, label: String, value: String, display: String) {
        self.kind = kind; self.label = label; self.value = value; self.display = display
    }
}

public struct ContactCandidate: Sendable, Equatable, Codable {
    public var identifier: String
    public var displayName: String
    public var detail: String
    public var methods: [ContactMethod]
    public init(identifier: String, displayName: String, detail: String = "", methods: [ContactMethod] = []) {
        self.identifier = identifier; self.displayName = displayName; self.detail = detail; self.methods = methods
    }
}

public struct ContactBinding: Sendable, Equatable, Codable {
    public var identifier: String
    public var displayName: String
    /// The exact labelled destination the user picked. nil means the user has not picked a method yet.
    /// Phone and email values are resolved from Contacts at perform time and are never added to receipts.
    public var method: ContactMethod?
    public init(identifier: String, displayName: String, method: ContactMethod? = nil) {
        self.identifier = identifier; self.displayName = displayName; self.method = method
    }
}

public enum AccessLevel: Sendable, Equatable, Codable {
    case full, writeOnly, limited, denied, restricted, notDetermined
}

public struct ContactLookup: Sendable, Equatable {
    public var access: AccessLevel
    public var matches: [ContactCandidate]
    public init(access: AccessLevel, matches: [ContactCandidate]) { self.access = access; self.matches = matches }
}

public enum InstantParse: Sendable, Equatable {
    case missing
    case parsed(Date)
    case unparsed(String)
}

/// Compiled invocation. This is copied into the persisted attempt before any claim, so a later registry
/// change cannot re-resolve a mutable JSON template.
public enum ExecutorKey: Sendable, Equatable, Codable {
    case reminderCreate
    case eventCreate
    case messageSend
    case mailSend
    case urlTemplate(String)
    case shortcut(name: String, input: String)
    case autoreplyMemory
    case emailDigest
    case documentAnalysis
    case htmlVisualization
    case cloudReason
    case deviceStatus
    case calendarQuery
    case memoryRecall
    case contactLookup
    case notWired
}

public struct CapabilityContract: Sendable, Equatable, Codable {
    public var id: String
    public var version: Int
    public var title: String
    public var effect: EffectClass
    public var confirmation: ConfirmationFloor
    public var reviewSentence: String
    public var availability: Availability
    public var arguments: [ArgSpec]
    public var executor: ExecutorKey
    /// For a person handoff, the contact method kind the invocation can actually use.
    public var methodKind: ContactMethodKind?

    public init(id: String, version: Int = 1, title: String, effect: EffectClass, confirmation: ConfirmationFloor,
                reviewSentence: String, availability: Availability = .ready, arguments: [ArgSpec] = [],
                executor: ExecutorKey, methodKind: ContactMethodKind? = nil) {
        self.id = id; self.version = version; self.title = title; self.effect = effect
        self.confirmation = confirmation
        self.reviewSentence = reviewSentence; self.availability = availability; self.arguments = arguments
        self.executor = executor; self.methodKind = methodKind
    }
}

public enum ResolvedCapability: Sendable, Equatable {
    case compiled(CapabilityContract)
    case userHandoff(CapabilityContract) // floor always, effect externalHandoff, user-authored snapshot
    case replyOnly
    case rejected(RejectedCapability)
}

public enum RejectedCapability: Sendable, Equatable {
    case unknownNativeHandler(String)
    case cloudStepRequiresPrivacyRepair
    case unsafeHandoff(String)
    case unknown(String)
}

// MARK: - Binding types

public struct UserRequestID: Hashable, Sendable, Codable {
    public let raw: UUID
    public init() { raw = UUID() }
    public init(raw: UUID) { self.raw = raw }
}

public struct AttemptID: Hashable, Sendable, Codable {
    public let raw: UUID
    public init() { raw = UUID() }
    public init(raw: UUID) { self.raw = raw }
}

public enum BoundArgument: Sendable, Equatable, Codable {
    case text(String)
    case contact(ContactBinding)
    /// The user named someone but the lookup is not a single identifiable person yet.
    case contactQuery(String)
    case instant(Date)
    case place(String)
    case url(URL)
    case shortcutName(String)
}

public enum ArgumentSource: Sendable, Equatable, Codable {
    case userUtterance
    case userEdited
    case approvedDefinition
    case modelProposal
}

/// The concrete, reviewed invocation. Stored in `args_json` before confirmation and executed verbatim.
public struct BoundAction: Sendable, Equatable, Codable {
    public var capabilityID: String
    public var contractVersion: Int
    public var title: String
    public var arguments: [String: BoundArgument]
    public var source: ArgumentSource
    public var executor: ExecutorKey
    /// The exact phrase the user used for a local-write time. It is display/audit data, never reparsed at confirm.
    public var timePhrase: String?
    public var timeZoneID: String?
    public var contactQueries: [String: String]
    public var contactChoices: [String: [ContactCandidate]]
    public var handoffContract: CapabilityContract? = nil

    public init(capabilityID: String, contractVersion: Int, title: String, arguments: [String: BoundArgument],
                source: ArgumentSource, executor: ExecutorKey, timePhrase: String? = nil,
                timeZoneID: String? = nil, contactQueries: [String: String] = [:],
                contactChoices: [String: [ContactCandidate]] = [:]) {
        self.capabilityID = capabilityID; self.contractVersion = contractVersion; self.title = title
        self.arguments = arguments; self.source = source; self.executor = executor
        self.timePhrase = timePhrase; self.timeZoneID = timeZoneID
        self.contactQueries = contactQueries; self.contactChoices = contactChoices
    }

    enum CodingKeys: String, CodingKey {
        case capabilityID, contractVersion, title, arguments, source, executor, timePhrase, timeZoneID, contactQueries, contactChoices, handoffContract
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        capabilityID = try c.decode(String.self, forKey: .capabilityID)
        contractVersion = try c.decode(Int.self, forKey: .contractVersion)
        title = try c.decode(String.self, forKey: .title)
        arguments = try c.decode([String: BoundArgument].self, forKey: .arguments)
        source = try c.decode(ArgumentSource.self, forKey: .source)
        executor = try c.decode(ExecutorKey.self, forKey: .executor)
        timePhrase = try c.decodeIfPresent(String.self, forKey: .timePhrase)
        timeZoneID = try c.decodeIfPresent(String.self, forKey: .timeZoneID)
        contactQueries = try c.decodeIfPresent([String: String].self, forKey: .contactQueries) ?? [:]
        contactChoices = try c.decodeIfPresent([String: [ContactCandidate]].self, forKey: .contactChoices) ?? [:]
        handoffContract = try c.decodeIfPresent(CapabilityContract.self, forKey: .handoffContract)
    }
}

// MARK: - Cards and edits

public enum DraftFieldKind: Sendable, Equatable, Codable { case text, contact, method, instant, place }

public struct DraftField: Sendable, Equatable {
    public var name: String
    public var kind: DraftFieldKind
    public var value: String
    public var choices: [ContactCandidate]
    public var methods: [ContactMethod]
    public var instant: Date?
    public var timeZoneID: String?
    public init(name: String, kind: DraftFieldKind, value: String, choices: [ContactCandidate] = [],
                methods: [ContactMethod] = [], instant: Date? = nil, timeZoneID: String? = nil) {
        self.name = name; self.kind = kind; self.value = value; self.choices = choices
        self.methods = methods; self.instant = instant; self.timeZoneID = timeZoneID
    }
}

public struct DuplicateHint: Sendable, Equatable {
    public var existingAttemptID: AttemptID
    public var title: String
    public var minute: Date?
    public var note: String
    public init(existingAttemptID: AttemptID, title: String, minute: Date?, note: String) {
        self.existingAttemptID = existingAttemptID; self.title = title; self.minute = minute; self.note = note
    }
}

public struct DraftCard: Sendable, Equatable {
    public var attemptID: AttemptID
    public var requestID: UserRequestID
    public var capabilityID: String
    public var contractVersion: Int
    public var revision: Int
    public var title: String
    public var fields: [DraftField]
    public var notice: String
    public var reviewSentence: String
    public var duplicateHint: DuplicateHint?
    public var canConfirm: Bool
    public var timeZoneID: String?
    public init(attemptID: AttemptID, requestID: UserRequestID, capabilityID: String, contractVersion: Int,
                revision: Int = 0, title: String, fields: [DraftField], notice: String, reviewSentence: String,
                duplicateHint: DuplicateHint? = nil, canConfirm: Bool, timeZoneID: String? = nil) {
        self.attemptID = attemptID; self.requestID = requestID; self.capabilityID = capabilityID
        self.contractVersion = contractVersion; self.revision = revision; self.title = title
        self.fields = fields; self.notice = notice; self.reviewSentence = reviewSentence
        self.duplicateHint = duplicateHint; self.canConfirm = canConfirm; self.timeZoneID = timeZoneID
    }
}

public struct DraftEdit: Sendable, Equatable {
    public var field: String
    public var value: DraftEditValue
    public init(field: String, value: DraftEditValue) { self.field = field; self.value = value }
}

public enum DraftEditValue: Sendable, Equatable {
    case text(String)
    case contactID(String)
    case refreshContact
    /// The exact labelled method/value shown on this card. Revalidated against Contacts at confirm.
    case contactMethod(ContactMethod)
    case instant(Date)
}

// MARK: - Typed outcomes

public struct EffectReport: Sendable, Equatable {
    public var boundary: EffectBoundary
    public init(boundary: EffectBoundary) { self.boundary = boundary }
}

public enum EffectBoundary: Sendable, Equatable {
    case notStarted(NotStartedReason)
    case startedUnverified(UnverifiedReason)
    case observed(ObservedOutcome)
}

public enum StoreKind: Sendable, Equatable, Codable { case reminders, calendars, contacts }
public enum SheetKind: Sendable, Equatable, Codable { case messages, mail }

public enum NotStartedReason: Sendable, Equatable {
    case permission(StoreKind, AccessLevel)
    case sheetUnavailable(SheetKind)
    /// A different attempt owns the one system compose sheet. This is transient: the attempt returns to the card.
    case sheetBusy(SheetKind)
    case missingContactMethod
    case bindingRejected
    case unsupportedOnThisOS
}

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
    public init(identifier: String, title: String, instant: Date?, attemptTokenFound: Bool) {
        self.identifier = identifier; self.title = title; self.instant = instant
        self.attemptTokenFound = attemptTokenFound
    }
}

public enum MessageSheetResult: Sendable, Equatable { case acceptedOrQueued, cancelled, failed }
public enum MailSheetResult: Sendable, Equatable { case queuedInOutbox, savedDraft, cancelled, failed }
public enum URLOpenObservation: Sendable, Equatable { case systemAccepted, systemRefused }

// MARK: - Disposition

public enum AttemptPhase: Sendable, Equatable, Codable {
    case awaitingUser(UserPause?)
    case claimed
    case settled(Disposition)
    case ambiguous(AmbiguousReason)
}

public enum Disposition: Sendable, Equatable, Codable {
    case committed(CommittedEffect)
    case sheet(SheetObservation)
    case handedOff(HandoffRecord)
    case cancelled(CancelKind)
    case failed(FailureKind)
    /// A reply-only read was confirmed and completed. This is not an effect and has no delivery meaning.
    case read(ReadReceipt)
}

public enum CommittedEffect: Sendable, Equatable, Codable {
    case eventKitItem(id: String, title: String, instant: Date?)
    case memoryFact(id: String)
}

public enum SheetObservation: Sendable, Equatable, Codable {
    case messagesQueuedOrSent
    case mailQueuedInOutbox
    case mailDraftSaved
}

public enum HandoffRecord: Sendable, Equatable, Codable {
    case systemAcceptedURL
}

public enum CancelKind: Sendable, Equatable, Codable { case userCard, messageSheet, mailSheet }

public enum FailureKind: Sendable, Equatable, Codable {
    case permission(StoreKind, AccessLevel)
    case sheetUnavailable(SheetKind)
    case urlRefused
    case messageSheetFailed
    case mailSheetFailed
    case missingContactMethod
    case unavailable
}

public enum AmbiguousReason: Sendable, Equatable, Codable {
    case claimedWithoutReceipt
    case saveUnverified
}

public enum UserPause: Sendable, Equatable, Codable {
    case needsTime
    case needsContactChoice
    case needsField(String)
    case contractVersionStale
    case outputBinding
    case sheetBusy(SheetKind)
}

public struct ReadReceipt: Sendable, Equatable, Codable {
    public var text: String
    public var provider: String?
    public var cloudPromptSent: String?
    public var withheldForSensitivity: Bool
    public init(text: String, provider: String? = nil, cloudPromptSent: String? = nil, withheldForSensitivity: Bool = false) {
        self.text = text; self.provider = provider; self.cloudPromptSent = cloudPromptSent
        self.withheldForSensitivity = withheldForSensitivity
    }
}

/// A read result kept structured so the app can show the real provider and privacy payload on both the
/// immediate and confirm paths. It is never a claim that an effect happened.
public struct ReadResult: Sendable, Equatable {
    public var text: String
    public var provider: String?
    public var cloudPromptSent: String?
    public var withheldForSensitivity: Bool
    public var decisions: [ReflexDecision]
    public init(text: String, provider: String? = nil, cloudPromptSent: String? = nil,
                withheldForSensitivity: Bool = false, decisions: [ReflexDecision] = []) {
        self.text = text; self.provider = provider; self.cloudPromptSent = cloudPromptSent
        self.withheldForSensitivity = withheldForSensitivity; self.decisions = decisions
    }
    public var receipt: ReadReceipt {
        ReadReceipt(text: text, provider: provider, cloudPromptSent: cloudPromptSent, withheldForSensitivity: withheldForSensitivity)
    }
}

public struct EffectResult: Sendable, Equatable {
    public var attemptID: AttemptID
    public var phase: AttemptPhase
    public var summary: String
    public var cloudPromptSent: String?
    public init(attemptID: AttemptID, phase: AttemptPhase, summary: String, cloudPromptSent: String? = nil) {
        self.attemptID = attemptID; self.phase = phase; self.summary = summary
        self.cloudPromptSent = cloudPromptSent
    }
}

public struct UnresolvedAttempt: Sendable, Equatable {
    public var attemptID: AttemptID
    public var capabilityID: String
    public var summary: String
    public init(attemptID: AttemptID, capabilityID: String, summary: String) {
        self.attemptID = attemptID; self.capabilityID = capabilityID; self.summary = summary
    }
}

public struct LaunchRecovery: Sendable, Equatable {
    public var showAgain: [DraftCard]
    public var unresolved: [UnresolvedAttempt]
    public init(showAgain: [DraftCard], unresolved: [UnresolvedAttempt]) {
        self.showAgain = showAgain; self.unresolved = unresolved
    }
}

public enum SessionResult: Sendable, Equatable {
    case staged(DraftCard)
    case finished(EffectResult)
    case read(ReadResult)
    case ignoredTerminal(EffectResult)
}

public enum EffectError: Error, Equatable {
    case ledgerUnavailable
    case attemptNotFound
    case notAwaitingUser
    case invalidEdit(String)
    case effectRequiresConfirmation(String)
    case storage(String)
}

// MARK: - Effects protocol

public protocol PhoneEffects: Sendable {
    func resolveContacts(_ query: String) async -> ContactLookup
    func contact(identifier: String) async -> ContactLookup
    func resolveInstant(_ phrase: String) -> InstantParse
    func storeAccess(_ store: StoreKind) -> AccessLevel
    func perform(_ action: BoundAction, ticket: ClaimTicket) async -> EffectReport
}

public struct ClaimTicket: Hashable, Sendable {
    public let attemptID: AttemptID
    public let requestID: UserRequestID
    public let capabilityID: String
    public let contractVersion: Int
    internal init(attemptID: AttemptID, requestID: UserRequestID, capabilityID: String, contractVersion: Int) {
        self.attemptID = attemptID; self.requestID = requestID
        self.capabilityID = capabilityID; self.contractVersion = contractVersion
    }
}

// MARK: - Capability catalog

public enum CapabilityCatalog {
    public static let replyOnlyIDs: Set<String> = [
        "email_digest", "analyze_document", "translate", "summarize_text", "html_viz",
        "device_status", "calendar_find", "memory_recall", "lookup_contact",
    ]

    public static let all: [CapabilityContract] = [
        // Person / money handoffs: compiled floor is always. A JSON file cannot lower it.
        c("imessage_send", "Send an iMessage / text", .personOrMoneyHandoff, .always, .messageSend,
          [ArgSpec("contact", .contact, required: true), ArgSpec("body", .text, required: true)],
          methodKind: .phone, review: "Opens the Messages sheet with this person and message. You tap Send."),
        c("email_compose", "Write an email", .personOrMoneyHandoff, .always, .mailSend,
          [ArgSpec("contact", .contact, required: true), ArgSpec("subject", .text), ArgSpec("body", .text, required: true)],
          methodKind: .email, review: "Opens the Mail sheet with this address, subject and body. You tap Send."),
        c("instagram_dm", "Instagram DM", .externalHandoff, .always, .urlTemplate("https://ig.me/m/{contact}"),
          [ArgSpec("contact", .handle, required: true), ArgSpec("body", .text, required: true)],
          review: "Opens the Instagram DM thread. The message text is copied to the clipboard; paste and send."),
        c("x_dm", "X (Twitter) DM", .externalHandoff, .always, .urlTemplate("https://x.com/{contact}"),
          [ArgSpec("contact", .handle, required: true), ArgSpec("body", .text, required: true)],
          review: "Opens this X profile. The message text is copied to the clipboard; tap Message, paste and send."),
        c("whatsapp_send", "WhatsApp message", .externalHandoff, .always, .urlTemplate("whatsapp://send?text={body}"),
          [ArgSpec("contact", .contact, required: true), ArgSpec("body", .text, required: true)],
          methodKind: .phone, review: "Opens WhatsApp with the text filled in. You pick the chat and tap Send."),
        c("call", "Phone call", .personOrMoneyHandoff, .always, .urlTemplate("tel:{phone}"),
          [ArgSpec("contact", .contact, required: true)], methodKind: .phone,
          review: "Asks iOS to call this exact phone number. iOS shows its own Call prompt."),
        c("facetime", "FaceTime", .personOrMoneyHandoff, .always, .urlTemplate("facetime:{phone}"),
          [ArgSpec("contact", .contact, required: true)], methodKind: .phone,
          review: "Asks iOS to FaceTime this exact phone number."),
        c("uber_ride", "Request an Uber", .personOrMoneyHandoff, .always,
          .urlTemplate("uber://?action=setPickup&pickup=my_location&dropoff[formatted_address]={place}"),
          [ArgSpec("place", .place, required: true)],
          review: "Opens Uber with this drop-off. You confirm the ride and the charge in Uber."),
        c("instagram_autoreply", "Auto-reply rule (Instagram / any app)", .localWrite, .always, .autoreplyMemory,
          [ArgSpec("trigger", .text), ArgSpec("reply", .text, required: true)],
          review: "Saves this auto-reply rule to memory. It does not send a message."),

        // Local writes. A confident, fully parsed, user-spoken time may act without a card; calendar creation
        // always reviews its fixed one-hour/no-invitation/no-location contract first.
        c("reminder_create", "Create a reminder", .localWrite, .modelMayAct, .reminderCreate,
          [ArgSpec("title", .text, required: true), ArgSpec("when", .datetime, required: true)],
          review: "Saves a reminder with this title and exact time in Reminders.", version: 3),
        c("calendar_create", "Add a calendar event", .localWrite, .always, .eventCreate,
          [ArgSpec("title", .text, required: true), ArgSpec("when", .datetime, required: true)],
          review: "Saves one fixed one-hour event with this title and exact start time in Calendar. It has no invitations and no location.", version: 3),

        // URL and Shortcut handoffs. Opening is the whole observable outcome.
        c("maps_directions", "Directions in Maps", .externalHandoff, .modelMayAct, .urlTemplate("maps://?daddr={place}"),
          [ArgSpec("place", .place, required: true)],
          review: "Opens Maps directions to this place. This app does not see the route or navigation."),
        c("web_search", "Search the web", .externalHandoff, .modelMayAct, .urlTemplate("https://duckduckgo.com/?q={query}"),
          [ArgSpec("query", .query, required: true)],
          review: "Opens this web search in the browser. This app does not see the result page."),
        c("open_url", "Open a link", .externalHandoff, .modelMayAct, .urlTemplate("{url}"),
          [ArgSpec("url", .url, required: true)],
          review: "Opens this http or https link in the browser. This app does not see the page."),
        c("open_app", "Open an app", .externalHandoff, .modelMayAct,
          .shortcut(name: "PG Open App", input: "{app}"), [ArgSpec("app", .app, required: true)],
          availability: .notWired,
          review: "Asks Shortcuts to open this app. This app does not see whether the app opened. Unavailable until a Shortcut named “PG Open App” is set up; nothing opens from this card."),
        c("run_shortcut", "Run a Shortcut by name", .externalHandoff, .modelMayAct,
          .urlTemplate("shortcuts://run-shortcut?name={name}&input=text&text={text}"),
          [ArgSpec("name", .text, required: true), ArgSpec("text", .text)],
          review: "Asks Shortcuts to run this Shortcut. This app does not see what the Shortcut does."),
        c("create_shortcut", "Create a new Shortcut", .externalHandoff, .modelMayAct,
          .urlTemplate("shortcuts://create-shortcut"), [],
          review: "Opens the Shortcuts editor. Nothing is created until you build it there."),
        c("music_play", "Play music", .externalHandoff, .modelMayAct, .urlTemplate("music://"),
          [ArgSpec("query", .query)],
          review: "Opens Apple Music. This app does not see what plays."),
        c("spotify_play", "Spotify", .externalHandoff, .modelMayAct, .urlTemplate("spotify:search:{query}"),
          [ArgSpec("query", .query)],
          review: "Opens a Spotify search. This app does not see what plays."),
        c("appletv_play", "Apple TV: find a show", .externalHandoff, .modelMayAct,
          .urlTemplate("https://tv.apple.com/search?term={show}"), [ArgSpec("show", .query, required: true)],
          review: "Opens an Apple TV search for this show. It does not start playback or pick an episode."),
        c("alarm_create", "Set an alarm", .externalHandoff, .modelMayAct,
          .shortcut(name: "PG Create Alarm", input: "{time}|{label}"),
          [ArgSpec("time", .datetime, required: true), ArgSpec("label", .text)],
          availability: .notWired,
          review: "Asks the Shortcut to create a Clock alarm. This app does not own or see that alarm. Unavailable until a Shortcut named “PG Create Alarm” is set up; nothing opens from this card.", version: 3),
        c("timer_start", "Start a timer", .externalHandoff, .modelMayAct,
          .shortcut(name: "PG Start Timer", input: "{duration}"), [ArgSpec("duration", .duration, required: true)],
          availability: .notWired,
          review: "Asks the Shortcut to start a Clock timer. This app does not see the timer. Unavailable until a Shortcut named “PG Start Timer” is set up; nothing opens from this card."),
        c("notes_create", "Create a note", .externalHandoff, .modelMayAct,
          .shortcut(name: "PG Create Note", input: "{text}"), [ArgSpec("text", .text, required: true)],
          availability: .notWired,
          review: "Asks Shortcuts to create this note. This app does not see the saved note. Unavailable until a Shortcut named “PG Create Note” is set up; nothing opens from this card."),
        c("photos_open", "Open Photos", .externalHandoff, .modelMayAct, .urlTemplate("photos-redirect://"), [],
          review: "Opens Photos. This app does not see what you do there."),
        c("flashlight_toggle", "Toggle flashlight", .externalHandoff, .modelMayAct,
          .shortcut(name: "PG Toggle Flashlight", input: ""), [],
          availability: .notWired,
          review: "Asks Shortcuts to toggle the flashlight. This app does not see the result. Unavailable until a Shortcut named “PG Toggle Flashlight” is set up; nothing opens from this card."),
        c("focus_toggle", "Toggle Do Not Disturb", .externalHandoff, .modelMayAct,
          .shortcut(name: "PG Toggle Focus", input: ""), [],
          availability: .notWired,
          review: "Asks Shortcuts to toggle Focus. This app does not see the result. Unavailable until a Shortcut named “PG Toggle Focus” is set up; nothing opens from this card."),
        c("low_power_toggle", "Toggle Low Power Mode", .externalHandoff, .modelMayAct,
          .shortcut(name: "PG Toggle Low Power", input: ""), [],
          availability: .notWired,
          review: "Asks Shortcuts to toggle Low Power Mode. This app does not see the result. Unavailable until a Shortcut named “PG Toggle Low Power” is set up; nothing opens from this card."),
        c("weather", "Weather", .externalHandoff, .modelMayAct,
          .shortcut(name: "PG Weather", input: "{place}"), [ArgSpec("place", .place)],
          availability: .notWired,
          review: "Asks the Shortcut for weather. This app does not see the source or the reading. Unavailable until a Shortcut named “PG Weather” is set up; nothing opens from this card."),

        // Reply-only: confirmation is preserved for email/document reads, but nothing is claimed as an effect.
        c("email_digest", "Summarize my recent emails", .localWrite, .always, .emailDigest,
          [ArgSpec("n", .number)], review: "Reads shared email text on this device. This does not open Mail."),
        c("analyze_document", "Analyze a document", .localWrite, .modelMayAct, .documentAnalysis,
          [ArgSpec("document", .document)], review: "Reads the document you picked on this device."),
        c("html_viz", "Make a chart / HTML visualization", .localWrite, .modelMayAct, .htmlVisualization,
          [ArgSpec("data", .text)], review: "Draws a chart on this device. Nothing is sent to another app."),
        c("translate", "Translate a phrase", .localWrite, .modelMayAct, .cloudReason,
          [ArgSpec("text", .text, required: true), ArgSpec("target_language", .text, required: true)], review: "Translates this text into the chosen language. Long text may use the cloud after privacy checks."),
        c("summarize_text", "Summarize shared text", .localWrite, .modelMayAct, .cloudReason,
          [ArgSpec("text", .text)], review: "Summarizes this text. A long local request may use the cloud only as today's read path."),
        c("device_status", "Battery & storage", .localWrite, .modelMayAct, .deviceStatus, [],
          review: "Reads battery and storage on this device."),
        c("calendar_find", "Check my calendar", .localWrite, .modelMayAct, .calendarQuery,
          [ArgSpec("query", .query)], review: "Reads your calendar on this device."),
        c("memory_recall", "Recall something I told you", .localWrite, .modelMayAct, .memoryRecall,
          [ArgSpec("query", .query)], review: "Reads saved memories on this device."),
        c("lookup_contact", "Look up a contact", .localWrite, .modelMayAct, .contactLookup,
          [ArgSpec("contact", .text, required: true)], review: "Reads accessible contact matches; ambiguous matches need clarification."),

        // Compiled, deliberately not wired in Slice 1. Never substituted with the Clock Shortcut.
        c("alarmkit_schedule", "App alarm (not wired)", .localWrite, .modelMayAct, .notWired, [],
          availability: .notWired, review: "This is this app's own alarm. It is not wired in this build; nothing will be scheduled."),
    ]

    private static func c(_ id: String, _ title: String, _ effect: EffectClass, _ floor: ConfirmationFloor,
                          _ executor: ExecutorKey, _ args: [ArgSpec] = [], availability: Availability = .ready,
                          methodKind: ContactMethodKind? = nil, review: String, version: Int = 2) -> CapabilityContract {
        CapabilityContract(id: id, version: version, title: title, effect: effect, confirmation: effect == .externalHandoff ? .always : floor,
                           reviewSentence: review, availability: availability, arguments: args,
                           executor: executor, methodKind: methodKind)
    }

    public static func current(id: String) -> CapabilityContract? {
        all.filter { $0.id == id }.max { $0.version < $1.version }
    }

    public static func contract(id: String, version: Int) -> CapabilityContract? {
        all.first { $0.id == id && $0.version == version }
    }

    public static func isReplyOnly(_ id: String) -> Bool { replyOnlyIDs.contains(id) }

    /// The six trained toolChoice ids plus the handlers that can still arrive as PlannedAction tools.
    public static func capabilityID(forTool tool: String) -> String? {
        switch tool {
        case "send_message": return "imessage_send"
        case "send_email": return "email_compose"
        case "create_reminder": return "reminder_create"
        case "create_event": return "calendar_create"
        case "find_event": return "calendar_find"
        case "search_memory": return "memory_recall"
        case "lookup_contact": return "lookup_contact"
        default: return nil
        }
    }

    public static func resolve(id: String, skill: Skill?) -> ResolvedCapability {
        if isReplyOnly(id) { return .replyOnly }
        if let compiled = current(id: id) { return .compiled(compiled) }
        guard let skill else { return .rejected(.unknown(id)) }
        switch skill.invocation {
        case .urlScheme(let template):
            guard let reason = userHandoffProblem(template: template) else {
                let host = hostLabel(template)
                let title = "Open \(host)"
                let contract = CapabilityContract(id: id, version: 1, title: title, effect: .externalHandoff,
                    confirmation: .always,
                    reviewSentence: "This opens \(host) after you confirm. The other app decides what happens next.",
                    arguments: skill.argSchema, executor: .urlTemplate(template))
                return .userHandoff(contract)
            }
            return .rejected(.unsafeHandoff(reason))
        case .shortcut(let name, let input):
            guard !name.isEmpty, !name.contains("{"), !name.contains("}") else {
                return .rejected(.unsafeHandoff("The Shortcut name must be literal text."))
            }
            let title = "Run Shortcut “\(name)”"
            let contract = CapabilityContract(id: id, version: 1, title: title, effect: .externalHandoff,
                confirmation: .always,
                reviewSentence: "This asks Shortcuts to run “\(name)”. This app does not see what the Shortcut does.",
                arguments: skill.argSchema, executor: .shortcut(name: name, input: input))
            return .userHandoff(contract)
        case .native(let handler):
            return .rejected(.unknownNativeHandler(handler))
        case .cloudReason:
            return .rejected(.cloudStepRequiresPrivacyRepair)
        }
    }

    /// F14: a user file may add an https/http handoff, never a raw-scheme or contact-exfiltration template.
    static func userHandoffProblem(template: String) -> String? {
        let t = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains("\n"), !t.contains("\r"), !t.contains("\0") else {
            return "The handoff template is empty or contains control characters."
        }
        guard let colon = t.firstIndex(of: ":") else { return "The handoff template has no URL scheme." }
        let scheme = String(t[..<colon]).lowercased()
        guard scheme == "https" || scheme == "http" else {
            return "Only http and https templates can be added by a skill file."
        }
        let placeholders = SkillTemplate.placeholders(t)
        let forbidden: Set<String> = ["url", "phone", "contact", "email", "address"]
        if let bad = placeholders.first(where: { forbidden.contains($0.lowercased()) }) {
            return "The template inserts contact or raw-URL data ({\(bad)}); that is not allowed in a file-provided handoff."
        }
        let host = hostLabel(t)
        guard !host.isEmpty, host != "?" else {
            return "The handoff template has no valid host."
        }
        return nil
    }

    static func hostLabel(_ template: String) -> String {
        var filled = ""
        var name = "", inBrace = false
        for ch in template {
            if inBrace {
                if ch == "}" { filled += "x"; name = ""; inBrace = false } else { name.append(ch) }
            } else if ch == "{" { inBrace = true } else { filled.append(ch) }
        }
        if inBrace { filled += "x" }
        if let u = URL(string: filled) {
            if let h = u.host, !h.isEmpty { return h }
            return u.scheme.map { "\($0)://" } ?? template
        }
        return template
    }
}

// MARK: - Ledger

struct AttemptRecord: Sendable, Equatable {
    var attemptID: AttemptID
    var requestID: UserRequestID
    var stepIndex: Int
    var capabilityID: String
    var contractVersion: Int
    var phase: AttemptPhase
    var action: BoundAction
    var revision: Int
    var notice: String
    var created: Date
    var updated: Date
    var receipt: Disposition?
    var planSize: Int? = nil
    var planState: PlanStepState? = nil
    var planBlock: String? = nil
}

enum ClaimOutcome: Sendable {
    case claimed(ClaimTicket, AttemptRecord)
    case terminal(AttemptRecord)
    case mismatch(AttemptRecord)
}

/// The only writer of action_attempts. No await or nested transaction is allowed inside a transaction body.
public final class EffectLedger: @unchecked Sendable {
    let db: SQLiteDB
    private let clock: () -> Date

    public init(db: SQLiteDB, now: @escaping () -> Date = Date.init) throws {
        self.db = db; self.clock = now
        try db.exec("""
        CREATE TABLE IF NOT EXISTS action_attempts (
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
          draft_revision INTEGER NOT NULL DEFAULT 0,
          notice TEXT NOT NULL DEFAULT '',
          receipt_json TEXT,
          created REAL NOT NULL,
          updated REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS action_attempts_request ON action_attempts(request_id, step_index);
        CREATE INDEX IF NOT EXISTS action_attempts_title_minute ON action_attempts(normalized_title, minute_epoch);
        """)
        try migratePlans()
    }

    func now() -> Date { clock() }

    // MARK: insert / load

    @discardableResult
    func insertAwaiting(requestID: UserRequestID, capabilityID: String, contractVersion: Int,
                        action: BoundAction, pause: UserPause?, notice: String, stepIndex: Int = 0,
                        planSize: Int? = nil, planState: PlanStepState? = nil) throws -> AttemptRecord {
        let id = AttemptID()
        let t = clock()
        let key = Self.duplicateKey(action)
        let title = key?.0
        let minute = key?.1
        let sql = """
        INSERT INTO action_attempts(attempt_id, request_id, step_index, capability_id, contract_version, phase,
          pause, disposition, args_json, normalized_title, minute_epoch, draft_revision, notice, receipt_json, created, updated,
          plan_size, plan_json)
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """
        try db.run(sql, [.text(id.raw.uuidString), .text(requestID.raw.uuidString), .int(Int64(stepIndex)),
                         .text(capabilityID), .int(Int64(contractVersion)), .text(Self.kind(.awaitingUser(nil))),
                         Self.jsonText(pause).map(SQLValue.text) ?? .null, .null, .text(Self.jsonText(action) ?? "{}"),
                         title.map(SQLValue.text) ?? .null, minute.map { SQLValue.int(Int64($0)) } ?? .null,
                         .int(0), .text(notice), .null, .double(t.timeIntervalSince1970), .double(t.timeIntervalSince1970),
                         planSize.map { .int(Int64($0)) } ?? .null, Self.jsonText(planState).map(SQLValue.text) ?? .null])
        return AttemptRecord(attemptID: id, requestID: requestID, stepIndex: stepIndex, capabilityID: capabilityID,
                             contractVersion: contractVersion, phase: .awaitingUser(pause), action: action,
                             revision: 0, notice: notice, created: t, updated: t, receipt: nil,
                             planSize: planSize, planState: planState)
    }

    func load(_ attemptID: AttemptID) throws -> AttemptRecord? {
        guard let row = try db.query("SELECT * FROM action_attempts WHERE attempt_id=?", [.text(attemptID.raw.uuidString)]).first else { return nil }
        var record = try Self.decode(row)
        record.planBlock = try planBlockingReason(for: record, action: record.action)
        return record
    }

    // MARK: claim and edit

    /// Applies edits and claims in one transaction. `changes()==1` is the only gate. The executor runs after commit.
    func claim(attemptID: AttemptID, expectedRevision: Int, action: BoundAction?) throws -> ClaimOutcome {
        let t = clock()
        let n: Int = try db.transaction {
            guard let saved = try load(attemptID) else { throw EffectError.attemptNotFound }
            guard try planBlockingReason(for: saved, action: action ?? saved.action) == nil else { return 0 }
            if let action {
                try db.run("""
                UPDATE action_attempts SET phase=?, pause=NULL, notice='', args_json=?, draft_revision=draft_revision+1, updated=?
                WHERE attempt_id=? AND phase=? AND draft_revision=?
                """, [.text(Self.kind(.claimed)), .text(Self.jsonText(action) ?? "{}"), .double(t.timeIntervalSince1970),
                       .text(attemptID.raw.uuidString), .text(Self.kind(.awaitingUser(nil))), .int(Int64(expectedRevision))])
            } else {
                try db.run("""
                UPDATE action_attempts SET phase=?, pause=NULL, notice='', draft_revision=draft_revision+1, updated=?
                WHERE attempt_id=? AND phase=? AND draft_revision=?
                """, [.text(Self.kind(.claimed)), .double(t.timeIntervalSince1970),
                       .text(attemptID.raw.uuidString), .text(Self.kind(.awaitingUser(nil))), .int(Int64(expectedRevision))])
            }
            return db.changes()
        }
        guard let current = try load(attemptID) else { throw EffectError.attemptNotFound }
        if n == 1 {
            let ticket = ClaimTicket(attemptID: current.attemptID, requestID: current.requestID,
                                     capabilityID: current.capabilityID, contractVersion: current.contractVersion)
            return .claimed(ticket, current)
        }
        if case .awaitingUser = current.phase { return .mismatch(current) }
        return .terminal(current)
    }

    /// Persists a draft edit without claiming. Revision CAS keeps concurrent edits from overwriting a claim.
    func updateAwaiting(attemptID: AttemptID, expectedRevision: Int, action: BoundAction,
                        pause: UserPause?, notice: String) throws -> AttemptRecord {
        guard let saved = try load(attemptID) else { throw EffectError.attemptNotFound }
        try validatePlanEdit(record: saved, action: action)
        let t = clock()
        try db.run("""
        UPDATE action_attempts SET args_json=?, pause=?, notice=?, draft_revision=draft_revision+1, updated=?
        WHERE attempt_id=? AND phase=? AND draft_revision=?
        """, [.text(Self.jsonText(action) ?? "{}"), Self.jsonText(pause).map(SQLValue.text) ?? .null, .text(notice), .double(t.timeIntervalSince1970),
               .text(attemptID.raw.uuidString), .text(Self.kind(.awaitingUser(nil))), .int(Int64(expectedRevision))])
        guard let current = try load(attemptID) else { throw EffectError.attemptNotFound }
        return current
    }

    /// A transient sheet collision returns the attempt to its card with a retryable notice.
    func releaseClaim(attemptID: AttemptID, pause: UserPause?, notice: String) throws -> AttemptRecord {
        let t = clock()
        try db.run("""
        UPDATE action_attempts SET phase=?, pause=?, notice=?, draft_revision=draft_revision+1, updated=?
        WHERE attempt_id=? AND phase=?
        """, [.text(Self.kind(.awaitingUser(nil))), Self.jsonText(pause).map(SQLValue.text) ?? .null, .text(notice), .double(t.timeIntervalSince1970),
               .text(attemptID.raw.uuidString), .text(Self.kind(.claimed))])
        guard let current = try load(attemptID) else { throw EffectError.attemptNotFound }
        return current
    }

    func record(attemptID: AttemptID, phase: AttemptPhase) throws {
        let t = clock()
        switch phase {
        case .settled(let disposition):
            let receipt = Self.receipt(of: disposition)
            try db.run("""
            UPDATE action_attempts SET phase=?, pause=?, disposition=?, receipt_json=?, notice='', updated=?
            WHERE attempt_id=? AND phase=?
            """, [.text(Self.kind(phase)), Self.jsonText(Self.pause(of: phase)).map(SQLValue.text) ?? .null,
                   .text(Self.jsonText(disposition) ?? "{}"),
                   receipt.map { SQLValue.text(Self.jsonText($0) ?? "{}") } ?? .null,
                   .double(t.timeIntervalSince1970), .text(attemptID.raw.uuidString), .text(Self.kind(.claimed))])
        case .ambiguous(let reason):
            try db.run("""
            UPDATE action_attempts SET phase=?, pause=NULL, disposition=?, receipt_json=NULL, notice='', updated=?
            WHERE attempt_id=? AND phase=?
            """, [.text(Self.kind(phase)), .text(Self.jsonText(reason) ?? "{}"),
                   .double(t.timeIntervalSince1970), .text(attemptID.raw.uuidString), .text(Self.kind(.claimed))])
        default:
            throw EffectError.storage("record needs a terminal phase")
        }
    }

    func cancel(attemptID: AttemptID) throws -> AttemptRecord {
        let t = clock()
        let phase = AttemptPhase.settled(.cancelled(.userCard))
        try db.run("""
        UPDATE action_attempts SET phase=?, pause=NULL, disposition=?, receipt_json=NULL, notice='', updated=?
        WHERE attempt_id=? AND phase=?
        """, [.text(Self.kind(phase)), .text(Self.jsonText(Disposition.cancelled(.userCard)) ?? "{}"),
               .double(t.timeIntervalSince1970), .text(attemptID.raw.uuidString), .text(Self.kind(.awaitingUser(nil)))])
        guard let current = try load(attemptID) else { throw EffectError.attemptNotFound }
        guard case .settled = current.phase else { throw EffectError.notAwaitingUser }
        return current
    }

    // MARK: recovery / duplicate

    func recover(now: Date) throws -> LaunchRecovery {
        var cards: [DraftCard] = []
        var unresolved: [UnresolvedAttempt] = []
        for row in try db.query("SELECT * FROM action_attempts ORDER BY created, attempt_id") {
            guard var record = try? Self.decode(row) else {
                // A row that cannot be decoded is never presented as success or automatically retried.
                if let idText = row["attempt_id"]?.text, let uuid = UUID(uuidString: idText) {
                    unresolved.append(UnresolvedAttempt(attemptID: AttemptID(raw: uuid),
                                                        capabilityID: row["capability_id"]?.text ?? "unknown",
                                                        summary: "A saved attempt could not be read. It will not run again."))
                }
                continue
            }
            record.planBlock = try planBlockingReason(for: record, action: record.action)
            switch record.phase {
            case .awaitingUser:
                guard let contract = Self.contract(for: record) else {
                    unresolved.append(UnresolvedAttempt(attemptID: record.attemptID, capabilityID: record.capabilityID,
                                                        summary: "This saved request uses a policy version this build does not have. It will not run."))
                    continue
                }
                let hint = try duplicateHint(for: record, contract: contract)
                cards.append(Self.card(for: record, contract: contract, duplicate: hint, now: now))
            case .claimed:
                unresolved.append(UnresolvedAttempt(attemptID: record.attemptID, capabilityID: record.capabilityID,
                                                    summary: Self.unresolvedSummary(record)))
            case .ambiguous:
                unresolved.append(UnresolvedAttempt(attemptID: record.attemptID, capabilityID: record.capabilityID,
                                                    summary: Self.summary(for: record.phase, contract: Self.contract(for: record), action: record.action)))
            case .settled:
                continue
            }
        }
        return LaunchRecovery(showAgain: cards, unresolved: unresolved)
    }

    func duplicateHint(for record: AttemptRecord, contract: CapabilityContract) throws -> DuplicateHint? {
        guard let (title, minute) = Self.duplicateKey(record.action) else { return nil }
        let rows = try db.query("""
        SELECT attempt_id, capability_id, created FROM action_attempts
        WHERE normalized_title=? AND minute_epoch=? AND attempt_id<>? AND phase<>?
        ORDER BY created LIMIT 1
        """, [.text(title), .int(Int64(minute)), .text(record.attemptID.raw.uuidString), .text(Self.kind(.claimed))])
        guard let r = rows.first, let idText = r["attempt_id"]?.text, let uuid = UUID(uuidString: idText) else { return nil }
        let when = Date(timeIntervalSince1970: Double(minute) * 60)
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
        return DuplicateHint(existingAttemptID: AttemptID(raw: uuid), title: record.action.title, minute: when,
                             note: "A \(contract.title.lowercased()) with this title and minute already exists. This is a hint, not a match; confirming creates a separate request.")
    }

    static func duplicateKey(_ action: BoundAction) -> (String, Int)? {
        switch action.executor {
        case .reminderCreate, .eventCreate: break
        default: return nil
        }
        guard let title = Self.textArg(action, "title")?.trimmed, !title.isEmpty else { return nil }
        guard case .instant(let date)? = action.arguments["when"] else { return nil }
        let norm = title.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
        return (norm, Int(floor(date.timeIntervalSince1970 / 60)))
    }

    static func textArg(_ action: BoundAction, _ name: String) -> String? {
        if case .url(let u)? = action.arguments[name] { return u.absoluteString }
        if case .text(let s)? = action.arguments[name] { return s }
        if case .place(let s)? = action.arguments[name] { return s }
        if case .shortcutName(let s)? = action.arguments[name] { return s }
        if case .contactQuery(let s)? = action.arguments[name] { return s }
        if case .contact(let b)? = action.arguments[name] { return b.displayName }
        return nil
    }

    // MARK: card construction

    /// A user handoff has no row in the compiled catalog; its reviewed invocation is the persisted action.
    /// Rebuilding the display contract from that snapshot is what prevents a later JSON file from changing it.
    static func contract(for record: AttemptRecord) -> CapabilityContract? {
        if let stored = CapabilityCatalog.contract(id: record.capabilityID, version: record.contractVersion) {
            return stored
        }
        // A compiled id with a missing version is stale policy. Only an id with no compiled entry at all can
        // rebuild its reviewed contract from the persisted user-handoff snapshot.
        if CapabilityCatalog.all.contains(where: { $0.id == record.capabilityID }) { return nil }
        guard let saved = record.action.handoffContract,
              saved.id == record.capabilityID, saved.version == record.contractVersion,
              saved.executor == record.action.executor, saved.confirmation == .always,
              saved.effect == .externalHandoff else { return nil }
        switch saved.executor {
        case .urlTemplate, .shortcut: return saved
        default: return nil
        }
    }

    static func card(for record: AttemptRecord, contract: CapabilityContract, duplicate: DuplicateHint?, now: Date) -> DraftCard {
        var fields: [DraftField] = []
        for spec in contract.arguments {
            switch spec.kind {
            case .contact, .handle:
                if case .contact(let b)? = record.action.arguments[spec.name] {
                    let value = b.method.map { "\(b.displayName) — \($0.display)" } ?? b.displayName
                    fields.append(DraftField(name: spec.name, kind: .contact, value: value,
                                             choices: record.action.contactChoices[spec.name] ?? []))
                    if b.method == nil, let needed = contract.methodKind {
                        let methods = (record.action.contactChoices[spec.name] ?? [])
                            .first { $0.identifier == b.identifier }?.methods ?? []
                        fields.append(DraftField(name: "\(spec.name).method", kind: .method, value: "",
                                                 methods: methods.filter { $0.kind == needed }))
                    }
                } else if case .contactQuery(let q)? = record.action.arguments[spec.name] {
                    fields.append(DraftField(name: spec.name, kind: .contact, value: q,
                                             choices: record.action.contactChoices[spec.name] ?? []))
                } else if case .text(let s)? = record.action.arguments[spec.name], spec.kind == .handle {
                    fields.append(DraftField(name: spec.name, kind: .text, value: s))
                } else {
                    fields.append(DraftField(name: spec.name, kind: spec.kind == .handle ? .text : .contact,
                                             value: "", choices: record.action.contactChoices[spec.name] ?? []))
                }
            case .datetime:
                if case .instant(let date)? = record.action.arguments[spec.name] {
                    let zone = record.action.timeZoneID ?? TimeZone.current.identifier
                    fields.append(DraftField(name: spec.name, kind: .instant,
                                             value: InstantText.full(date, timeZoneID: zone),
                                             instant: date, timeZoneID: zone))
                } else if case .text(let phrase)? = record.action.arguments[spec.name], !phrase.isEmpty {
                    // A Shortcut handoff receives the exact phrase the user spoke; it is not an EventKit instant.
                    fields.append(DraftField(name: spec.name, kind: .text, value: phrase))
                } else {
                    fields.append(DraftField(name: spec.name, kind: .instant, value: "",
                                             instant: nil, timeZoneID: record.action.timeZoneID ?? TimeZone.current.identifier))
                }
            case .url:
                if case .url(let url)? = record.action.arguments[spec.name] {
                    fields.append(DraftField(name: spec.name, kind: .text, value: url.absoluteString))
                } else if case .text(let text)? = record.action.arguments[spec.name], !text.isEmpty {
                    fields.append(DraftField(name: spec.name, kind: .text, value: text))
                } else {
                    fields.append(DraftField(name: spec.name, kind: .text, value: ""))
                }
            default:
                fields.append(DraftField(name: spec.name, kind: .text, value: textArg(record.action, spec.name) ?? ""))
            }
        }
        // A user handoff card must show the concrete destination, never just the file's title.
        if case .urlTemplate(let template) = record.action.executor {
            let filled = SkillTemplate.fill(template, args: Assistant.stringArguments(record.action), raw: ["url"])
            fields.insert(DraftField(name: "destination", kind: .text, value: CapabilityCatalog.hostLabel(filled)), at: 0)
        } else if case .shortcut(let name, _) = record.action.executor {
            fields.insert(DraftField(name: "destination", kind: .text, value: "Shortcut “\(name)”"), at: 0)
        }
        let readiness = readiness(record.action, contract: contract, now: now)
        let pause = readiness.pause ?? pauseFromRecord(record.phase)
        // The stored notice names the specific cause found at bind time (no match,
        // ambiguity, missing access); the re-derived notice is the generic fallback.
        let notice = record.planBlock ?? (record.notice.isEmpty ? readiness.notice : record.notice)
        var retryableBusy = false
        if case .sheetBusy = pause { retryableBusy = true }
        return DraftCard(attemptID: record.attemptID, requestID: record.requestID,
                         capabilityID: record.capabilityID, contractVersion: record.contractVersion,
                         revision: record.revision, title: contract.title, fields: fields, notice: notice,
                         reviewSentence: contract.reviewSentence, duplicateHint: duplicate,
                         canConfirm: record.planBlock == nil && readiness.ready && (pause == nil || retryableBusy), timeZoneID: record.action.timeZoneID)
    }

    static func pauseFromRecord(_ phase: AttemptPhase) -> UserPause? {
        if case .awaitingUser(let p) = phase { return p }
        return nil
    }

    struct Readiness { var ready: Bool; var pause: UserPause?; var notice: String }

    /// Derived from the stored action. It never calls Contacts and never reparses a relative phrase.
    static func readiness(_ action: BoundAction, contract: CapabilityContract, now: Date) -> Readiness {
        guard action.capabilityID == contract.id, action.contractVersion == contract.version,
              action.executor == contract.executor else {
            return Readiness(ready: false, pause: .contractVersionStale, notice: "The saved action does not match this build's contract. Start a new request.")
        }
        if action.source == .modelProposal {
            return Readiness(ready: false, pause: .needsField("proposal"), notice: "A model proposal cannot run until you choose concrete values.")
        }
        for spec in contract.arguments {
            if spec.kind != .contact && spec.kind != .datetime,
               let issue = ActionValidation.issue(spec: spec, value: textArg(action, spec.name), capabilityID: contract.id) {
                return Readiness(ready: false, pause: .needsField(spec.name), notice: issue.question)
            }
            switch spec.kind {
            case .contact:
                guard let value = action.arguments[spec.name] else {
                    if spec.required { return Readiness(ready: false, pause: .needsContactChoice, notice: "Choose a contact before confirming.") }
                    continue
                }
                switch value {
                case .contact(let b):
                    if contract.methodKind != nil && b.method == nil {
                        return Readiness(ready: false, pause: .needsContactChoice, notice: "Choose which phone number or email to use.")
                    }
                    if let need = contract.methodKind, let m = b.method, m.kind != need {
                        return Readiness(ready: false, pause: .needsContactChoice, notice: need == .phone ? "This action needs a phone number." : "This action needs an email address.")
                    }
                case .contactQuery:
                    return Readiness(ready: false, pause: .needsContactChoice, notice: "Choose the exact person before confirming.")
                default:
                    return Readiness(ready: false, pause: .needsContactChoice, notice: "Choose the exact person before confirming.")
                }
            case .datetime:
                let localWrite: Bool
                switch contract.executor {
                case .reminderCreate, .eventCreate: localWrite = true
                default: localWrite = false
                }
                if let value = action.arguments[spec.name] {
                    if localWrite {
                        guard case .instant(let date) = value else {
                            return Readiness(ready: false, pause: .needsTime, notice: "Choose the exact time before confirming.")
                        }
                        if let phrase = action.timePhrase, phrase.count > ActionValidation.textLimit {
                            return Readiness(ready: false, pause: .needsTime, notice: "Shorten the time description to \(ActionValidation.textLimit) characters, or choose an exact time.")
                        }
                        if !date.timeIntervalSince1970.isFinite || date.timeIntervalSince(now) < -60 {
                            return Readiness(ready: false, pause: .needsTime, notice: "That time has passed. Choose a new exact time; the saved phrase is not reapplied.")
                        }
                    } else {
                        let present: Bool
                        switch value {
                        case .instant(let date): present = date.timeIntervalSince1970.isFinite && date.timeIntervalSince(now) >= -60
                        case .text(let phrase):
                            // A Shortcut receives this phrase. Validate the whole phrase here; no fake resolver
                            // may turn an explicit past time into a future one for the readiness check.
                            present = ActionValidation.issue(spec: spec, value: phrase, capabilityID: contract.id) == nil
                        default: present = false
                        }
                        if spec.required && !present {
                            return Readiness(ready: false, pause: .needsTime, notice: "Choose one exact future time before confirming.")
                        }
                    }
                } else if spec.required || localWrite {
                    return Readiness(ready: false, pause: .needsTime, notice: "Choose the exact time before confirming.")
                }
            case .url:
                guard let value = action.arguments[spec.name] else {
                    if spec.required { return Readiness(ready: false, pause: .needsField(spec.name), notice: "Choose the link before confirming.") }
                    continue
                }
                let valid: Bool
                switch value {
                case .url(let u): valid = ActionValidation.isWebURL(u.absoluteString)
                case .text(let s):
                    if let u = URL(string: s), let scheme = u.scheme?.lowercased(),
                       (scheme == "http" || scheme == "https"), u.host?.isEmpty == false { valid = true } else { valid = false }
                default: valid = false
                }
                if !valid {
                    return Readiness(ready: false, pause: .needsField(spec.name), notice: "Only http or https links can be opened. Correct the link before confirming.")
                }
            default:
                if spec.required, (textArg(action, spec.name) ?? "").isEmpty {
                    return Readiness(ready: false, pause: .needsField(spec.name), notice: "Fill in \(spec.name) before confirming.")
                }
            }
        }
        return Readiness(ready: true, pause: nil, notice: "")
    }

    static func unresolvedSummary(_ record: AttemptRecord) -> String {
        switch record.action.executor {
        case .reminderCreate, .eventCreate:
            return "A reminder or event for this attempt may already exist. This attempt will not write again."
        case .messageSend:
            return "A message may already be in Messages. This attempt will not open the sheet again."
        case .mailSend:
            return "An email may already be in Mail. This attempt will not open the sheet again."
        case .urlTemplate, .shortcut:
            return "This handoff has no verified result. It may have partly run, and this attempt will not open it again."
        case .emailDigest, .documentAnalysis, .cloudReason:
            return "A read was interrupted. A cloud request may already have been sent. This attempt will not run again."
        case .htmlVisualization, .deviceStatus, .calendarQuery, .memoryRecall, .contactLookup:
            return "A read was interrupted. It will not run again."
        case .autoreplyMemory, .notWired:
            return "This attempt started and has no recorded result. It will not run again."
        }
    }

    static func result(for record: AttemptRecord, contract: CapabilityContract?) -> EffectResult {
        let payload: String?
        if case .settled(.read(let receipt)) = record.phase { payload = receipt.cloudPromptSent }
        else { payload = nil }
        return EffectResult(attemptID: record.attemptID, phase: record.phase,
                            summary: summary(for: record.phase, contract: contract, action: record.action),
                            cloudPromptSent: payload)
    }

    static func summary(for phase: AttemptPhase, contract: CapabilityContract?, action: BoundAction) -> String {
        switch phase {
        case .awaitingUser(let pause):
            if case .sheetBusy = pause {
                return "The system compose sheet was busy. Nothing was sent. The card is ready to try again."
            }
            return "This request is waiting for your confirmation. Nothing was done."
        case .claimed:
            return "This attempt already started and has no recorded result. It will not run again."
        case .ambiguous(let reason):
            if CapabilityCatalog.isReplyOnly(action.capabilityID) {
                return "The read has no verified result. A cloud request may already have been sent. This attempt will not run again."
            }
            let name = nameFor(action)
            switch action.executor {
            case .messageSend:
                if reason == .saveUnverified || reason == .claimedWithoutReceipt {
                    return "A message to \(name) may already be in Messages. This attempt will not open the sheet again."
                }
            case .mailSend:
                return "An email to \(name) may already be in Mail. This attempt will not open the sheet again."
            default: break
            }
            if case .reminderCreate = action.executor {
                return "A reminder for this attempt may already exist. This attempt will not write again."
            }
            if case .eventCreate = action.executor {
                return "An event for this attempt may already exist. This attempt will not write again."
            }
            if case .urlTemplate = action.executor, reason == .saveUnverified {
                return "The handoff may have partly run. This attempt will not open it again."
            }
            if case .shortcut = action.executor {
                return "This Shortcut may have partly run. This attempt will not open it again."
            }
            return "This attempt may have partly run. It will not run again."
        case .settled(let disposition):
            return disposition.userSummary(contract: contract, action: action)
        }
    }

    static func nameFor(_ action: BoundAction) -> String {
        if case .contact(let b)? = action.arguments["contact"] { return b.displayName }
        return "them"
    }

    // MARK: private storage encoding

    /// Phase text is private storage. Kind only; pause/disposition carry the typed payload.
    static func kind(_ phase: AttemptPhase) -> String {
        switch phase {
        case .awaitingUser: return "awaitingUser"
        case .claimed: return "claimed"
        case .settled: return "settled"
        case .ambiguous: return "ambiguous"
        }
    }

    static func pause(of phase: AttemptPhase) -> UserPause? {
        if case .awaitingUser(let p) = phase { return p }
        return nil
    }

    static func disposition(of phase: AttemptPhase) -> Disposition? {
        if case .settled(let d) = phase { return d }
        return nil
    }

    static func receipt(of disposition: Disposition) -> Disposition? {
        switch disposition {
        case .committed, .sheet, .handedOff, .read: return disposition
        case .cancelled, .failed: return nil
        }
    }

    static func decode(_ row: [String: SQLValue]) throws -> AttemptRecord {
        guard let idText = row["attempt_id"]?.text, let id = UUID(uuidString: idText),
              let reqText = row["request_id"]?.text, let req = UUID(uuidString: reqText),
              let args = row["args_json"]?.text,
              let action = try? JSONDecoder().decode(BoundAction.self, from: Data(args.utf8))
        else { throw EffectError.storage("bad attempt row") }
        let kind = row["phase"]?.text ?? ""
        let pause = row["pause"]?.text.flatMap { try? JSONDecoder().decode(UserPause.self, from: Data($0.utf8)) }
        let disposition = row["disposition"]?.text.flatMap { try? JSONDecoder().decode(Disposition.self, from: Data($0.utf8)) }
        let phase: AttemptPhase
        switch kind {
        case "awaitingUser": phase = .awaitingUser(pause)
        case "claimed": phase = .claimed
        case "settled": phase = disposition.map { .settled($0) } ?? .ambiguous(.claimedWithoutReceipt)
        case "ambiguous":
            let raw = row["disposition"]?.text
            let reason = raw.flatMap { try? JSONDecoder().decode(AmbiguousReason.self, from: Data($0.utf8)) } ?? .claimedWithoutReceipt
            phase = .ambiguous(reason)
        default:
            phase = .ambiguous(.claimedWithoutReceipt)
        }
        let created = Date(timeIntervalSince1970: row["created"]?.double ?? 0)
        let updated = Date(timeIntervalSince1970: row["updated"]?.double ?? 0)
        let receipt = row["receipt_json"]?.text.flatMap { try? JSONDecoder().decode(Disposition.self, from: Data($0.utf8)) }
        let planSize = row["plan_size"]?.int.map(Int.init)
        let planState: PlanStepState?
        if let planSize {
            guard (2...3).contains(planSize), let index = row["step_index"]?.int, (0..<Int64(planSize)).contains(index),
                  let raw = row["plan_json"]?.text,
                  let decoded = try? JSONDecoder().decode(PlanStepState.self, from: Data(raw.utf8)) else {
                throw ActionPlanError.corruptPlan
            }
            if let dependency = decoded.dependency, !(0..<Int(index)).contains(dependency.stepIndex) {
                throw ActionPlanError.corruptPlan
            }
            planState = decoded
        } else {
            guard row["plan_json"]?.text == nil else { throw ActionPlanError.corruptPlan }
            planState = nil
        }
        return AttemptRecord(attemptID: AttemptID(raw: id), requestID: UserRequestID(raw: req),
                             stepIndex: Int(row["step_index"]?.int ?? 0), capabilityID: row["capability_id"]?.text ?? action.capabilityID,
                             contractVersion: Int(row["contract_version"]?.int ?? Int64(action.contractVersion)),
                             phase: phase, action: action, revision: Int(row["draft_revision"]?.int ?? 0),
                             notice: row["notice"]?.text ?? "", created: created, updated: updated, receipt: receipt,
                             planSize: planSize, planState: planState)
    }

    static func jsonText<T: Encodable>(_ value: T?) -> String? {
        guard let value else { return nil }
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Disposition classification and summaries

extension Disposition {
    /// The only classifier. Text in a report is never promoted to success.
    public static func classify(contract: CapabilityContract, report: EffectReport, action: BoundAction) -> AttemptPhase {
        switch report.boundary {
        case .notStarted(let reason):
            switch reason {
            case .permission(let store, let level): return .settled(.failed(.permission(store, level)))
            case .sheetUnavailable(let sheet): return .settled(.failed(.sheetUnavailable(sheet)))
            case .sheetBusy: return .awaitingUser(nil) // handled by the session as a transient release
            case .missingContactMethod: return .settled(.failed(.missingContactMethod))
            case .bindingRejected: return .settled(.failed(.unavailable))
            case .unsupportedOnThisOS: return .settled(.failed(.unavailable))
            }
        case .startedUnverified:
            return .ambiguous(.saveUnverified)
        case .observed(let observed):
            switch observed {
            case .eventKit(let o):
                let boundTitle = PersistedText.text(action, "title")?.trimmed
                let titleMatches = o.title.trimmed == (boundTitle ?? "")
                let minuteMatches: Bool
                if case .instant(let date)? = action.arguments["when"] {
                    minuteMatches = o.instant.map { Int($0.timeIntervalSince1970 / 60) == Int(date.timeIntervalSince1970 / 60) } ?? false
                } else {
                    minuteMatches = o.instant == nil
                }
                guard !o.identifier.isEmpty, o.attemptTokenFound, titleMatches, minuteMatches else {
                    return .ambiguous(.saveUnverified)
                }
                return .settled(.committed(.eventKitItem(id: o.identifier, title: o.title, instant: o.instant)))
            case .memoryFact(let id, let found):
                guard found else { return .ambiguous(.saveUnverified) }
                return .settled(.committed(.memoryFact(id: id)))
            case .message(let result):
                switch result {
                case .acceptedOrQueued: return .settled(.sheet(.messagesQueuedOrSent))
                case .cancelled: return .settled(.cancelled(.messageSheet))
                case .failed: return .settled(.failed(.messageSheetFailed))
                }
            case .mail(let result):
                switch result {
                case .queuedInOutbox: return .settled(.sheet(.mailQueuedInOutbox))
                case .savedDraft: return .settled(.sheet(.mailDraftSaved))
                case .cancelled: return .settled(.cancelled(.mailSheet))
                case .failed: return .settled(.failed(.mailSheetFailed))
                }
            case .url(let result):
                switch result {
                case .systemRefused: return .settled(.failed(.urlRefused))
                case .systemAccepted:
                    return .settled(.handedOff(.systemAcceptedURL))
                }
            }
        }
    }

    public func userSummary(contract: CapabilityContract?, action: BoundAction) -> String {
        let name = PersistedText.name(action)
        switch self {
        case .committed(let effect):
            switch effect {
            case .eventKitItem(let id, let title, let instant):
                let verb = contract?.executor == .eventCreate ? "Event" : "Reminder"
                let when = instant.map { InstantText.full($0, timeZoneID: action.timeZoneID ?? TimeZone.current.identifier) } ?? "no resolved time"
                let limitations = contract?.id == "calendar_create" ? " It lasts one hour, has no invitations, and has no location." : ""
                return "\(verb) “\(title)” saved for \(when). Identifier: \(id).\(limitations)"
            case .memoryFact:
                return "Saved the auto-reply rule to memory. Nothing was sent."
            }
        case .sheet(let observation):
            switch observation {
            case .messagesQueuedOrSent:
                return "Messages accepted or queued the message to \(name). Delivery is not confirmed."
            case .mailQueuedInOutbox:
                return "Mail queued the message to \(name) in the Outbox. Delivery is not confirmed."
            case .mailDraftSaved:
                return "Mail saved a draft to \(name). It was not sent."
            }
        case .handedOff(let record):
            switch record {
            case .systemAcceptedURL:
                if case .shortcut(let name, _) = action.executor {
                    return "Shortcuts was asked to run \(name). If that Shortcut is not set up, Shortcuts shows an error. This app did not see what it did."
                }
                return "The system accepted a link for \(contract?.title ?? action.title). That does not show what happened in the other app."
            }
        case .cancelled(let kind):
            switch kind {
            case .userCard: return "Cancelled. Nothing was sent or saved."
            case .messageSheet: return "You cancelled the Messages sheet. This attempt did not accept a send."
            case .mailSheet: return "You cancelled the Mail sheet. This attempt did not accept a send."
            }
        case .failed(let failure):
            switch failure {
            case .permission(.reminders, _): return "Reminders access is off. Nothing was saved."
            case .permission(.calendars, _): return "Calendars access is off. Nothing was saved."
            case .permission(.contacts, _): return "Contacts access is off. Nothing was sent."
            case .sheetUnavailable(.messages): return "Messages cannot open a compose sheet on this device. Nothing was sent; this attempt will not fall back to another channel."
            case .sheetUnavailable(.mail): return "Mail cannot open a compose sheet on this device. Nothing was sent; this attempt will not fall back to another channel."
            case .urlRefused: return "The system refused to open this link. Nothing was handed off."
            case .messageSheetFailed: return "Messages reported that it could not send this message. Delivery is not confirmed."
            case .mailSheetFailed: return "Mail reported that it could not queue this message. Delivery is not confirmed."
            case .missingContactMethod:
                return contract?.methodKind == .email
                    ? "This contact has no usable email address. Nothing was sent."
                    : "This contact has no usable phone number. Nothing was sent."
            case .unavailable: return "This action is not available in this build. Nothing was done."
            }
        case .read(let receipt):
            return receipt.text
        }
    }
}

private enum PersistedText {
    static func text(_ action: BoundAction, _ name: String) -> String? {
        if case .text(let s)? = action.arguments[name] { return s }
        return nil
    }
    static func name(_ action: BoundAction) -> String {
        if case .contact(let b)? = action.arguments["contact"] { return b.displayName }
        if case .contactQuery(let q)? = action.arguments["contact"] { return q }
        return "them"
    }
}

// MARK: - Time display

public enum InstantText {
    /// Full date, clock time and timezone. Cards and committed summaries both use this, so a parsed instant is
    /// visible before and after the write (contract Slice 1 + Muse N3).
    public static func full(_ date: Date, timeZoneID: String?) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: timeZoneID ?? "") ?? .current
        f.dateFormat = "EEEE, MMM d, yyyy 'at' h:mm a zzz"
        return f.string(from: date)
    }
}

// MARK: - Session

/// One session for the immediate-act and confirmation paths. Callers never set a phase, write SQL, or
/// interpret a UIKit/SwiftUI result enum.
public struct EffectSession: Sendable {
    public let ledger: EffectLedger
    public let effects: PhoneEffects

    public init(ledger: EffectLedger, effects: PhoneEffects) {
        self.ledger = ledger; self.effects = effects
    }

    public func evaluate(requestID: UserRequestID, capability: ResolvedCapability,
                         raw: PlannedAction, modelAskedConfirm: Bool, explicitDraft: Bool) async throws -> SessionResult {
        let contract: CapabilityContract
        switch capability {
        case .compiled(let c), .userHandoff(let c): contract = c
        case .replyOnly:
            return .finished(EffectResult(attemptID: AttemptID(), phase: .settled(.failed(.unavailable)),
                                          summary: "That request is a read, not an effect. Nothing was done."))
        case .rejected(let rejected):
            return .finished(EffectResult(attemptID: AttemptID(), phase: .settled(.failed(.unavailable)),
                                          summary: Self.rejectedSummary(rejected)))
        }
        guard contract.availability == .ready else {
            return .finished(EffectResult(attemptID: AttemptID(), phase: .settled(.failed(.unavailable)),
                                          summary: Self.unavailableSummary(contract)))
        }

        try Task.checkCancellation()
        if let issue = ActionValidation.issues(contract: contract, args: raw.args).first(where: { $0.code == .unsupported }) {
            return .finished(EffectResult(attemptID: AttemptID(), phase: .settled(.failed(.unavailable)), summary: issue.question))
        }

        let now = ledger.now()
        let bound = await bind(raw: raw, contract: contract, now: now)
        try Task.checkCancellation()
        let action = bound.action
        var pause = bound.pause
        var notice = bound.notice
        let readiness = EffectLedger.readiness(action, contract: contract, now: now)
        if pause == nil { pause = readiness.pause }
        if notice.isEmpty { notice = readiness.notice }
        if action.source == .modelProposal {
            pause = pause ?? .needsField("proposal")
            notice = "A model proposal cannot run until you choose concrete values."
        }

        let mustCard = contract.confirmation == .always || modelAskedConfirm || explicitDraft
        if explicitDraft {
            let draftNotice = "The model was not confident enough to act. This is an editable draft; nothing has been sent or saved yet."
            notice = notice.isEmpty ? draftNotice : notice + " " + draftNotice
        }
        let record = try ledger.insertAwaiting(requestID: requestID, capabilityID: contract.id,
                                               contractVersion: contract.version, action: action,
                                               pause: pause, notice: notice)
        let hint = try ledger.duplicateHint(for: record, contract: contract)
        if pause == nil && !mustCard {
            // A repeated title/minute is a hint, not an identity. Show the card so the user can decide whether
            // this is a new intent, while a genuinely new UserRequestID still gets its own attempt.
            if hint != nil {
                let busyNotice = "A similar item already exists. This is a separate request; confirm to keep both."
                let updated = try ledger.updateAwaiting(attemptID: record.attemptID, expectedRevision: record.revision,
                                                        action: action, pause: nil, notice: busyNotice)
                return .staged(EffectLedger.card(for: updated, contract: contract,
                                                 duplicate: try ledger.duplicateHint(for: updated, contract: contract), now: now))
            }
            return try await perform(record: record, action: action, contract: contract)
        }
        return .staged(EffectLedger.card(for: record, contract: contract, duplicate: hint, now: now))
    }

    /// Confirm applies edits and claims in one revision-guarded transaction. The stored Date is executed verbatim;
    /// relative phrases are never reparsed here.
    public func confirm(attemptID: AttemptID, edits: [DraftEdit], expectedRevision: Int? = nil) async throws -> SessionResult {
        guard let record = try ledger.load(attemptID) else {
            return .ignoredTerminal(EffectResult(attemptID: attemptID, phase: .ambiguous(.claimedWithoutReceipt),
                                                 summary: "This attempt no longer exists. Nothing was done."))
        }
        switch record.phase {
        case .awaitingUser:
            break
        case .claimed, .settled, .ambiguous:
            return .ignoredTerminal(EffectLedger.result(for: record, contract: EffectLedger.contract(for: record)))
        }
        guard let contract = EffectLedger.contract(for: record) else {
            let stale = UserPause.contractVersionStale
            let updated = try ledger.updateAwaiting(attemptID: attemptID, expectedRevision: expectedRevision ?? record.revision,
                                                     action: record.action, pause: stale,
                                                     notice: "This saved request used a policy version this build does not have. Nothing was done.")
            return .staged(EffectLedger.card(for: updated, contract: CapabilityCatalog.current(id: updated.capabilityID) ?? Self.fallbackContract(updated), duplicate: nil, now: ledger.now()))
        }
        if CapabilityCatalog.isReplyOnly(contract.id) {
            return .staged(EffectLedger.card(for: record, contract: contract, duplicate: nil, now: ledger.now()))
        }

        let now = ledger.now()
        if record.planSize != nil, expectedRevision == nil {
            return .staged(EffectLedger.card(for: record, contract: contract, duplicate: nil, now: now))
        }
        var action = record.action
        try await apply(edits, to: &action, contract: contract)
        await revalidateContacts(in: &action, contract: contract)
        try Task.checkCancellation()
        let readiness = EffectLedger.readiness(action, contract: contract, now: now)
        let revision = expectedRevision ?? record.revision

        if !readiness.ready {
            let updated = try ledger.updateAwaiting(attemptID: attemptID, expectedRevision: revision,
                                                     action: action, pause: readiness.pause, notice: readiness.notice)
            guard case .awaitingUser = updated.phase else {
                return .ignoredTerminal(EffectLedger.result(for: updated, contract: contract))
            }
            return .staged(EffectLedger.card(for: updated, contract: contract,
                                             duplicate: try ledger.duplicateHint(for: updated, contract: contract), now: now))
        }

        let claim = try ledger.claim(attemptID: attemptID, expectedRevision: revision, action: action)
        switch claim {
        case .claimed(let ticket, let claimed):
            return try await performClaimed(record: claimed, ticket: ticket, action: action, contract: contract)
        case .mismatch(let current):
            return .staged(EffectLedger.card(for: current, contract: contract,
                                             duplicate: try ledger.duplicateHint(for: current, contract: contract), now: now))
        case .terminal(let current):
            return .ignoredTerminal(EffectLedger.result(for: current, contract: contract))
        }
    }

    /// Persists a card edit without claiming. Uses the same revision CAS as confirm.
    public func edit(attemptID: AttemptID, edits: [DraftEdit], expectedRevision: Int) async throws -> DraftCard {
        guard let record = try ledger.load(attemptID) else { throw EffectError.attemptNotFound }
        guard case .awaitingUser = record.phase else { throw EffectError.notAwaitingUser }
        guard let contract = EffectLedger.contract(for: record) else {
            throw EffectError.invalidEdit("This card's policy version is unavailable.")
        }
        var action = record.action
        try await apply(edits, to: &action, contract: contract)
        let readiness = EffectLedger.readiness(action, contract: contract, now: ledger.now())
        let updated = try ledger.updateAwaiting(attemptID: attemptID, expectedRevision: expectedRevision,
                                                 action: action, pause: readiness.pause, notice: readiness.notice)
        guard case .awaitingUser = updated.phase else {
            throw EffectError.notAwaitingUser
        }
        return EffectLedger.card(for: updated, contract: contract,
                                 duplicate: try ledger.duplicateHint(for: updated, contract: contract), now: ledger.now())
    }

    public func cancel(attemptID: AttemptID) throws -> EffectResult {
        let record = try ledger.cancel(attemptID: attemptID)
        return EffectLedger.result(for: record, contract: EffectLedger.contract(for: record))
    }

    /// Stages a reply-only read so an explicit email/document confirmation survives relaunch with its payload.
    /// This is not an effect claim and never calls PhoneEffects.
    public func stageRead(requestID: UserRequestID, contract: CapabilityContract,
                          raw: PlannedAction, sharedText: String?) throws -> DraftCard {
        var action = BoundAction(capabilityID: contract.id, contractVersion: contract.version, title: contract.title,
                                 arguments: [:], source: .userUtterance, executor: contract.executor)
        for spec in contract.arguments {
            if let v = raw.args[spec.name], !v.isEmpty { action.arguments[spec.name] = .text(v) }
        }
        if let sharedText {
            guard sharedText.count <= ActionValidation.sharedTextLimit else {
                throw EffectError.invalidEdit("Shared text exceeds 24,000 characters. Choose a smaller excerpt.")
            }
            action.arguments["_sharedText"] = .text(sharedText)
        }
        let record = try ledger.insertAwaiting(requestID: requestID, capabilityID: contract.id,
                                               contractVersion: contract.version, action: action,
                                               pause: nil, notice: "")
        return EffectLedger.card(for: record, contract: contract, duplicate: nil, now: ledger.now())
    }

    public func confirmRead(attemptID: AttemptID, expectedRevision: Int? = nil,
                            read: @escaping @Sendable (BoundAction) async throws -> ReadResult) async throws -> SessionResult {
        guard let record = try ledger.load(attemptID) else {
            return .ignoredTerminal(EffectResult(attemptID: attemptID, phase: .ambiguous(.claimedWithoutReceipt),
                                                 summary: "This attempt no longer exists. Nothing was done."))
        }
        guard case .awaitingUser = record.phase else {
            return .ignoredTerminal(EffectLedger.result(for: record, contract: EffectLedger.contract(for: record)))
        }
        guard let contract = EffectLedger.contract(for: record), CapabilityCatalog.isReplyOnly(contract.id) else {
            return .staged(EffectLedger.card(for: record, contract: CapabilityCatalog.current(id: record.capabilityID) ?? Self.fallbackContract(record), duplicate: nil, now: ledger.now()))
        }
        let readiness = EffectLedger.readiness(record.action, contract: contract, now: ledger.now())
        if !readiness.ready {
            let updated = try ledger.updateAwaiting(attemptID: attemptID, expectedRevision: expectedRevision ?? record.revision,
                                                     action: record.action, pause: readiness.pause, notice: readiness.notice)
            guard case .awaitingUser = updated.phase else {
                return .ignoredTerminal(EffectLedger.result(for: updated, contract: contract))
            }
            return .staged(EffectLedger.card(for: updated, contract: contract, duplicate: nil, now: ledger.now()))
        }
        let claim = try ledger.claim(attemptID: attemptID, expectedRevision: expectedRevision ?? record.revision, action: record.action)
        switch claim {
        case .claimed(_, let claimed):
            var cloudPromptSent: String?
            do {
                let result = try await read(claimed.action)
                cloudPromptSent = result.cloudPromptSent
                try ledger.record(attemptID: attemptID, phase: .settled(.read(result.receipt)))
                return .read(result)
            } catch {
                let readError = error
                cloudPromptSent = cloudPromptSent ?? (readError as? CloudRequestFailure)?.cloudPromptSent
                let phase = AttemptPhase.ambiguous(.claimedWithoutReceipt)
                do {
                    try ledger.record(attemptID: attemptID, phase: phase)
                } catch {
                    if let cloudPromptSent { throw CloudRequestFailure(sentText: cloudPromptSent, causedBy: readError) }
                    throw error
                }
                if CloudBrainChain.isCancellation(readError) { throw readError }
                return .finished(EffectResult(attemptID: attemptID, phase: phase,
                                              summary: EffectLedger.summary(for: phase, contract: contract, action: claimed.action),
                                              cloudPromptSent: cloudPromptSent))
            }
        case .mismatch(let current):
            return .staged(EffectLedger.card(for: current, contract: contract, duplicate: nil, now: ledger.now()))
        case .terminal(let current):
            return .ignoredTerminal(EffectLedger.result(for: current, contract: contract))
        }
    }

    // MARK: internals

    private func perform(record: AttemptRecord, action: BoundAction, contract: CapabilityContract) async throws -> SessionResult {
        let claim = try ledger.claim(attemptID: record.attemptID, expectedRevision: record.revision, action: nil)
        switch claim {
        case .claimed(let ticket, let current):
            return try await performClaimed(record: current, ticket: ticket, action: action, contract: contract)
        case .mismatch(let current):
            return .staged(EffectLedger.card(for: current, contract: contract, duplicate: nil, now: ledger.now()))
        case .terminal(let current):
            return .ignoredTerminal(EffectLedger.result(for: current, contract: contract))
        }
    }

    private func performClaimed(record: AttemptRecord, ticket: ClaimTicket, action: BoundAction,
                                contract: CapabilityContract) async throws -> SessionResult {
        if Task.isCancelled {
            return .finished(try finish(attemptID: record.attemptID, phase: .settled(.cancelled(.userCard)), contract: contract))
        }
        let report = await effects.perform(action, ticket: ticket)

        // A transient sheet collision is not a terminal failure. Put the card back and keep the attempt alive.
        if case .notStarted(.sheetBusy(let sheet)) = report.boundary {
            let notice: String
            switch sheet {
            case .messages: notice = "The Messages sheet was busy with another request. Nothing was sent. Try this card again."
            case .mail: notice = "The Mail sheet was busy with another request. Nothing was sent. Try this card again."
            }
            let updated = try ledger.releaseClaim(attemptID: record.attemptID, pause: .sheetBusy(sheet), notice: notice)
            return .staged(EffectLedger.card(for: updated, contract: contract,
                                             duplicate: try ledger.duplicateHint(for: updated, contract: contract), now: ledger.now()))
        }

        let phase = Disposition.classify(contract: contract, report: report, action: action)
        let result = try finish(attemptID: record.attemptID, phase: phase, contract: contract)
        return .finished(result)
    }

    private func finish(attemptID: AttemptID, phase: AttemptPhase, contract: CapabilityContract) throws -> EffectResult {
        try ledger.record(attemptID: attemptID, phase: phase)
        guard let current = try ledger.load(attemptID) else { throw EffectError.attemptNotFound }
        return EffectLedger.result(for: current, contract: contract)
    }

    struct Binding {
        var action: BoundAction
        var pause: UserPause?
        var notice: String
    }

    func bind(raw: PlannedAction, contract: CapabilityContract, now: Date) async -> Binding {
        var args: [String: BoundArgument] = [:]
        var choices: [String: [ContactCandidate]] = [:]
        var queries: [String: String] = [:]
        var pause: UserPause?
        var notice = ""
        var timePhrase: String?
        let zone = TimeZone.current.identifier

        for spec in contract.arguments {
            let rawValue = (raw.args[spec.name] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if rawValue.isEmpty {
                if spec.required {
                    if spec.kind == .contact {
                        pause = pause ?? .needsContactChoice
                        notice = notice.isEmpty ? "Choose a contact before confirming." : notice
                    } else if spec.kind == .datetime {
                        pause = pause ?? .needsTime
                        notice = notice.isEmpty ? "Choose the exact time before confirming." : notice
                    } else {
                        pause = pause ?? .needsField(spec.name)
                        notice = notice.isEmpty ? "Fill in \(spec.name) before confirming." : notice
                    }
                }
                continue
            }
            switch spec.kind {
            case .contact:
                let lookup = await effects.resolveContacts(rawValue)
                choices[spec.name] = lookup.matches
                queries[spec.name] = rawValue
                switch lookup.access {
                case .denied, .restricted:
                    ActionDiagnostics.shared.record(capability: contract.id, phase: .permission, code: .contactsDenied)
                    pause = pause ?? .needsContactChoice
                    notice = notice.isEmpty ? "Contacts access is off. Nothing can be sent until you allow access and choose a contact." : notice
                case .notDetermined:
                    ActionDiagnostics.shared.record(capability: contract.id, phase: .permission, code: .contactsNotDetermined)
                    pause = pause ?? .needsContactChoice
                    notice = notice.isEmpty ? "Contacts access hasn't been granted yet. Allow access to look up this contact; nothing will be sent until you choose." : notice
                default:
                    if lookup.matches.count == 1, let candidate = lookup.matches.first {
                        let filtered = Self.filterMethods(candidate.methods, contract.methodKind)
                        if filtered.count == 1 {
                            args[spec.name] = .contact(ContactBinding(identifier: candidate.identifier,
                                                                      displayName: candidate.displayName,
                                                                      method: filtered[0]))
                        } else {
                            args[spec.name] = .contact(ContactBinding(identifier: candidate.identifier,
                                                                      displayName: candidate.displayName, method: nil))
                            pause = pause ?? .needsContactChoice
                            notice = notice.isEmpty
                                ? (filtered.isEmpty
                                   ? "This contact has no usable \(methodWord(contract.methodKind)). Choose another contact."
                                   : "This contact has more than one \(methodWord(contract.methodKind)). Choose the exact destination.")
                                : notice
                        }
                    } else if lookup.matches.isEmpty {
                        args[spec.name] = .contactQuery(rawValue)
                        pause = pause ?? .needsContactChoice
                        notice = notice.isEmpty ? "No contact with read access matches “\(rawValue)”. Nothing will be sent." : notice
                    } else {
                        args[spec.name] = .contactQuery(rawValue)
                        pause = pause ?? .needsContactChoice
                        notice = notice.isEmpty ? "More than one contact matches “\(rawValue)”. Choose the exact person." : notice
                    }
                }
            case .datetime:
                timePhrase = rawValue
                let localWrite: Bool
                switch contract.executor {
                case .reminderCreate, .eventCreate: localWrite = true
                default: localWrite = false
                }
                if let issue = ActionValidation.issue(spec: spec, value: rawValue, capabilityID: contract.id) {
                    // The phrase itself cannot be honoured. Keep the user's words visible on a handoff card;
                    // a local write keeps an empty time field so it cannot be confirmed as a guessed instant.
                    pause = pause ?? .needsTime
                    notice = notice.isEmpty ? issue.question : notice
                    if !localWrite { args[spec.name] = .text(rawValue) }
                } else {
                    switch effects.resolveInstant(rawValue) {
                    case .parsed(let date):
                        if date.timeIntervalSince(now) < -60 {
                            pause = pause ?? .needsTime
                            notice = notice.isEmpty ? "That time has passed. Choose a new exact time; the phrase is not reapplied." : notice
                            // Do not store a handoff phrase that resolved in the past: readiness can only
                            // re-check its syntax, so keeping it would clear the pause at confirmation.
                        } else if localWrite {
                            args[spec.name] = .instant(date)
                        } else {
                            // URL/Shortcut handoffs receive the user's exact phrase; the app does not pretend to execute a Date.
                            args[spec.name] = .text(rawValue)
                        }
                    case .missing:
                        pause = pause ?? .needsTime
                        notice = notice.isEmpty ? "Choose the exact time before confirming." : notice
                        if !localWrite { args[spec.name] = .text(rawValue) }
                    case .unparsed:
                        pause = pause ?? .needsTime
                        notice = notice.isEmpty ? "I could not resolve that time safely, including any timezone words. Choose the exact time." : notice
                        if !localWrite { args[spec.name] = .text(rawValue) }
                    }
                }
            case .url:
                if let url = URL(string: rawValue), let scheme = url.scheme?.lowercased(),
                   scheme == "http" || scheme == "https", url.host?.isEmpty == false {
                    args[spec.name] = .url(url)
                } else {
                    args[spec.name] = .text(rawValue)
                    pause = pause ?? .needsField(spec.name)
                    notice = notice.isEmpty ? "Only http or https links can be opened. Choose a valid link." : notice
                }
            case .place:
                args[spec.name] = .place(rawValue)
            case .text, .handle, .query, .number, .duration, .app, .document:
                args[spec.name] = .text(rawValue)
            }
        }
        var action = BoundAction(capabilityID: contract.id, contractVersion: contract.version, title: contract.title,
                                 arguments: args, source: .userUtterance, executor: contract.executor,
                                 timePhrase: timePhrase, timeZoneID: args.values.contains(where: {
                                     if case .instant = $0 { return true }; return false
                                 }) ? zone : nil,
                                 contactQueries: queries, contactChoices: choices)
        if CapabilityCatalog.current(id: contract.id) == nil { action.handoffContract = contract }
        return Binding(action: action, pause: pause, notice: notice)
    }

    private func apply(_ edits: [DraftEdit], to action: inout BoundAction, contract: CapabilityContract) async throws {
        guard !edits.isEmpty else { return }
        action.source = .userEdited
        for edit in edits {
            switch edit.value {
            case .refreshContact:
                guard contract.arguments.contains(where: { $0.name == edit.field && $0.kind == .contact }),
                      let query = action.contactQueries[edit.field], !query.isEmpty else {
                    throw EffectError.invalidEdit("This card has no saved contact search to refresh.")
                }
                let lookup = await effects.resolveContacts(query)
                let allowed = lookup.access == .full || lookup.access == .limited
                action.contactChoices[edit.field] = allowed ? lookup.matches : []
                action.arguments[edit.field] = .contactQuery(query)
                if allowed, lookup.matches.count == 1, let candidate = lookup.matches.first {
                    let methods = Self.filterMethods(candidate.methods, contract.methodKind)
                    action.arguments[edit.field] = .contact(ContactBinding(identifier: candidate.identifier,
                                                                          displayName: candidate.displayName,
                                                                          method: methods.count == 1 ? methods[0] : nil))
                }
            case .text(let value):
                guard let spec = contract.arguments.first(where: { $0.name == edit.field }) else {
                    throw EffectError.invalidEdit("Unknown field \(edit.field).")
                }
                let isLocalTime = contract.executor == .reminderCreate || contract.executor == .eventCreate
                guard spec.kind != .contact, !(spec.kind == .datetime && isLocalTime) else {
                    throw EffectError.invalidEdit("\(edit.field) needs a typed edit.")
                }
                action.arguments[edit.field] = spec.kind == .place ? .place(value) : .text(value)
            case .contactID(let identifier):
                guard let spec = contract.arguments.first(where: { $0.name == edit.field }),
                      spec.kind == .contact || spec.kind == .handle else {
                    throw EffectError.invalidEdit("Unknown contact field \(edit.field).")
                }
                guard let choices = action.contactChoices[edit.field], choices.contains(where: { $0.identifier == identifier }) else {
                    throw EffectError.invalidEdit("That contact is not one of this card's choices.")
                }
                let lookup = await effects.contact(identifier: identifier)
                if lookup.matches.count == 1, let candidate = lookup.matches.first {
                    let filtered = Self.filterMethods(candidate.methods, contract.methodKind)
                    let method = filtered.count == 1 ? filtered[0] : nil
                    action.arguments[edit.field] = .contact(ContactBinding(identifier: candidate.identifier,
                                                                           displayName: candidate.displayName, method: method))
                    action.contactChoices[edit.field] = lookup.matches
                } else if lookup.matches.isEmpty {
                    // F8: never dead-end on a stale frozen list. Re-run the original query and show fresh choices.
                    let query = action.contactQueries[edit.field] ?? identifier
                    let refreshed = await effects.resolveContacts(query)
                    action.contactChoices[edit.field] = refreshed.matches
                    action.arguments[edit.field] = .contactQuery(query)
                } else {
                    action.contactChoices[edit.field] = lookup.matches
                    action.arguments[edit.field] = .contactQuery(lookup.matches.first?.displayName ?? edit.field)
                }
            case .contactMethod(let method):
                let field = edit.field.hasSuffix(".method") ? String(edit.field.dropLast(".method".count)) : edit.field
                guard case .contact(var binding)? = action.arguments[field] else {
                    throw EffectError.invalidEdit("Choose the contact before choosing a method.")
                }
                let lookup = await effects.contact(identifier: binding.identifier)
                guard lookup.matches.count == 1, let candidate = lookup.matches.first else {
                    let query = action.contactQueries[field] ?? binding.displayName
                    let refreshed = await effects.resolveContacts(query)
                    action.contactChoices[field] = refreshed.matches
                    action.arguments[field] = .contactQuery(query)
                    continue
                }
                guard let exact = candidate.methods.first(where: { Self.sameMethod($0, method) }) else {
                    throw EffectError.invalidEdit("That contact method is no longer available. Choose another.")
                }
                binding.method = exact
                binding.displayName = candidate.displayName
                action.arguments[field] = .contact(binding)
                action.contactChoices[field] = [candidate]
            case .instant(let date):
                guard let spec = contract.arguments.first(where: { $0.name == edit.field }), spec.kind == .datetime else {
                    throw EffectError.invalidEdit("Unknown time field \(edit.field).")
                }
                if !date.timeIntervalSince1970.isFinite || date.timeIntervalSince(ledger.now()) < -60 {
                    throw EffectError.invalidEdit("Choose a time in the future.")
                }
                action.arguments[edit.field] = .instant(date)
                action.timeZoneID = TimeZone.current.identifier
            }
        }
    }

    /// Confirm re-resolves the exact identifier and labelled method the user saw. A removed or relinked
    /// contact refreshes the choices and pauses; it never falls back to the first number or another method.
    private func revalidateContacts(in action: inout BoundAction, contract: CapabilityContract) async {
        for spec in contract.arguments where spec.kind == .contact {
            guard case .contact(let binding)? = action.arguments[spec.name] else { continue }
            let lookup = await effects.contact(identifier: binding.identifier)
            if lookup.matches.count == 1, let current = lookup.matches.first {
                var updated = ContactBinding(identifier: current.identifier, displayName: current.displayName,
                                             method: binding.method)
                if let chosen = binding.method {
                    updated.method = current.methods.first { Self.sameMethod($0, chosen) }
                    if updated.method == nil {
                        // The labelled method disappeared; keep the person and let the user choose again.
                        action.arguments[spec.name] = .contact(updated)
                        action.contactChoices[spec.name] = [current]
                        continue
                    }
                }
                action.arguments[spec.name] = .contact(updated)
                action.contactChoices[spec.name] = [current]
            } else {
                let query = action.contactQueries[spec.name] ?? binding.displayName
                let refreshed = await effects.resolveContacts(query)
                action.contactChoices[spec.name] = refreshed.matches
                action.arguments[spec.name] = .contactQuery(query)
            }
        }
    }

    static func filterMethods(_ methods: [ContactMethod], _ kind: ContactMethodKind?) -> [ContactMethod] {
        guard let kind else { return methods }
        return methods.filter { $0.kind == kind }
    }

    static func sameMethod(_ a: ContactMethod, _ b: ContactMethod) -> Bool {
        a.kind == b.kind && a.label == b.label && a.value.caseInsensitiveCompare(b.value) == .orderedSame
    }

    func methodWord(_ kind: ContactMethodKind?) -> String {
        kind == .email ? "email address" : "phone number"
    }

    static func unavailableSummary(_ contract: CapabilityContract) -> String {
        if case .shortcut(let name, _) = contract.executor {
            return "\(contract.title) needs a Shortcut named “\(name)”, which this app cannot confirm is set up. Nothing was opened. Build it in Shortcuts, then say “run my shortcut \(name)”."
        }
        return "This is this app's own alarm. It is not wired in this build; nothing was scheduled."
    }

    static func rejectedSummary(_ rejected: RejectedCapability) -> String {
        switch rejected {
        case .unknownNativeHandler(let h): return "This skill file asks for the native handler “\(h)”, which is not compiled into this build. Nothing was done."
        case .cloudStepRequiresPrivacyRepair: return "This saved step would send text to a cloud model. It is not available until the privacy repair ships. Nothing was done."
        case .unsafeHandoff(let reason): return "This skill file's handoff was rejected: \(reason) Nothing was done."
        case .unknown(let id): return "Unknown capability “\(id)”. Nothing was done."
        }
    }

    static func fallbackContract(_ record: AttemptRecord) -> CapabilityContract {
        CapabilityContract(id: record.capabilityID, version: record.contractVersion, title: record.action.title,
                           effect: .localWrite, confirmation: .always, reviewSentence: "Review this request.",
                           executor: record.action.executor)
    }
}

// MARK: - Auto-reply memory postcondition (F6)

public enum AutoreplyMemory {
    public static let attribute = "autoreply_rule"

    /// Saves an auto-reply rule without putting an attempt UUID in user-visible fact text. The postcondition is
    /// semantic: an active fact with this subject/attribute/value exists, whether it was inserted now or found by
    /// the all-important `ignoreNew` path on a repeated request.
    @discardableResult
    public static func save(memory: MemoryStore, trigger: String, reply: String) async throws -> (fact: MemoryFact, wasExisting: Bool) {
        let value = "\(trigger) -> \(reply)"
        if let found = try memory.active().first(where: {
            $0.subject == "user" && $0.attribute == attribute && $0.value.caseInsensitiveCompare(value) == .orderedSame
        }) {
            return (found, true)
        }
        let text = "Auto-reply rule: when someone sends a \(trigger), reply “\(reply)”"
        let result = try await memory.upsert(ExtractedFact(subject: "user", attribute: attribute, value: value,
                                                           text: text, provenance: MemoryProvenance.userStated))
        if let fact = result.fact { return (fact, false) }
        if let found = try memory.active().first(where: {
            $0.subject == "user" && $0.attribute == attribute && $0.value.caseInsensitiveCompare(value) == .orderedSame
        }) {
            return (found, true)
        }
        throw EffectError.storage("the auto-reply rule was not saved")
    }
}

// MARK: - Instant parsing (core, shared by the app adapter and tests)

public enum InstantRejection: Sendable, Equatable {
    case empty
    case noExactTime
    case zone
    case ambiguous
    case multipleTimes
    case past
    case invalidClock

    var question: String {
        switch self {
        case .empty:
            return "Choose one exact time."
        case .noExactTime:
            return "Choose one exact time, not just a day or a vague part of the day."
        case .zone:
            return "This app cannot honour an explicit timezone or city time. Choose a time in the device timezone, or set the zone in the destination app."
        case .ambiguous:
            return "Use one exact time without approximations such as “around”, “sometime” or “or”."
        case .multipleTimes:
            return "Use one exact time. Ranges and multiple times are not supported by this action."
        case .past:
            return "That time has passed. Choose a future time."
        case .invalidClock:
            return "Use a valid time with AM/PM, or a 24-hour time such as 18:30."
        }
    }

    /// A day-only phrase is left to the normal missing-time card. These reasons mean the phrase itself
    /// cannot be honoured, so planning should correct before it builds a one-field action.
    var requiresPlanningCorrection: Bool {
        switch self {
        case .zone, .ambiguous, .multipleTimes, .past, .invalidClock: return true
        case .empty, .noExactTime: return false
        }
    }
}

public enum InstantParser {
    static let zoneHints = try! NSRegularExpression(pattern:
        #"\b(?:(?i:UTC|GMT|EST|EDT|CST|CDT|MST|MDT|PST|PDT|AKST|AKDT|HST|CET|CEST|BST|IST|JST|KST|AEST|AEDT|NZST|NZDT|ET|PT|CT|MT)\b|UTC[+-]\d{1,2}(?::?\d{2})?|(?i:Eastern|Central|Mountain|Pacific|Alaska|Hawaii|Berlin|London|Paris|Tokyo|Sydney|Toronto|Chicago|Denver|Boston|Seattle|New\s+York|Los\s+Angeles|San\s+Francisco|Hong\s+Kong|Singapore|Dubai|Moscow)\b|\b[A-Z][a-z]+\s+time\b|\bin\s+[A-Z][a-z]+\b|\b(?:at|by)\s+\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)\s+(?!(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|Today|Tomorrow|Tonight)\b)[A-Z][a-z]+\b)"#)
    static let timeToken = try! NSRegularExpression(pattern:
        #"(?:\b\d{1,2}:\d{2}\b|\b(?:at|by)\s+\d{1,2}(?::\d{2})?|\b\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)\b|\bin\s+\d+\s+(?:minutes?|mins?|hours?|hrs?|days?)|\b(?:noon|midnight)\b|\btonight\s+(?:at\s+)?\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)?\b)"#,
        options: [.caseInsensitive])
    static let ambiguousHints = try! NSRegularExpression(pattern:
        #"\b(?:or|ish|around|about|approximately|roughly|nearly|maybe|perhaps|sometime)\b|\b(?:\d{4}-\d{2}-\d{2}T\S+|[A-Za-z_]+/[A-Za-z_]+)\b"#,
        options: [.caseInsensitive])
    static let pastHints = try! NSRegularExpression(pattern:
        #"\b(?:yesterday|earlier|last\s+(?:night|week|month|year|monday|tuesday|wednesday|thursday|friday|saturday|sunday)|\d+\s+(?:minutes?|mins?|hours?|hrs?|days?|weeks?|months?|years?)\s+ago)\b"#,
        options: [.caseInsensitive])
    static let clockPattern = try! NSRegularExpression(pattern:
        #"\b(?:at\s+|by\s+)?(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)?\b"#,
        options: [.caseInsensitive])

    /// Structural refusal shared by the parser, argument validation, readiness and planning. It never
    /// resolves a date: a caller with a detector still receives an explicit refusal here first.
    static func rejection(_ phrase: String) -> InstantRejection? {
        let p = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return .empty }
        let ns = p as NSString
        let full = NSRange(location: 0, length: ns.length)
        if zoneHints.firstMatch(in: p, range: full) != nil { return .zone }
        guard timeToken.firstMatch(in: p, range: full) != nil else { return .noExactTime }
        if ambiguousHints.firstMatch(in: p, range: full) != nil { return .ambiguous }
        if pastHints.firstMatch(in: p, range: full) != nil { return .past }
        var clocks = 0
        for m in clockPattern.matches(in: p, range: full) {
            // Relative quantities are durations, not clock hours.
            let tail = ns.substring(from: m.range.location + m.range.length)
            if tail.range(of: #"^\s*(minutes?|mins?|hours?|hrs?|days?)\b"#, options: [.regularExpression, .caseInsensitive]) != nil { continue }
            let hour = Int(ns.substring(with: m.range(at: 1))) ?? -1
            let minute = m.range(at: 2).location == NSNotFound ? 0 : Int(ns.substring(with: m.range(at: 2))) ?? -1
            let meridiem = m.range(at: 3).location != NSNotFound
            if !(0...59).contains(minute) || (meridiem ? !(1...12).contains(hour) : !(0...23).contains(hour)) { return .invalidClock }
            if !meridiem && (1...12).contains(hour) { return .invalidClock }
            clocks += 1
        }
        if clocks > 1 { return .multipleTimes }
        return nil
    }

    /// Foundation date detection is iOS-only (`NSDataDetector` is absent from corelibs on Linux), so the app
    /// supplies the detector through `dateResolver`. The zone/time-token guard lives here so both the app and
    /// tests make the same decision about a phrase that cannot be honoured safely.
    public static func parse(_ phrase: String, now: Date = Date(), timeZone: TimeZone = .current,
                             dateResolver: (String) -> Date?) -> InstantParse {
        _ = now; _ = timeZone
        let p = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return .missing }
        if rejection(p) != nil { return .unparsed(p) }
        guard let date = dateResolver(p), date.timeIntervalSince1970.isFinite else { return .unparsed(p) }
        return .parsed(date)
    }
}
