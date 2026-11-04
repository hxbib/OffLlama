import Foundation

/// Instinct-style memory layer on top of `MemoryStore`: an always-injected profile one-pager, a tasks board, and a
/// background reconciliation pass. Memory stays read-only for the answering path; `consolidate()` is the only writer here.

public enum MemoryAttributes {
    public static let preference: Set<String> = ["likes", "dislikes", "prefers", "preference", "favorite", "hobby"]
    public static let autonomy: Set<String> = ["autonomy", "always_confirm", "never_confirm", "ask_before"]
    public static let style: Set<String> = ["communication_style", "tone", "style", "language", "reply_length"]
    public static let tasks: Set<String> = ["todo", "task", "reminder"]
    public static let shopping: Set<String> = ["needs_to_buy"]
    /// Never included in the profile sent to the cloud (`redactSensitive: true`).
    public static let sensitive: Set<String> = ["allergy", "health", "medication", "diagnosis", "condition", "phone", "address",
                                                "password", "pin", "salary", "bank", "account", "ssn"]
}

/// One fact-disclosure policy for every memory representation: local prompts keep everything, cloud-bound
/// profile/retrieval/correction text keeps only facts that pass the existing attribute set and lexical hint.
enum MemoryDisclosure: Sendable, Equatable {
    case local
    case cloud

    func admits(_ fact: MemoryFact) -> Bool {
        switch self {
        case .local: return true
        case .cloud: return !Self.isSensitive(fact)
        }
    }

    /// Both sides of a rendered correction must pass: the old value is transmitted too.
    func admits(correction old: MemoryFact, _ new: MemoryFact) -> Bool {
        admits(old) && admits(new)
    }

    /// Checks every field the profile/retrieval renderer can expose. The attribute is checked with underscores
    /// replaced by spaces because that is how the profile renders it.
    static func isSensitive(_ fact: MemoryFact) -> Bool {
        if MemoryAttributes.sensitive.contains(fact.attribute) { return true }
        let attribute = fact.attribute.replacingOccurrences(of: "_", with: " ")
        return SensitivityHint.matches(fact.subject)
            || SensitivityHint.matches(fact.value)
            || SensitivityHint.matches(fact.text)
            || SensitivityHint.matches(attribute)
            || fact.aliases.contains { SensitivityHint.matches($0) }
    }

    /// The retrieved-memory block for `Assistant`. Local is byte-for-byte the previous rendering.
    func render(_ facts: [MemoryFact]) -> String {
        let shown = facts.filter(admits)
        guard !shown.isEmpty else { return "" }
        return "Known about the user:\n" + shown.map { "- " + $0.text }.joined(separator: "\n") + "\n"
    }
}

public struct ConsolidationReport: Sendable, Equatable {
    public var purgedExpired = 0, deduplicated = 0, superseded = 0, evicted = 0
    public var total: Int { purgedExpired + deduplicated + superseded + evicted }
}

public struct TaskBoard: Sendable, Equatable {
    public struct Item: Sendable, Equatable { public let fact: MemoryFact; public let due: Date? }
    public var dueSoon: [Item] = [], open: [Item] = [], shopping: [Item] = []
    public init(dueSoon: [Item] = [], open: [Item] = [], shopping: [Item] = []) { self.dueSoon = dueSoon; self.open = open; self.shopping = shopping }
    public var isEmpty: Bool { dueSoon.isEmpty && open.isEmpty && shopping.isEmpty }
    public var text: String {
        guard !isEmpty else { return "" }
        var s = "Tasks board"
        for (title, items) in [("Due soon", dueSoon), ("Open", open), ("Shopping", shopping)] where !items.isEmpty {
            s += "\n\(title):"
            for i in items { s += "\n- [ ] \(i.fact.value)" + (i.due.map { " (by \(MemoryStore.day($0)))" } ?? "") }
        }
        return s
    }
}

extension MemoryStore {
    static func day(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        return f.string(from: d)
    }

    /// Every stored decision correction, newest first (autonomy calibration source).
    public func decisionCorrections(limit: Int = 200) throws -> [DecisionCorrection] {
        try db.query("SELECT id,decision_type,context,wrong_id,correct_id,created FROM corrections ORDER BY id DESC LIMIT ?", [.int(Int64(limit))]).map {
            DecisionCorrection(id: $0["id"]?.int ?? 0, decisionType: $0["decision_type"]?.text ?? "", context: $0["context"]?.text ?? "",
                               wrongID: $0["wrong_id"]?.text ?? "", correctID: $0["correct_id"]?.text ?? "",
                               createdAt: Date(timeIntervalSince1970: $0["created"]?.double ?? 0))
        }
    }

    /// Named subjects, aliases, and person-valued profile attributes for outbound masking.
    public func entityNames() throws -> [String] {
        let names = try active().flatMap { fact -> [String] in
            var names = fact.subject == "user" ? fact.aliases : [fact.subject] + fact.aliases
            if ["partner", "name"].contains(fact.attribute.lowercased()) { names.append(fact.value) }
            return names
        }
        return Array(Set(names.filter { $0.count > 1 })).sorted()
    }

