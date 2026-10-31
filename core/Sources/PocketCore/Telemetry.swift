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
    }

    @discardableResult
    public func log(_ r: DecisionRecord) throws -> Int64 {
        try db.run("INSERT INTO decisions(ts,type,chosen,confidence,escalated,latency_ms,model,agreed_teacher,source) VALUES(?,?,?,?,?,?,?,?,?)",
                   [.double(r.timestamp.timeIntervalSince1970), .text(r.decisionType.rawValue), .text(r.chosenID), .double(r.confidence),
                    .int(r.escalated ? 1 : 0), .double(r.latencyMs), .text(r.model),
                    r.agreedWithTeacher.map { .int($0 ? 1 : 0) } ?? .null, .text(r.source)])
    }

    public func markTeacherAgreement(id: Int64, agreed: Bool) throws {
        try db.run("UPDATE decisions SET agreed_teacher=? WHERE id=?", [.int(agreed ? 1 : 0), .int(id)])
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

    /// CSV export (for the training loop and for the judges).
    public func csv() throws -> String {
        var s = "id,timestamp_iso,decision_type,chosen,confidence,escalated,latency_ms,model,agreed_with_teacher,source\n"
        let iso = ISO8601DateFormatter()
        for r in try all() {
            s += "\(r.id ?? 0),\(iso.string(from: r.timestamp)),\(r.decisionType.rawValue),\(r.chosenID),\(String(format: "%.4f", r.confidence)),\(r.escalated),\(String(format: "%.1f", r.latencyMs)),\(r.model),\(r.agreedWithTeacher.map { "\($0)" } ?? ""),\(r.source)\n"
        }
        return s
    }

    static func decode(_ row: [String: SQLValue]) -> DecisionRecord {
        DecisionRecord(id: row["id"]?.int, timestamp: Date(timeIntervalSince1970: row["ts"]?.double ?? 0),
                       decisionType: DecisionType(rawValue: row["type"]?.text ?? "") ?? .route,
                       chosenID: row["chosen"]?.text ?? "", confidence: row["confidence"]?.double ?? 0,
                       escalated: (row["escalated"]?.int ?? 0) != 0, latencyMs: row["latency_ms"]?.double ?? 0,
                       model: row["model"]?.text ?? "", agreedWithTeacher: row["agreed_teacher"]?.int.map { $0 != 0 },
                       source: row["source"]?.text ?? "")
    }
}
