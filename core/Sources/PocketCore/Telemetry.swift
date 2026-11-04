import Foundation

/// One real System 1 decision. Never synthesize these: the reflex chart is built only from logged rows.
public struct DecisionRecord: Sendable, Equatable {
    public var id: Int64?
    public var timestamp: Date
    public var decisionType: DecisionType
    public var chosenID: String
    public var confidence: Double
    public var escalated: Bool
    public var latencyMs: Double
    public var model: String
    public var agreedWithTeacher: Bool?   // filled later by teacher spot-check / user correction
    public var source: String             // "device", "linux-e2e", "test"
    /// Decision context exactly as given to `Reflex.decide` (feeds the distillation queue). Stays on device.
    public var context: String? = nil
    /// Option ids of the set, in letter order (A, B, ...).
    public var optionIDs: [String]? = nil
    /// Student's calibrated probability per option id.
    public var probabilities: [String: Double]? = nil

    public init(id: Int64?, timestamp: Date, decisionType: DecisionType, chosenID: String, confidence: Double, escalated: Bool,
                latencyMs: Double, model: String, agreedWithTeacher: Bool?, source: String,
                context: String? = nil, optionIDs: [String]? = nil, probabilities: [String: Double]? = nil) {
        self.id = id; self.timestamp = timestamp; self.decisionType = decisionType; self.chosenID = chosenID
        self.confidence = confidence; self.escalated = escalated; self.latencyMs = latencyMs; self.model = model
        self.agreedWithTeacher = agreedWithTeacher; self.source = source
        self.context = context; self.optionIDs = optionIDs; self.probabilities = probabilities
    }
}

public struct DailyReflexShare: Sendable, Equatable {
    public let day: String          // yyyy-MM-dd (local)
    public let total: Int
    public let handledLocally: Int  // not escalated
    public var share: Double { total == 0 ? 0 : Double(handledLocally) / Double(total) }
    public let medianLatencyMs: Double
}

public final class TelemetryLog: @unchecked Sendable {
    let db: SQLiteDB
    public init(db: SQLiteDB) throws {
        self.db = db
        try db.exec("""
        CREATE TABLE IF NOT EXISTS decisions(
          id INTEGER PRIMARY KEY AUTOINCREMENT, ts REAL NOT NULL, type TEXT NOT NULL, chosen TEXT NOT NULL,
          confidence REAL NOT NULL, escalated INTEGER NOT NULL, latency_ms REAL NOT NULL, model TEXT NOT NULL,
          agreed_teacher INTEGER, source TEXT NOT NULL);
        CREATE INDEX IF NOT EXISTS decisions_ts ON decisions(ts);
        """)
        // Migration for pre-context databases (JSON text columns).
        let cols = try db.query("PRAGMA table_info(decisions)").compactMap { $0["name"]?.text }
        for c in ["context", "option_ids", "probabilities"] where !cols.contains(c) { try db.exec("ALTER TABLE decisions ADD COLUMN \(c) TEXT") }
    }

    static func json(_ v: Any?) -> SQLValue {
        guard let v, JSONSerialization.isValidJSONObject(v),
              let d = try? JSONSerialization.data(withJSONObject: v, options: [.sortedKeys]) else { return .null }
        return .text(String(decoding: d, as: UTF8.self))
    }
    static func unjson<T>(_ v: SQLValue?, as: T.Type) -> T? {
        guard let t = v?.text, let d = t.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? T
    }

    @discardableResult
    public func log(_ r: DecisionRecord) throws -> Int64 {
        try db.run("INSERT INTO decisions(ts,type,chosen,confidence,escalated,latency_ms,model,agreed_teacher,source,context,option_ids,probabilities) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
                   [.double(r.timestamp.timeIntervalSince1970), .text(r.decisionType.rawValue), .text(r.chosenID), .double(r.confidence),
                    .int(r.escalated ? 1 : 0), .double(r.latencyMs), .text(r.model),
                    r.agreedWithTeacher.map { .int($0 ? 1 : 0) } ?? .null, .text(r.source),
                    r.context.map { .text($0) } ?? .null, Self.json(r.optionIDs), Self.json(r.probabilities)])
    }

    public func markTeacherAgreement(id: Int64, agreed: Bool) throws {
        try db.run("UPDATE decisions SET agreed_teacher=? WHERE id=?", [.int(agreed ? 1 : 0), .int(id)])
    }

