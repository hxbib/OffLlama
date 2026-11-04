import XCTest
@testable import PocketCore

func phone(_ label: String, _ value: String) -> ContactMethod {
    let tail = value.filter(\.isNumber).suffix(4)
    return ContactMethod(kind: .phone, label: label, value: value, display: "\(label) ···\(tail)")
}

func email(_ label: String, _ value: String) -> ContactMethod {
    ContactMethod(kind: .email, label: label, value: value.lowercased(), display: "\(label) \(value.lowercased())")
}

func candidate(_ name: String, id: String, detail: String = "", methods: [ContactMethod]) -> ContactCandidate {
    ContactCandidate(identifier: id, displayName: name, detail: detail, methods: methods)
}

/// Deterministic fake adapter. It never touches EventKit, Contacts, MessageUI, or Shortcuts.
final class FakePhoneEffects: PhoneEffects, @unchecked Sendable {
    private let lock = NSLock()
    var contactQueries: [String: ContactLookup] = [:]
    var contactIDs: [String: ContactLookup] = [:]
    var instantPhrases: [String: InstantParse] = [:]
    var defaultInstant: (String) -> InstantParse = { _ in .parsed(Date().addingTimeInterval(3600)) }
    var access: [StoreKind: AccessLevel] = [.reminders: .full, .calendars: .full, .contacts: .full]
    var handler: ((BoundAction, ClaimTicket) async -> EffectReport)?
    var delayNanoseconds: UInt64 = 0
    var memory: MemoryStore?
    /// Optional observation of the row at the moment the fake executor is entered, for claim-before-save assertions.
    var ledger: EffectLedger?

    private(set) var performed: [(action: BoundAction, ticket: ClaimTicket)] = []
    private(set) var performCount = 0
    private(set) var saveCount = 0
    private(set) var phaseAtPerform: AttemptPhase?

    func resolveContacts(_ query: String) async -> ContactLookup {
        contactQueries[query] ?? ContactLookup(access: access[.contacts] ?? .full, matches: [])
    }

    func contact(identifier: String) async -> ContactLookup {
        contactIDs[identifier] ?? ContactLookup(access: access[.contacts] ?? .full, matches: [])
    }

    func resolveInstant(_ phrase: String) -> InstantParse {
        instantPhrases[phrase] ?? defaultInstant(phrase)
    }

    func storeAccess(_ store: StoreKind) -> AccessLevel {
        access[store] ?? .full
    }

    func perform(_ action: BoundAction, ticket: ClaimTicket) async -> EffectReport {
        record(action, ticket)
        if delayNanoseconds > 0 { try? await Task.sleep(nanoseconds: delayNanoseconds) }
        if let handler { return await handler(action, ticket) }
        switch action.executor {
        case .reminderCreate, .eventCreate:
            let store: StoreKind = {
                if case .eventCreate = action.executor { return .calendars }
                return .reminders
            }()
            let level = access[store] ?? .full
            if level != .full { return EffectReport(boundary: .notStarted(.permission(store, level))) }
            bumpSave()
            let title = text(action, "title") ?? ""
            let instant: Date? = { if case .instant(let d)? = action.arguments["when"] { return d }; return nil }()
            return EffectReport(boundary: .observed(.eventKit(EventKitObservation(
                identifier: "ek-\(ticket.attemptID.raw.uuidString)", title: title,
                instant: instant, attemptTokenFound: true))))
        case .messageSend:
            return EffectReport(boundary: .observed(.message(.acceptedOrQueued)))
        case .mailSend:
            return EffectReport(boundary: .observed(.mail(.queuedInOutbox)))
        case .urlTemplate, .shortcut:
            return EffectReport(boundary: .observed(.url(.systemAccepted)))
        case .autoreplyMemory:
            guard let memory else { return EffectReport(boundary: .notStarted(.unsupportedOnThisOS)) }
            do {
                let saved = try await AutoreplyMemory.save(memory: memory,
                                                           trigger: text(action, "trigger") ?? "message",
                                                           reply: text(action, "reply") ?? "")
                return EffectReport(boundary: .observed(.memoryFact(id: String(saved.fact.id), attemptTokenFound: true)))
            } catch {
                return EffectReport(boundary: .startedUnverified(.executorThrew))
            }
        case .notWired:
            return EffectReport(boundary: .notStarted(.unsupportedOnThisOS))
        case .emailDigest, .documentAnalysis, .htmlVisualization, .cloudReason, .deviceStatus, .calendarQuery, .memoryRecall:
            return EffectReport(boundary: .notStarted(.bindingRejected))
        }
    }

    private func record(_ action: BoundAction, _ ticket: ClaimTicket) {
        lock.lock(); defer { lock.unlock() }
        performed.append((action, ticket))
        performCount += 1
        phaseAtPerform = try? ledger?.load(ticket.attemptID)?.phase
    }

    private func bumpSave() {
        lock.lock(); defer { lock.unlock() }
        saveCount += 1
    }

    private func text(_ action: BoundAction, _ name: String) -> String? {
        if case .text(let s)? = action.arguments[name] { return s }
        if case .place(let s)? = action.arguments[name] { return s }
        return nil
    }
}

func makeLedger(path: String = ":memory:", now: @escaping () -> Date = Date.init) throws -> (SQLiteDB, EffectLedger) {
    let db = try SQLiteDB(path: path)
    return (db, try EffectLedger(db: db, now: now))
}

func tempDBPath(_ name: String) -> String {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pg-effect-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("\(name.isEmpty ? "pocket" : name).sqlite").path
}

func reminderContract() -> CapabilityContract {
    CapabilityCatalog.current(id: "reminder_create")!
}

func messageContract() -> CapabilityContract {
    CapabilityCatalog.current(id: "imessage_send")!
}

func mailContract() -> CapabilityContract {
    CapabilityCatalog.current(id: "email_compose")!
}

func urlContract(_ id: String = "instagram_dm") -> CapabilityContract {
    CapabilityCatalog.current(id: id)!
}

func text(_ action: BoundAction, _ name: String) -> String? {
    if case .text(let s)? = action.arguments[name] { return s }
    if case .place(let s)? = action.arguments[name] { return s }
    return nil
}

extension AttemptPhase {
    var disposition: Disposition? { if case .settled(let d) = self { return d }; return nil }
    var isCommitted: Bool { if case .settled(.committed) = self { return true }; return false }
    var isSheet: Bool { if case .settled(.sheet) = self { return true }; return false }
    var isHandedOff: Bool { if case .settled(.handedOff) = self { return true }; return false }
    var isAmbiguous: Bool { if case .ambiguous = self { return true }; return false }
}
