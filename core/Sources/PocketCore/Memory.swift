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
    public var isActive: Bool { supersededBy == nil }
}

/// Candidate fact before storage (from the rule extractor or the on-device model).
public struct ExtractedFact: Sendable, Equatable {
    public var subject: String, attribute: String, value: String, text: String
    public var ttl: TimeInterval?
    public init(subject: String, attribute: String, value: String, text: String, ttl: TimeInterval? = nil) {
        self.subject = subject.lowercased(); self.attribute = attribute; self.value = value; self.text = text; self.ttl = ttl
    }
}

/// Attributes where one value replaces another (single-valued). Multi-valued attributes (likes, allergy) keep both
/// unless a resolver says otherwise.
public let singleValuedAttributes: Set<String> = ["lives_in", "works_at", "birthday", "job", "partner", "phone", "diet", "gym_time", "name"]

public enum ConflictResolution: String, Sendable { case update, keepBoth = "keep_both", ignoreNew = "ignore_new" }

public final class MemoryStore: @unchecked Sendable {
    let db: SQLiteDB
    let embedder: Embedder
    let clock: () -> Date

    public init(db: SQLiteDB, embedder: Embedder = HashingEmbedder(), clock: @escaping () -> Date = Date.init) throws {
        self.db = db; self.embedder = embedder; self.clock = clock
        try db.exec("""
        CREATE TABLE IF NOT EXISTS facts(
          id INTEGER PRIMARY KEY AUTOINCREMENT, subject TEXT NOT NULL, attribute TEXT NOT NULL, value TEXT NOT NULL,
          text TEXT NOT NULL, created REAL NOT NULL, updated REAL NOT NULL, expires REAL, superseded_by INTEGER,
          embedding BLOB NOT NULL, embedder TEXT NOT NULL);
        CREATE INDEX IF NOT EXISTS facts_key ON facts(subject, attribute);
        """)
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
        let id = try db.transaction { () throws -> Int64 in
            let id = try db.run("INSERT INTO facts(subject,attribute,value,text,created,updated,expires,superseded_by,embedding,embedder) VALUES(?,?,?,?,?,?,?,NULL,?,?)",
                [.text(f.subject), .text(f.attribute), .text(f.value), .text(f.text), .double(now.timeIntervalSince1970),
                 .double(now.timeIntervalSince1970), f.ttl.map { .double(now.addingTimeInterval($0).timeIntervalSince1970) } ?? .null,
                 .blob(bytes), .text(embedder.name)])
            for o in toSupersede { try db.run("UPDATE facts SET superseded_by=? WHERE id=?", [.int(id), .int(o.id)]) }
            return id
        }
        return (try fact(id: id), resolution)
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
    public func forget(id: Int64) throws { try db.run("DELETE FROM facts WHERE id=?", [.int(id)]) }
    /// Physically delete expired rows.
    @discardableResult public func purgeExpired() throws -> Int {
        let n = try db.query("SELECT COUNT(*) AS n FROM facts WHERE expires IS NOT NULL AND expires <= ?", [.double(clock().timeIntervalSince1970)]).first?["n"]?.int ?? 0
        try db.run("DELETE FROM facts WHERE expires IS NOT NULL AND expires <= ?", [.double(clock().timeIntervalSince1970)])
        return Int(n)
    }

    /// Profile = the user's current single-valued attributes plus lists of multi-valued ones.
    public func profile() throws -> [String: [String]] {
        var p: [String: [String]] = [:]
        for f in try active() where f.subject == "user" { p[f.attribute, default: []].append(f.value) }
        return p
    }

    /// Hybrid retrieval: cosine on embeddings + small keyword boost + recency tie-break.
    public func retrieve(_ query: String, k: Int = 5, minScore: Float = 0.15) async throws -> [(fact: MemoryFact, score: Float)] {
        let q = try await embedder.embed(query)
        let qWords = Set(query.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 })
        let rows = try db.query("SELECT * FROM facts WHERE superseded_by IS NULL AND (expires IS NULL OR expires > ?)", [.double(clock().timeIntervalSince1970)])
        var scored: [(MemoryFact, Float)] = []
        for r in rows {
            guard let b = r["embedding"]?.blob else { continue }
            let e: [Float] = b.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            let f = Self.decode(r)
            let fw = Set((f.text + " " + f.subject + " " + f.value).lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
            let overlap = Float(qWords.intersection(fw).count)
            let s = cosine(q, e) + 0.1 * overlap
            if s >= minScore { scored.append((f, s)) }
        }
        return scored.sorted { $0.1 == $1.1 ? $0.0.updatedAt > $1.0.updatedAt : $0.1 > $1.1 }.prefix(k).map { (fact: $0.0, score: $0.1) }
    }

    static func decode(_ r: [String: SQLValue]) -> MemoryFact {
        MemoryFact(id: r["id"]?.int ?? 0, subject: r["subject"]?.text ?? "", attribute: r["attribute"]?.text ?? "",
                   value: r["value"]?.text ?? "", text: r["text"]?.text ?? "",
                   createdAt: Date(timeIntervalSince1970: r["created"]?.double ?? 0), updatedAt: Date(timeIntervalSince1970: r["updated"]?.double ?? 0),
                   expiresAt: r["expires"]?.double.map { Date(timeIntervalSince1970: $0) }, supersededBy: r["superseded_by"]?.int)
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