    /// The always-injected profile ("one-pager"): life context, autonomy calibration, communication style, preferences,
    /// dated corrections, entity index with aliases, open tasks. Sections in priority order; the result never exceeds
    /// `maxChars` (keeps a 1B context small). Empty string when nothing is known.
    /// `redactSensitive` drops health/money/credential facts (attribute list or any rendered field matching
    /// `SensitivityHint`) and decision corrections: used for the escalation prompt, which is scrubbed again before
    /// it leaves the device. Local rendering (`false`) keeps every fact.
    public func profileOnePager(maxChars: Int = 600, redactSensitive: Bool = false) throws -> String {
        let disclosure: MemoryDisclosure = redactSensitive ? .cloud : .local
        let act = try active().filter { disclosure.admits($0) }
        let user = act.filter { $0.subject == "user" }
        func group(_ fs: [MemoryFact]) -> String {
            var order: [String] = [], vals: [String: [String]] = [:]
            for f in fs.sorted(by: { ($0.createdAt.timeIntervalSince1970, $0.id) < ($1.createdAt.timeIntervalSince1970, $1.id) }) {
                if vals[f.attribute] == nil { order.append(f.attribute) }
                vals[f.attribute, default: []].append(f.value)
            }
            return order.map { "\($0.replacingOccurrences(of: "_", with: " ")) \(vals[$0]!.joined(separator: ", "))" }.joined(separator: "; ")
        }
        let special = MemoryAttributes.preference.union(MemoryAttributes.autonomy).union(MemoryAttributes.style)
            .union(MemoryAttributes.tasks).union(MemoryAttributes.shopping)
        var lines: [String] = []
        let life = group(user.filter { !special.contains($0.attribute) && $0.attribute != "upcoming_trip" } + user.filter { $0.attribute == "upcoming_trip" })
        if !life.isEmpty { lines.append("Life context: " + life) }

        var autonomy = user.filter { MemoryAttributes.autonomy.contains($0.attribute) }.map(\.value)
        let corr = redactSensitive ? [] : try decisionCorrections()
        var seen: [String: (n: Int, latest: Date)] = [:], order: [String] = []
        for c in corr {
            let key = "\(c.decisionType): \(c.correctID) not \(c.wrongID)"
            if seen[key] == nil { order.append(key); seen[key] = (0, c.createdAt) }
            seen[key]!.n += 1
        }
        autonomy += order.map { "\($0) (\(seen[$0]!.n)x, last \(Self.day(seen[$0]!.latest)))" }
        if !autonomy.isEmpty { lines.append("Autonomy: " + autonomy.joined(separator: "; ")) }

        let style = group(user.filter { MemoryAttributes.style.contains($0.attribute) })
        if !style.isEmpty { lines.append("Style: " + style) }
        let prefs = group(user.filter { MemoryAttributes.preference.contains($0.attribute) })
        if !prefs.isEmpty { lines.append("Preferences: " + prefs) }

        let ids = Set(act.map(\.id))
        let fixes = try corrections(limit: 5).filter { ids.contains($0.new.id) && disclosure.admits(correction: $0.old, $0.new) }
        if !fixes.isEmpty {
            lines.append("Corrected by you: " + fixes.map { "\(Self.day($0.new.createdAt)) \($0.new.attribute.replacingOccurrences(of: "_", with: " ")) \($0.old.value) -> \($0.new.value)" }.joined(separator: "; "))
        }

        var entOrder: [String] = [], ent: [String: [MemoryFact]] = [:]
        for f in act.sorted(by: { ($0.createdAt.timeIntervalSince1970, $0.id) < ($1.createdAt.timeIntervalSince1970, $1.id) })
            where f.subject != "user" && !MemoryAttributes.tasks.contains(f.attribute) {
            if ent[f.subject] == nil { entOrder.append(f.subject) }
            ent[f.subject, default: []].append(f)
        }
        if !entOrder.isEmpty {
            lines.append("People & places: " + entOrder.map { s -> String in
                let fs = ent[s]!
                let aka = Set(fs.flatMap(\.aliases)).sorted()
                return s.capitalized + (aka.isEmpty ? "" : " (aka \(aka.joined(separator: ", ")))") + ": " + fs.map { "\($0.attribute.replacingOccurrences(of: "_", with: " ")) \($0.value)" }.joined(separator: ", ")
            }.joined(separator: " | "))
        }
        let board = redactSensitive ? TaskBoard() : try tasksBoard()
        let open = (board.dueSoon + board.open + board.shopping).map(\.fact.value)
        if !open.isEmpty { lines.append("Open tasks: " + open.joined(separator: "; ")) }
        guard !lines.isEmpty else { return "" }

        var out = "Profile (as of \(Self.day(clock()))):"
        guard out.count < maxChars else { return String(out.prefix(max(0, maxChars))) }
        for l in lines {
            let room = maxChars - out.count - 1
            if room <= 12 { break }
            out += "\n" + (l.count <= room ? l : String(l.prefix(room - 1)) + "…")
        }
        return out
    }

