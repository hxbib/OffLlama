import Foundation

/// Triggers delivered by iOS Shortcuts personal automations -> App Intent -> `ProactiveEngine.handle`.
public enum TriggerKind: String, Codable, CaseIterable, Sendable {
    case time, arrive, leave, email, message, charger
    case morning   // daily brief (Shortcuts "Time of Day" automation): tasks board + today's events, gated by nudgeNow
}

public struct Trigger: Codable, Sendable, Equatable {
    public var kind: TriggerKind
    public var date: Date
    public var place: String?     // arrive/leave
    public var sender: String?    // email/message
    public var text: String?      // email subject / message body
    public init(kind: TriggerKind, date: Date, place: String? = nil, sender: String? = nil, text: String? = nil) {
        self.kind = kind; self.date = date; self.place = place; self.sender = sender; self.text = text
    }
    public var summary: String {
        var s = "Trigger: \(kind.rawValue) at \(ISO8601DateFormatter().string(from: date))"
        if let p = place { s += ", place: \(p)" }
        if let x = sender { s += ", from: \(x)" }
        if let t = text { s += ", content: \(t)" }
        return s
    }
}

public struct Nudge: Sendable, Equatable {
    public let title: String
    public let body: String
    public let factIDs: [Int64]
    public let confidence: Double
}

/// Deterministic pre-filter rules: cheap, explainable, decide *which memories are candidates* for a trigger.
public struct ProactiveRule: Sendable {
    public let name: String
    public let kinds: Set<TriggerKind>
    public let match: @Sendable (Trigger, MemoryFact) -> Bool
    public let render: @Sendable (Trigger, MemoryFact) -> Nudge
}

public enum ProactiveRules {
    static func n(_ t: String, _ b: String, _ f: MemoryFact) -> Nudge { Nudge(title: t, body: b, factIDs: [f.id], confidence: 0) }

    public static let defaults: [ProactiveRule] = [
        ProactiveRule(name: "shopping-on-arrival", kinds: [.arrive],
            match: { t, f in f.attribute == "needs_to_buy" && (t.place ?? "").range(of: #"store|market|grocery|shop|costco|target|trader|whole foods|pharmacy"#, options: [.regularExpression, .caseInsensitive]) != nil },
            render: { t, f in n("You're at \(t.place ?? "the store")", "You said you're out of \(f.value).", f) }),
        ProactiveRule(name: "promise-when-messaged", kinds: [.message, .email],
            match: { t, f in f.attribute == "promise" && (t.sender ?? "").lowercased().contains(f.subject) },
            render: { t, f in n("\(t.sender ?? f.subject.capitalized) just wrote", "Heads-up: you owe \(f.subject.capitalized) \(f.value).", f) }),
        ProactiveRule(name: "birthday-soon", kinds: [.time, .charger, .morning],
            match: { t, f in f.attribute == "birthday" && f.subject != "user" && ProactiveRules.isWithin(days: 3, of: f.value, from: t.date) },
            render: { _, f in n("\(f.subject.capitalized)'s birthday", "\(f.subject.capitalized)'s birthday is \(f.value). Want a reminder to send something?", f) }),
        ProactiveRule(name: "trip-prep-overnight", kinds: [.charger, .time],
            match: { _, f in f.attribute == "upcoming_trip" },
            render: { _, f in n("Trip to \(f.value)", "Want me to set a packing reminder for your trip to \(f.value)?", f) }),
    ]

    /// Parses "March 3" / "Nov 5th" and checks if it falls within `days` after `from` (local calendar).
    public static func isWithin(days: Int, of monthDay: String, from: Date, calendar: Calendar = .current) -> Bool {
        let clean = monthDay.replacingOccurrences(of: #"(st|nd|rd|th)$"#, with: "", options: .regularExpression)
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = calendar; f.timeZone = calendar.timeZone
        for fmt in ["MMMM d", "MMM d"] {
            f.dateFormat = fmt
            guard let md = f.date(from: clean) else { continue }
            let c = calendar.dateComponents([.month, .day], from: md)
            for off in 0...days {
                let d = calendar.date(byAdding: .day, value: off, to: from)!
                let dc = calendar.dateComponents([.month, .day], from: d)
                if dc.month == c.month && dc.day == c.day { return true }
            }
            return false
        }
        return false
    }
}

/// Rule pre-filter -> Reflex `nudgeNow` decision -> nudge (or nothing). Every decision is logged by Reflex.
public final class ProactiveEngine: @unchecked Sendable {
    let memory: MemoryStore
    let reflex: Reflex?
    let rules: [ProactiveRule]
    /// Today's calendar lines for the morning brief (EventKit on iOS). nil = no calendar.
    public var todayEvents: (@Sendable (Date) async throws -> [String])? = nil

    public init(memory: MemoryStore, reflex: Reflex?, rules: [ProactiveRule] = ProactiveRules.defaults) {
        self.memory = memory; self.reflex = reflex; self.rules = rules
    }

    /// Morning brief: tasks board + today's events, delivered at most once per local day and only if the Reflex
    /// `nudgeNow` decision says "nudge" (a "later"/"skip" or a below-tau fallback lets a later trigger retry).
    public func morningBrief(_ t: Trigger) async throws -> Nudge? {
        let day = MemoryStore.day(t.date)
        if try memory.meta("last_morning_brief") == day { return nil }
        let board = try memory.tasksBoard()
        let events = (try? await todayEvents?(t.date)) ?? []
        var parts: [String] = []
        if !events.isEmpty { parts.append("Today: " + events.prefix(4).joined(separator: "; ")) }
        for (label, items) in [("Due soon", board.dueSoon), ("To do", board.open), ("Buy", board.shopping)] where !items.isEmpty {
            parts.append("\(label): " + items.prefix(4).map(\.fact.value).joined(separator: "; "))
        }
        guard !parts.isEmpty else { return nil }
        let body = parts.joined(separator: "\n")
        var conf = 0.0
        if let reflex {
            let d = try await reflex.decide(OptionSets.nudgeNow, context: "\(t.summary)\nMemory: \(parts.joined(separator: "; "))\nDraft nudge: morning brief")
            guard d.chosen.id == "nudge" else { return nil }
            conf = d.confidence
        }
        try memory.setMeta("last_morning_brief", day)
        return Nudge(title: "Good morning", body: body, factIDs: (board.dueSoon + board.open + board.shopping).map(\.fact.id), confidence: conf)
    }

    public func handle(_ t: Trigger) async throws -> [Nudge] {
        var out: [Nudge] = []
        if t.kind == .morning, let b = try await morningBrief(t) { out.append(b) }
        for f in try memory.active() {
            for r in rules where r.kinds.contains(t.kind) && r.match(t, f) {
                let draft = r.render(t, f)
                guard let reflex else { out.append(draft); continue }
                let d = try await reflex.decide(OptionSets.nudgeNow, context: "\(t.summary)\nMemory: \(f.text)\nDraft nudge: \(draft.body)")
                if d.chosen.id == "nudge" { out.append(Nudge(title: draft.title, body: draft.body, factIDs: draft.factIDs, confidence: d.confidence)) }
            }
        }
        return out
    }
}
