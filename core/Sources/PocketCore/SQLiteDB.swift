import Foundation
import CSQLite

public enum SQLValue: Equatable, Sendable {
    case null, int(Int64), double(Double), text(String), blob([UInt8])
    public var int: Int64? { if case .int(let v) = self { return v }; return nil }
    public var double: Double? { switch self { case .double(let v): return v; case .int(let v): return Double(v); default: return nil } }
    public var text: String? { if case .text(let v) = self { return v }; return nil }
    public var blob: [UInt8]? { if case .blob(let v) = self { return v }; return nil }
}

public struct SQLiteError: Error, CustomStringConvertible { public let description: String }

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Minimal, dependency-free SQLite wrapper (one connection, serialized by a lock).
public final class SQLiteDB: @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()

    /// `path` = ":memory:" for tests.
    public init(path: String) throws {
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw SQLiteError(description: "open failed: \(path)")
        }
        try exec("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;")
    }
    deinit { sqlite3_close(db) }

    public func exec(_ sql: String) throws {
        lock.lock(); defer { lock.unlock() }
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let m = err.map { String(cString: $0) } ?? "?"; sqlite3_free(err)
            throw SQLiteError(description: m)
        }
    }

    @discardableResult
    public func run(_ sql: String, _ args: [SQLValue] = []) throws -> Int64 {
        lock.lock(); defer { lock.unlock() }
        let st = try prepare(sql, args); defer { sqlite3_finalize(st) }
        let rc = sqlite3_step(st)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw SQLiteError(description: lastError) }
        return sqlite3_last_insert_rowid(db)
    }

    public func query(_ sql: String, _ args: [SQLValue] = []) throws -> [[String: SQLValue]] {
        lock.lock(); defer { lock.unlock() }
        let st = try prepare(sql, args); defer { sqlite3_finalize(st) }
        var rows: [[String: SQLValue]] = []
        while true {
            let rc = sqlite3_step(st)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw SQLiteError(description: lastError) }
            var row: [String: SQLValue] = [:]
            for i in 0..<sqlite3_column_count(st) {
                let name = String(cString: sqlite3_column_name(st, i))
                switch sqlite3_column_type(st, i) {
                case SQLITE_INTEGER: row[name] = .int(sqlite3_column_int64(st, i))
                case SQLITE_FLOAT: row[name] = .double(sqlite3_column_double(st, i))
                case SQLITE_TEXT: row[name] = .text(String(cString: sqlite3_column_text(st, i)))
                case SQLITE_BLOB:
                    let n = Int(sqlite3_column_bytes(st, i))
                    if let p = sqlite3_column_blob(st, i) { row[name] = .blob(Array(UnsafeRawBufferPointer(start: p, count: n))) } else { row[name] = .blob([]) }
                default: row[name] = .null
                }
            }
            rows.append(row)
        }
        return rows
    }

    public func transaction<T>(_ body: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        try exec("BEGIN IMMEDIATE")
        do { let r = try body(); try exec("COMMIT"); return r } catch { try? exec("ROLLBACK"); throw error }
    }

    private var lastError: String { String(cString: sqlite3_errmsg(db)) }

    private func prepare(_ sql: String, _ args: [SQLValue]) throws -> OpaquePointer? {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { throw SQLiteError(description: lastError + " in " + sql) }
        for (i, a) in args.enumerated() {
            let idx = Int32(i + 1)
            switch a {
            case .null: sqlite3_bind_null(st, idx)
            case .int(let v): sqlite3_bind_int64(st, idx, v)
            case .double(let v): sqlite3_bind_double(st, idx, v)
            case .text(let v): sqlite3_bind_text(st, idx, v, -1, SQLITE_TRANSIENT)
            case .blob(let v): v.withUnsafeBytes { _ = sqlite3_bind_blob(st, idx, $0.baseAddress, Int32(v.count), SQLITE_TRANSIENT) }
            }
        }
        return st
    }
}