    /// Distillation queue: one JSON line per escalated decision (confidence < tau) in the last `sinceDays` days, with keys
    /// exactly {"id","type","context","option_ids","student_probs","confidence","ts","source"} (training/round2/ reads it;
    /// `ts` is ISO-8601 UTC). Privacy: this string/file stays on the device until the user shares it; nothing is uploaded.
    public func exportDistillationQueue(sinceDays: Int = 30, now: Date = Date()) throws -> String {
        let since = now.addingTimeInterval(-Double(max(0, sinceDays)) * 86_400).timeIntervalSince1970
        let iso = ISO8601DateFormatter()
        var out = ""
        for row in try db.query("SELECT * FROM decisions WHERE escalated=1 AND ts >= ? ORDER BY ts, id", [.double(since)]) {
            let r = Self.decode(row)
            let obj: [String: Any] = ["id": r.id ?? 0, "type": r.decisionType.rawValue, "context": r.context ?? NSNull(),
                                      "option_ids": r.optionIDs ?? [], "student_probs": r.probabilities ?? [:],
                                      "confidence": r.confidence, "ts": iso.string(from: r.timestamp), "source": r.source]
            let d = try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes])
            out += String(decoding: d, as: UTF8.self) + "\n"
        }
        return out
    }

    /// Teacher verdicts back from the labeling round: lines {"id": <decision id>, "agreed": true|false}. Bad lines are skipped.
    /// Returns how many rows were updated.
    @discardableResult public func importTeacherVerdicts(jsonl: String) throws -> Int {
        var n = 0
        for line in jsonl.split(whereSeparator: \.isNewline) {
            guard let o = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  let id = (o["id"] as? NSNumber)?.int64Value, let agreed = o["agreed"] as? Bool else { continue }
            guard try db.query("SELECT id FROM decisions WHERE id=?", [.int(id)]).first != nil else { continue }
            try markTeacherAgreement(id: id, agreed: agreed); n += 1
        }
        return n
    }

    public func recent(limit: Int = 50) throws -> [DecisionRecord] {
        try db.query("SELECT * FROM decisions ORDER BY ts DESC, id DESC LIMIT ?", [.int(Int64(limit))]).map(Self.decode)
    }

    public func all() throws -> [DecisionRecord] { try db.query("SELECT * FROM decisions ORDER BY ts, id").map(Self.decode) }

    /// Share of decisions handled by Reflex (not escalated) per local day. Feeds the Swift Charts view.
    public func dailyShare(calendar: Calendar = .current) throws -> [DailyReflexShare] {
        let f = DateFormatter(); f.calendar = calendar; f.timeZone = calendar.timeZone; f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        let groups = Dictionary(grouping: try all()) { f.string(from: $0.timestamp) }
        return groups.keys.sorted().map { d in
            let rs = groups[d]!
            let lat = rs.map(\.latencyMs).sorted()
            let med = lat.isEmpty ? 0 : (lat.count % 2 == 1 ? lat[lat.count / 2] : (lat[lat.count/2 - 1] + lat[lat.count/2]) / 2)
            return DailyReflexShare(day: d, total: rs.count, handledLocally: rs.filter { !$0.escalated }.count, medianLatencyMs: med)
        }
    }

    /// On-device share per model version ("distillation round"), in order of first use. The app ships each round
    /// as a new GGUF (model name), so rounds come straight from logged rows; nothing is synthesized.
    public func shareByModel() throws -> [(model: String, total: Int, handledLocally: Int)] {
        let rows = try db.query("SELECT model, MIN(ts) AS first, COUNT(*) AS n, SUM(CASE WHEN escalated=0 THEN 1 ELSE 0 END) AS loc FROM decisions GROUP BY model ORDER BY first")
        return rows.map { ($0["model"]?.text ?? "", Int($0["n"]?.int ?? 0), Int($0["loc"]?.int ?? 0)) }
    }

    /// CSV export (for the training loop and for the judges).
    public func csv() throws -> String {
        var s = "id,timestamp_iso,decision_type,chosen,confidence,escalated,latency_ms,model,agreed_with_teacher,source,context,option_ids\n"
        let iso = ISO8601DateFormatter()
        func q(_ v: String?) -> String { v.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" } ?? "" }   // RFC 4180 quoting
        for r in try all() {
            s += "\(r.id ?? 0),\(iso.string(from: r.timestamp)),\(r.decisionType.rawValue),\(r.chosenID),\(String(format: "%.4f", r.confidence)),\(r.escalated),\(String(format: "%.1f", r.latencyMs)),\(r.model),\(r.agreedWithTeacher.map { "\($0)" } ?? ""),\(r.source),\(q(r.context)),\(q(r.optionIDs?.joined(separator: "|")))\n"
        }
        return s
    }

    static func decode(_ row: [String: SQLValue]) -> DecisionRecord {
        DecisionRecord(id: row["id"]?.int, timestamp: Date(timeIntervalSince1970: row["ts"]?.double ?? 0),
                       decisionType: DecisionType(rawValue: row["type"]?.text ?? "") ?? .route,
                       chosenID: row["chosen"]?.text ?? "", confidence: row["confidence"]?.double ?? 0,
                       escalated: (row["escalated"]?.int ?? 0) != 0, latencyMs: row["latency_ms"]?.double ?? 0,
                       model: row["model"]?.text ?? "", agreedWithTeacher: row["agreed_teacher"]?.int.map { $0 != 0 },
                       source: row["source"]?.text ?? "", context: row["context"]?.text,
                       optionIDs: unjson(row["option_ids"], as: [String].self),
                       probabilities: unjson(row["probabilities"], as: [String: Any].self)?.compactMapValues { ($0 as? NSNumber)?.doubleValue })
    }
}
