import Foundation

public protocol Embedder: Sendable {
    var name: String { get }
    var dimension: Int { get }
    func embed(_ text: String) async throws -> [Float]
}

/// Offline baseline embedder: hashed character trigrams + word unigrams, L2-normalized.
/// Zero download, deterministic; replaced on device by a real small embedding model when present.
public struct HashingEmbedder: Embedder {
    public let name = "hash-trigram-256"
    public let dimension: Int
    public init(dimension: Int = 256) { self.dimension = dimension }
    public func embed(_ text: String) async throws -> [Float] { Self.vector(text, dimension) }

    static func fnv(_ s: Substring) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return h
    }
    static func vector(_ text: String, _ d: Int) -> [Float] {
        var v = [Float](repeating: 0, count: d)
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }
        for w in words {
            v[Int(fnv(w) % UInt64(d))] += 2
            let padded = "#" + w + "#"
            let chars = Array(padded)
            if chars.count >= 3 { for i in 0...(chars.count - 3) { v[Int(fnv(Substring(String(chars[i..<i+3]))) % UInt64(d))] += 1 } }
        }
        let n = sqrt(v.reduce(0) { $0 + $1 * $1 })
        return n > 0 ? v.map { $0 / n } : v
    }
}

public func cosine(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count, !a.isEmpty else { return 0 }
    var d: Float = 0, na: Float = 0, nb: Float = 0
    for i in a.indices { d += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
    return na > 0 && nb > 0 ? d / (na.squareRoot() * nb.squareRoot()) : 0
}

public struct MemoryFact: Sendable, Equatable, Identifiable {
    public var id: Int64
    public var subject: String     // "user" or a person/place name, lowercased
    public var attribute: String   // e.g. "lives_in", "allergy", "birthday", "likes"
    public var value: String
    public var text: String        // natural-language statement
    public var createdAt: Date
    public var updatedAt: Date
    public var expiresAt: Date?
    public var supersededBy: Int64?
    /// Where the fact came from (CURATOR-style provenance, arXiv 2606.25115): user_stated, model_extracted, user_correction, cloud, import.
    public var provenance: String = MemoryProvenance.userStated
    /// Other names for this fact's entity (subject), lowercased: "mom", "my mother", "prof lee". Used by keyword retrieval.
    public var aliases: [String] = []
    public var isActive: Bool { supersededBy == nil }
}

/// Candidate fact before storage (from the rule extractor or the on-device model).
public struct ExtractedFact: Sendable, Equatable {
    public var subject: String, attribute: String, value: String, text: String
    public var ttl: TimeInterval?
    public var provenance: String
    public var aliases: [String]
    public init(subject: String, attribute: String, value: String, text: String, ttl: TimeInterval? = nil,
                provenance: String = MemoryProvenance.userStated, aliases: [String] = []) {
        self.subject = subject.lowercased(); self.attribute = attribute; self.value = value; self.text = text; self.ttl = ttl
        self.provenance = provenance; self.aliases = MemoryStore.normAliases(aliases)
    }
}

/// Attributes where one value replaces another (single-valued). Multi-valued attributes (likes, allergy) keep both
/// unless a resolver says otherwise.
public let singleValuedAttributes: Set<String> = ["lives_in", "works_at", "birthday", "job", "partner", "phone", "diet", "gym_time", "name"]

public enum MemoryProvenance {
    public static let userStated = "user_stated", modelExtracted = "model_extracted", userCorrection = "user_correction",
                      cloud = "cloud", imported = "import"
    /// Eviction protection order (higher = kept longer). Unknown provenance is treated as least trusted.
    public static func trust(_ p: String) -> Int {
        switch p { case userCorrection: return 4; case userStated: return 3; case modelExtracted: return 2; case cloud: return 1; default: return 0 }
    }
}

/// A user correction of a Reflex decision, stored as a retrievable experience row and fed back into the Reflex prompt.
public struct DecisionCorrection: Sendable, Equatable {
    public var id: Int64, decisionType: String, context: String, wrongID: String, correctID: String, createdAt: Date
}

public enum ConflictResolution: String, Sendable { case update, keepBoth = "keep_both", ignoreNew = "ignore_new" }

/// Thread-safety: every SQL statement goes through `SQLiteDB`, which serializes on one lock (and the connection is opened
/// FULLMUTEX), so concurrent calls never race on the handle. `upsert` reads existing facts, awaits the resolver, then writes
/// in a transaction; two concurrent upserts of the same subject+attribute could both insert. The app calls it from one
/// turn at a time (Assistant.handle is awaited serially from the main actor) and `consolidate()` merges any duplicates.
/// `budget`/`correctionBudget` are set at configuration time only.
public final class MemoryStore: @unchecked Sendable {
    let db: SQLiteDB
    let embedder: Embedder
    let clock: () -> Date
    /// Max active facts kept; beyond it the least-trusted, least-recently-updated rows are evicted (CURATOR budget). nil = unlimited.
    public var budget: Int?
    /// Max stored corrections (oldest evicted first).
    public var correctionBudget: Int

    public init(db: SQLiteDB, embedder: Embedder = HashingEmbedder(), clock: @escaping () -> Date = Date.init,
                budget: Int? = nil, correctionBudget: Int = 500) throws {
        self.db = db; self.embedder = embedder; self.clock = clock; self.budget = budget; self.correctionBudget = correctionBudget
        try db.exec("""
        CREATE TABLE IF NOT EXISTS facts(
          id INTEGER PRIMARY KEY AUTOINCREMENT, subject TEXT NOT NULL, attribute TEXT NOT NULL, value TEXT NOT NULL,
          text TEXT NOT NULL, created REAL NOT NULL, updated REAL NOT NULL, expires REAL, superseded_by INTEGER,
          embedding BLOB NOT NULL, embedder TEXT NOT NULL);
        CREATE INDEX IF NOT EXISTS facts_key ON facts(subject, attribute);
        CREATE TABLE IF NOT EXISTS corrections(
          id INTEGER PRIMARY KEY AUTOINCREMENT, decision_type TEXT NOT NULL, context TEXT NOT NULL, wrong_id TEXT NOT NULL,
          correct_id TEXT NOT NULL, created REAL NOT NULL, embedding BLOB NOT NULL);
        CREATE TABLE IF NOT EXISTS memory_meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
        """)
        // Migration for pre-provenance databases.
        let cols = try db.query("PRAGMA table_info(facts)").compactMap { $0["name"]?.text }
        if !cols.contains("provenance") { try db.exec("ALTER TABLE facts ADD COLUMN provenance TEXT NOT NULL DEFAULT 'user_stated'") }
        // Migration for pre-alias databases ("|"-separated, lowercased).
        if !cols.contains("aliases") { try db.exec("ALTER TABLE facts ADD COLUMN aliases TEXT NOT NULL DEFAULT ''") }
    }

    static func normAliases(_ a: [String]) -> [String] {
        var seen = Set<String>()
        return a.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.contains("|") && seen.insert($0).inserted }
    }

    /// All aliases recorded for an entity (union over its rows, including history).
    public func aliases(forSubject subject: String) throws -> [String] {
        let rows = try db.query("SELECT aliases FROM facts WHERE subject=? AND aliases != '' ORDER BY id", [.text(subject.lowercased())])
        return Self.normAliases(rows.flatMap { ($0["aliases"]?.text ?? "").split(separator: "|").map(String.init) })
    }

    /// Attach aliases to an entity: stored on every row of that subject so keyword retrieval finds any of them.
    /// No-op (returns []) when the entity has no facts yet.
    @discardableResult public func addAliases(_ new: [String], to subject: String) throws -> [String] {
        let merged = Self.normAliases(try aliases(forSubject: subject) + new)
        guard !merged.isEmpty else { return [] }
        try db.run("UPDATE facts SET aliases=? WHERE subject=?", [.text(merged.joined(separator: "|")), .text(subject.lowercased())])
        let has = try db.query("SELECT COUNT(*) AS n FROM facts WHERE subject=?", [.text(subject.lowercased())]).first?["n"]?.int ?? 0
        return has > 0 ? merged : []
    }

    func meta(_ key: String) throws -> String? { try db.query("SELECT value FROM memory_meta WHERE key=?", [.text(key)]).first?["value"]?.text }
    func setMeta(_ key: String, _ value: String) throws {
        try db.run("INSERT INTO memory_meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [.text(key), .text(value)])
    }

    /// Store a fact, handling contradictions. `resolver` is normally Reflex's memoryConflict decision.
    @discardableResult
    public func upsert(_ f: ExtractedFact,
                       resolver: ((MemoryFact, ExtractedFact) async throws -> ConflictResolution)? = nil) async throws -> (fact: MemoryFact?, resolution: ConflictResolution?) {
        let now = clock()
        let existing = try active().filter { $0.subject == f.subject && $0.attribute == f.attribute }
        if let same = existing.first(where: { $0.value.caseInsensitiveCompare(f.value) == .orderedSame }) {
            try db.run("UPDATE facts SET updated=?, expires=? WHERE id=?",
                       [.double(now.timeIntervalSince1970), f.ttl.map { .double(now.addingTimeInterval($0).timeIntervalSince1970) } ?? .null, .int(same.id)])
            if !f.aliases.isEmpty { try addAliases(f.aliases, to: f.subject) }
            return (try fact(id: same.id), .ignoreNew)
        }
        var resolution: ConflictResolution? = nil
        var toSupersede: [MemoryFact] = []
        if let old = existing.first {
            resolution = try await resolver?(old, f) ?? (singleValuedAttributes.contains(f.attribute) ? .update : .keepBoth)
            switch resolution! {
            case .ignoreNew: return (nil, .ignoreNew)
            case .update: toSupersede = singleValuedAttributes.contains(f.attribute) ? existing : [old]
            case .keepBoth: break
            }
        }
        let emb = try await embedder.embed(f.text)
        let bytes = emb.withUnsafeBufferPointer { Array(UnsafeRawBufferPointer($0)) }
        let aliases = Self.normAliases(try aliases(forSubject: f.subject) + f.aliases)
        let id = try db.transaction { () throws -> Int64 in
            let id = try db.run("INSERT INTO facts(subject,attribute,value,text,created,updated,expires,superseded_by,embedding,embedder,provenance,aliases) VALUES(?,?,?,?,?,?,?,NULL,?,?,?,?)",
                [.text(f.subject), .text(f.attribute), .text(f.value), .text(f.text), .double(now.timeIntervalSince1970),
                 .double(now.timeIntervalSince1970), f.ttl.map { .double(now.addingTimeInterval($0).timeIntervalSince1970) } ?? .null,
                 .blob(bytes), .text(embedder.name), .text(f.provenance), .text(aliases.joined(separator: "|"))])
            if !aliases.isEmpty { try db.run("UPDATE facts SET aliases=? WHERE subject=?", [.text(aliases.joined(separator: "|")), .text(f.subject)]) }
            for o in toSupersede { try db.run("UPDATE facts SET superseded_by=? WHERE id=?", [.int(id), .int(o.id)]) }
            return id
        }
        try enforceBudget(protecting: id)
        return (try fact(id: id), resolution)
    }

    /// Evict active facts over `budget`: lowest provenance trust first, then least recently updated. Returns evicted ids.
    @discardableResult public func enforceBudget(protecting keep: Int64? = nil) throws -> [Int64] {
        guard let budget else { return [] }
        let act = try active()
        guard act.count > budget else { return [] }
        let victims = act.filter { $0.id != keep }
            .sorted { (MemoryProvenance.trust($0.provenance), $0.updatedAt.timeIntervalSince1970) < (MemoryProvenance.trust($1.provenance), $1.updatedAt.timeIntervalSince1970) }
            .prefix(act.count - budget).map(\.id)
        try db.transaction { for v in victims { try forget(id: v) } }
        return Array(victims)
    }

    // MARK: corrections (experience memory for the Reflex)

    @discardableResult
    public func recordCorrection(type: DecisionType, context: String, wrongID: String, correctID: String) async throws -> Int64 {
        let emb = try await embedder.embed(context)
        let bytes = emb.withUnsafeBufferPointer { Array(UnsafeRawBufferPointer($0)) }
        let id = try db.run("INSERT INTO corrections(decision_type,context,wrong_id,correct_id,created,embedding) VALUES(?,?,?,?,?,?)",
                            [.text(type.rawValue), .text(context), .text(wrongID), .text(correctID), .double(clock().timeIntervalSince1970), .blob(bytes)])
        try db.run("DELETE FROM corrections WHERE id NOT IN (SELECT id FROM corrections ORDER BY id DESC LIMIT ?)", [.int(Int64(correctionBudget))])
        return id
    }

    /// Most similar past corrections for this decision type.
    public func corrections(for type: DecisionType, similarTo context: String, k: Int = 3, minScore: Float = 0.2) async throws -> [(correction: DecisionCorrection, score: Float)] {
        let q = try await embedder.embed(context)
        var out: [(DecisionCorrection, Float)] = []
        for r in try db.query("SELECT * FROM corrections WHERE decision_type=?", [.text(type.rawValue)]) {
            guard let b = r["embedding"]?.blob else { continue }
            let e: [Float] = b.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            let s = cosine(q, e)
            guard s >= minScore else { continue }
            out.append((DecisionCorrection(id: r["id"]?.int ?? 0, decisionType: r["decision_type"]?.text ?? "", context: r["context"]?.text ?? "",
                                           wrongID: r["wrong_id"]?.text ?? "", correctID: r["correct_id"]?.text ?? "",
                                           createdAt: Date(timeIntervalSince1970: r["created"]?.double ?? 0)), s))
        }
        return out.sorted { $0.1 == $1.1 ? $0.0.id > $1.0.id : $0.1 > $1.1 }.prefix(k).map { (correction: $0.0, score: $0.1) }
    }

    /// Context with retrieved corrections prepended, for `Reflex.decide(_:context:)` (test-time adaptation, no weight updates).
    public func reflexContext(for set: OptionSet, context: String, k: Int = 3) async throws -> String {
        let hits = try await corrections(for: set.type, similarTo: context, k: k)
        guard !hits.isEmpty else { return context }
        let lines = hits.map { h -> String in
            let ctx = h.correction.context.replacingOccurrences(of: "\n", with: " ")
            return "- \"\(ctx.prefix(160))\" -> correct: \(h.correction.correctID) (not \(h.correction.wrongID))"
        }
        return "Past user corrections for similar cases:\n" + lines.joined(separator: "\n") + "\n\n" + context
    }

    public func fact(id: Int64) throws -> MemoryFact? { try db.query("SELECT * FROM facts WHERE id=?", [.int(id)]).first.map(Self.decode) }

    /// Active = not superseded and not expired.
    public func active() throws -> [MemoryFact] {
        try db.query("SELECT * FROM facts WHERE superseded_by IS NULL AND (expires IS NULL OR expires > ?) ORDER BY updated DESC",
                     [.double(clock().timeIntervalSince1970)]).map(Self.decode)
    }
    public func history(subject: String, attribute: String) throws -> [MemoryFact] {
        try db.query("SELECT * FROM facts WHERE subject=? AND attribute=? ORDER BY id", [.text(subject.lowercased()), .text(attribute)]).map(Self.decode)
    }
    /// Recent corrections: an old fact superseded by a newer one (shown as "Corrected by you" in the Memory tab).
    public func corrections(limit: Int = 20) throws -> [(old: MemoryFact, new: MemoryFact)] {
        let olds = try db.query("SELECT * FROM facts WHERE superseded_by IS NOT NULL ORDER BY updated DESC LIMIT ?", [.int(Int64(limit))]).map(Self.decode)
        return try olds.compactMap { o in try fact(id: o.supersededBy!).map { (o, $0) } }
    }
    /// Remove this fact and the older revisions it replaced. A single statement also works inside budget eviction's transaction.
    public func forget(id: Int64) throws {
        try db.run("""
        WITH RECURSIVE forgotten(id) AS (
          SELECT id FROM facts WHERE id=?
          UNION
          SELECT facts.id FROM facts JOIN forgotten ON facts.superseded_by=forgotten.id
        )
        DELETE FROM facts WHERE id IN (SELECT id FROM forgotten)
        """, [.int(id)])
    }
    /// Physically delete expired rows.
    @discardableResult public func purgeExpired() throws -> Int {
        let now = clock().timeIntervalSince1970          // one cutoff for both statements, in one transaction
        return try db.transaction {
            let n = try db.query("SELECT COUNT(*) AS n FROM facts WHERE expires IS NOT NULL AND expires <= ?", [.double(now)]).first?["n"]?.int ?? 0
            try db.run("DELETE FROM facts WHERE expires IS NOT NULL AND expires <= ?", [.double(now)])
            return Int(n)
        }
    }

    /// Profile = the user's current single-valued attributes plus lists of multi-valued ones.
    public func profile() throws -> [String: [String]] {
        var p: [String: [String]] = [:]
        for f in try active() where f.subject == "user" { p[f.attribute, default: []].append(f.value) }
        return p
    }

    /// Hybrid retrieval: (cosine on embeddings + small word-overlap boost) unioned with grep-style keyword hits on the
    /// entity's aliases, its name and the fact value (Instinct-style). score = max(dense, keywordHit ? 0.6 : 0);
    /// ties break on the dense score, then recency.
    public func retrieve(_ query: String, k: Int = 5, minScore: Float = 0.15) async throws -> [(fact: MemoryFact, score: Float)] {
        let q = try await embedder.embed(query)
        let qWords = Set(query.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 })
        let rows = try db.query("SELECT * FROM facts WHERE superseded_by IS NULL AND (expires IS NULL OR expires > ?)", [.double(clock().timeIntervalSince1970)])
        let facts = rows.map(Self.decode)
        var entityAliases: [String: Set<String>] = [:]
        for f in facts { entityAliases[f.subject, default: []].formUnion(f.aliases) }
        let ql = " " + Self.words(query) + " "
        func hit(_ term: String, min: Int) -> Bool { let t = Self.words(term); return t.count >= min && ql.contains(" \(t) ") }
        var scored: [(MemoryFact, Float, Float)] = []
        for (r, f) in zip(rows, facts) {
            guard let b = r["embedding"]?.blob else { continue }
            let e: [Float] = b.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            let fw = Set((f.text + " " + f.subject + " " + f.value).lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
            let overlap = Float(qWords.intersection(fw).count)
            let dense = cosine(q, e) + 0.1 * overlap
            let keyword = (entityAliases[f.subject] ?? []).contains { hit($0, min: 2) } || (f.subject != "user" && hit(f.subject, min: 2)) || hit(f.value, min: 3)
            let s = keyword ? max(dense, 0.6) : dense
            if s >= minScore { scored.append((f, s, dense)) }
        }
        return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : ($0.2 != $1.2 ? $0.2 > $1.2 : $0.0.updatedAt > $1.0.updatedAt) }
            .prefix(k).map { (fact: $0.0, score: $0.1) }
    }

    static func words(_ s: String) -> String { s.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ") }

    static func decode(_ r: [String: SQLValue]) -> MemoryFact {
        MemoryFact(id: r["id"]?.int ?? 0, subject: r["subject"]?.text ?? "", attribute: r["attribute"]?.text ?? "",
                   value: r["value"]?.text ?? "", text: r["text"]?.text ?? "",
                   createdAt: Date(timeIntervalSince1970: r["created"]?.double ?? 0), updatedAt: Date(timeIntervalSince1970: r["updated"]?.double ?? 0),
                   expiresAt: r["expires"]?.double.map { Date(timeIntervalSince1970: $0) }, supersededBy: r["superseded_by"]?.int,
                   provenance: r["provenance"]?.text ?? MemoryProvenance.userStated,
                   aliases: (r["aliases"]?.text ?? "").split(separator: "|").map(String.init))
    }
}

/// Fast rule-based extractor (runs before / without the model). The model-based extractor in
/// `ModelFactExtractor` handles the long tail on device.
public enum RuleFactExtractor {
    struct Rule { let re: NSRegularExpression; let make: ([String]) -> ExtractedFact }
    static func r(_ p: String, _ make: @escaping ([String]) -> ExtractedFact) -> Rule {
        Rule(re: try! NSRegularExpression(pattern: p, options: [.caseInsensitive]), make: make)
    }
    static let day: TimeInterval = 86_400
    static let rules: [Rule] = [
        r(#"\bi (?:live|moved) (?:in|to) ([A-Za-z][A-Za-z .'-]{1,40}?)(?:[.,!]|$| now| since)"#) { .init(subject: "user", attribute: "lives_in", value: $0[1], text: "User lives in \($0[1])") },
        r(#"\bi work (?:at|for) ([A-Za-z0-9][A-Za-z0-9 &.'-]{1,40}?)(?:[.,!]|$| now| as)"#) { .init(subject: "user", attribute: "works_at", value: $0[1], text: "User works at \($0[1])") },
        r(#"\bi(?:'m| am) allergic to ([a-z][a-z -]{1,30}?)(?:[.,!]|$| and)"#) { .init(subject: "user", attribute: "allergy", value: $0[1], text: "User is allergic to \($0[1])") },
        r(#"\bi(?:'m| am) (vegetarian|vegan|pescatarian|gluten[- ]free|keto)\b"#) { .init(subject: "user", attribute: "diet", value: $0[1].lowercased(), text: "User is \($0[1].lowercased())") },
        r(#"\bi (?:really )?(?:love|like|enjoy) ([a-z][a-z -]{1,30}?)(?:[.,!]|$| and)"#) { .init(subject: "user", attribute: "likes", value: $0[1], text: "User likes \($0[1])") },
        r(#"\bmy (wife|husband|partner|girlfriend|boyfriend)(?:'s name)? is ([A-Z][a-z]+)"#) { .init(subject: "user", attribute: "partner", value: $0[2], text: "User's \($0[1]) is \($0[2])") },
        r(#"\b([A-Z][a-z]+)'s birthday is (?:on )?([A-Za-z]+ \d{1,2}(?:st|nd|rd|th)?)"#) { .init(subject: $0[1], attribute: "birthday", value: $0[2], text: "\($0[1])'s birthday is \($0[2])") },
        r(#"\bmy birthday is (?:on )?([A-Za-z]+ \d{1,2}(?:st|nd|rd|th)?)"#) { .init(subject: "user", attribute: "birthday", value: $0[1], text: "User's birthday is \($0[1])") },
        r(#"\bi (?:owe|promised) ([A-Z][a-z]+) (.{3,60}?)(?:[.!]|$)"#) { .init(subject: $0[1], attribute: "promise", value: $0[2], text: "User promised/owes \($0[1]) \($0[2])", ttl: 14 * day) },
        r(#"\bi(?:'m| am) (?:out of|running low on) ([a-z][a-z -]{1,30}?)(?:[.,!]|$| and)"#) { .init(subject: "user", attribute: "needs_to_buy", value: $0[1], text: "User needs to buy \($0[1])", ttl: 7 * day) },
        r(#"\b(?:add|put) (.{3,60}?) (?:to|on) my (?:to-?do|todo|task) list\b"#) { .init(subject: "user", attribute: "todo", value: $0[1], text: "To do: \($0[1])", ttl: 30 * day) },
        r(#"\bmy (mom|mother|dad|father|sister|brother|boss|roommate|landlord|professor|best friend)(?:'s name)? is ((?-i:[A-Z][a-z]+))\b"#) {
            .init(subject: $0[2], attribute: "relation", value: $0[1].lowercased(), text: "\($0[2]) is the user's \($0[1].lowercased())",
                  aliases: [$0[1], "my " + $0[1]]) },
        r(#"\bi(?:'m| am) (?:going to|flying to|traveling to|travelling to) ([A-Z][A-Za-z ]{1,30}?) (?:on|this|next|tomorrow)"#) { .init(subject: "user", attribute: "upcoming_trip", value: $0[1], text: "User is traveling to \($0[1])", ttl: 21 * day) },
    ]

    public static func extract(_ text: String) -> [ExtractedFact] {
        var out: [ExtractedFact] = []
        let ns = text as NSString
        for rule in rules {
            for m in rule.re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let groups = (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)).trimmingCharacters(in: .whitespaces) }
                out.append(rule.make(groups))
            }
        }
        return out
    }
}