    /// To-dos, reminders and shopping items kept in memory, as a board. "Due soon" = expiring within `soon`.
    public func tasksBoard(soon: TimeInterval = 2 * 86_400) throws -> TaskBoard {
        let now = clock()
        var b = TaskBoard()
        for f in try active().sorted(by: { ($0.createdAt.timeIntervalSince1970, $0.id) < ($1.createdAt.timeIntervalSince1970, $1.id) }) {
            let item = TaskBoard.Item(fact: f, due: f.expiresAt)
            if MemoryAttributes.shopping.contains(f.attribute) { b.shopping.append(item) }
            else if MemoryAttributes.tasks.contains(f.attribute) {
                if let d = f.expiresAt, d.timeIntervalSince(now) <= soon { b.dueSoon.append(item) } else { b.open.append(item) }
            }
        }
        return b
    }

    /// "Peanuts." / "the  peanut" -> "peanut": case, whitespace, trailing punctuation, leading article, plural -s.
    static func normalizedValue(_ v: String) -> String {
        var w = v.lowercased().split { $0.isWhitespace }.map(String.init)
        if let f = w.first, ["a", "an", "the", "some"].contains(f), w.count > 1 { w.removeFirst() }
        var s = w.joined(separator: " ").trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
        if s.count > 3, s.hasSuffix("s"), !s.hasSuffix("ss") { s.removeLast() }
        return s
    }

    /// Background reconciliation (Instinct's daily "dreaming" pass, no LLM): purge expired rows, merge exact/near-duplicate
    /// facts (same subject + attribute + normalized value; keeps the most trusted, then newest, and merges aliases),
    /// supersede older values of single-valued attributes with the most recently stated one (kept in history as a dated correction),
    /// then enforce the budget.
    @discardableResult public func consolidate() throws -> ConsolidationReport {
        var r = ConsolidationReport()
        r.purgedExpired = try purgeExpired()
        let act = try active()
        try db.transaction {
            var groups: [String: [MemoryFact]] = [:]
            for f in act { groups["\(f.subject)\u{1}\(f.attribute)\u{1}\(Self.normalizedValue(f.value))", default: []].append(f) }
            var removed = Set<Int64>()
            var lastSaid: [Int64: Double] = [:]     // merged "last stated" time of kept duplicates
            for (_, g) in groups where g.count > 1 {
                let keep = g.max { (MemoryProvenance.trust($0.provenance), $0.updatedAt.timeIntervalSince1970, $0.id) <
                                   (MemoryProvenance.trust($1.provenance), $1.updatedAt.timeIntervalSince1970, $1.id) }!
                let updated = g.map(\.updatedAt).max()!
                let created = g.map(\.createdAt).min()!
                lastSaid[keep.id] = updated.timeIntervalSince1970
                let aliases = Self.normAliases(g.flatMap(\.aliases))
                try db.run("UPDATE facts SET updated=?, created=?, aliases=? WHERE id=?",
                           [.double(updated.timeIntervalSince1970), .double(created.timeIntervalSince1970), .text(aliases.joined(separator: "|")), .int(keep.id)])
                for d in g where d.id != keep.id {
                    try db.run("UPDATE facts SET superseded_by=? WHERE superseded_by=?", [.int(keep.id), .int(d.id)])
                    try db.run("DELETE FROM facts WHERE id=?", [.int(d.id)]); removed.insert(d.id); r.deduplicated += 1
                }
            }
            var single: [String: [MemoryFact]] = [:]
            for f in act where !removed.contains(f.id) && singleValuedAttributes.contains(f.attribute) {
                single["\(f.subject)\u{1}\(f.attribute)", default: []].append(f)
            }
            for (_, g) in single where g.count > 1 {
                func said(_ f: MemoryFact) -> Double { lastSaid[f.id] ?? f.updatedAt.timeIntervalSince1970 }
                let newest = g.max { (said($0), $0.id) < (said($1), $1.id) }!   // most recently stated wins
                for o in g where o.id != newest.id {
                    try db.run("UPDATE facts SET superseded_by=? WHERE id=?", [.int(newest.id), .int(o.id)]); r.superseded += 1
                }
            }
        }
        r.evicted = try enforceBudget().count
        try setMeta("last_consolidated", String(clock().timeIntervalSince1970))
        return r
    }

    public var lastConsolidated: Date? { (try? meta("last_consolidated")).flatMap { $0 }.flatMap(Double.init).map { Date(timeIntervalSince1970: $0) } }

    /// Run `consolidate()` at most once per `interval` (default daily). Returns nil when not due.
    @discardableResult public func consolidateIfDue(interval: TimeInterval = 86_400) throws -> ConsolidationReport? {
        if let last = lastConsolidated, clock().timeIntervalSince(last) < interval { return nil }
        return try consolidate()
    }
}
