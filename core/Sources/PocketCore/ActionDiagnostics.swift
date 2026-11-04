import Foundation

public enum ActionDiagPhase: String, Sendable, Codable {
    case routing, draft, followUp, projection, presentation, permission
}

public enum ActionDiagCode: String, Sendable, Codable {
    case explicitChartRendered
    case explicitMessageMatch
    case explicitMessageRoutedSkill
    case explicitMessageRoutedTool
    case draftCreated
    case draftUpdated
    case draftStaged
    case draftConsumed
    case draftCancelled
    case draftExpired
    case followUpCompleted
    case followUpUpdated
    case followUpCancelled
    case followUpKept
    case followUpDisambiguated
    case followUpNewRequest
    case contactsNotDetermined
    case contactsDenied
    case contactsRequested
    case cardProjected
    case presentationRequested
    case presentationAccepted
    case presentationCancelled
    case presentationFailed
    case presentationUnavailable
    case presentationBusy
    case callbackIgnored
}

public enum ActionDiagCapability: String, Sendable, Codable {
    case messages = "imessage_send"
    case whatsapp = "whatsapp_send"
    case instagram = "instagram_dm"
    case x = "x_dm"
    case email = "email_compose"
    case otherCompiledAction
}

public struct ActionDiagEvent: Sendable, Equatable, Codable {
    public var at: Date
    public var requestID: UUID?
    public var attemptID: UUID?
    public var capability: ActionDiagCapability?
    public var phase: ActionDiagPhase
    public var code: ActionDiagCode

    public init(at: Date = Date(), requestID: UUID? = nil, attemptID: UUID? = nil,
                capability: ActionDiagCapability? = nil, phase: ActionDiagPhase, code: ActionDiagCode) {
        self.at = at; self.requestID = requestID; self.attemptID = attemptID
        self.capability = capability; self.phase = phase; self.code = code
    }
}

public final class ActionDiagnostics: @unchecked Sendable {
    public static let shared = ActionDiagnostics()
    public static let capacity = 256

    private let lock = NSLock()
    private var events: [ActionDiagEvent] = []

    public init() {}

    public func record(requestID: UserRequestID? = nil, attemptID: AttemptID? = nil,
                       capability: String? = nil, phase: ActionDiagPhase,
                       code: ActionDiagCode, at: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        let classified = capability.flatMap { id in
            ActionDiagCapability(rawValue: id) ?? (CapabilityCatalog.current(id: id) == nil ? nil : .otherCompiledAction)
        }
        events.append(ActionDiagEvent(at: at, requestID: requestID?.raw,
                                      attemptID: attemptID?.raw,
                                      capability: classified, phase: phase, code: code))
        if events.count > Self.capacity { events.removeFirst(events.count - Self.capacity) }
    }

    public func snapshot() -> [ActionDiagEvent] {
        lock.lock(); defer { lock.unlock() }
        return events
    }

    /// JSONL for Mac/iPhone evidence collection. One event per line, sorted by time.
    public func exportJSONL() -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return snapshot().compactMap { try? encoder.encode($0) }
            .map { String(decoding: $0, as: UTF8.self) }.joined(separator: "\n")
    }

    public func resetForTesting() {
        lock.lock(); defer { lock.unlock() }
        events = []
    }
}
