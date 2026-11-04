import Foundation

public struct RequestInputPolicy: Sendable, Equatable {
    public var ttl: TimeInterval
    public var cameraTTL: TimeInterval
    public var maxActive: Int
    public var maxTotalBytes: Int
    public var maxTextCharacters: Int
    public var maxVoiceBytes: Int
    public var maxCameraBytes: Int
    public var tombstoneRetention: TimeInterval
    public var previewCharacters: Int

    public init(ttl: TimeInterval = 24 * 60 * 60,
                cameraTTL: TimeInterval = 60 * 60,
                maxActive: Int = 8,
                maxTotalBytes: Int = 8 * 1024 * 1024,
                maxTextCharacters: Int = 24_000,
                maxVoiceBytes: Int = 2 * 1024 * 1024,
                maxCameraBytes: Int = 1024 * 1024,
                tombstoneRetention: TimeInterval = 30 * 24 * 60 * 60,
                previewCharacters: Int = 160) {
        self.ttl = ttl
        self.cameraTTL = cameraTTL
        self.maxActive = maxActive
        self.maxTotalBytes = maxTotalBytes
        self.maxTextCharacters = maxTextCharacters
        self.maxVoiceBytes = maxVoiceBytes
        self.maxCameraBytes = maxCameraBytes
        self.tombstoneRetention = tombstoneRetention
        self.previewCharacters = previewCharacters
    }

    public static let standard = RequestInputPolicy()
}

public enum RequestOrigin: String, Sendable, Codable, Equatable {
    case typed, share, voice, shortcut, camera
}

public enum RequestInputState: String, Sendable, Codable, Equatable {
    case staged, claimed, interrupted, completed, discarded, expired
}

public enum RequestInterruption: String, Sendable, Codable, Equatable {
    case appStopped, handleFailed, transcriptionFailed
}

public enum RequestInputBody: Sendable, Equatable {
    case text(String)
    case sharedText(utterance: String, text: String)
    case voice(wav: Data, duration: TimeInterval)
    case camera(jpeg: Data, question: String, concept: String?, mode: String, photoText: String)
}

public struct RequestInputSummary: Sendable, Equatable, Identifiable {
    public let id: UserRequestID
    public let origin: RequestOrigin
    public let preview: String
    public let byteCount: Int
    public let createdAt: Date
    public let expiresAt: Date
    public let state: RequestInputState
    public let interruption: RequestInterruption?

    public init(id: UserRequestID, origin: RequestOrigin, preview: String, byteCount: Int,
                createdAt: Date, expiresAt: Date, state: RequestInputState,
                interruption: RequestInterruption?) {
        self.id = id
        self.origin = origin
        self.preview = preview
        self.byteCount = byteCount
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.state = state
        self.interruption = interruption
    }
}

public struct ClaimedRequestInput: Sendable, Equatable {
    public let id: UserRequestID
    public let body: RequestInputBody
    public let origin: RequestOrigin
    public let transcript: String?
    public let createdAt: Date
    public let capturedTimeZoneID: String
    public let expiresAt: Date

    public init(id: UserRequestID, body: RequestInputBody, origin: RequestOrigin, transcript: String?,
                createdAt: Date, capturedTimeZoneID: String, expiresAt: Date) {
        self.id = id
        self.body = body
        self.origin = origin
        self.transcript = transcript
        self.createdAt = createdAt
        self.capturedTimeZoneID = capturedTimeZoneID
        self.expiresAt = expiresAt
    }
}

public enum RequestInputError: Error, Equatable, CustomStringConvertible {
    case alreadyExists
    case notFound
    case expired
    case alreadyClaimed
    case notResumable
    case notDiscardable
    case notOwner
    case recoveryRequired
    case transcriptAlreadySet
    case invalidPayload(String)
    case tooLarge
    case capacity
    case corrupt(String)
    case storage(String)
    case closed

    public var description: String {
        switch self {
        case .alreadyExists: return "request input already exists"
        case .notFound: return "request input not found"
        case .expired: return "request input expired"
        case .alreadyClaimed: return "request input is already claimed"
        case .notResumable: return "request input is not resumable"
        case .notDiscardable: return "request input is not discardable"
        case .notOwner: return "this store instance does not own the request input store"
        case .recoveryRequired: return "recover the request input store before processing requests"
        case .transcriptAlreadySet: return "request input transcript is already set"
        case .invalidPayload(let reason): return "invalid request input: \(reason)"
        case .tooLarge: return "request input is too large"
        case .capacity: return "request input store is at capacity"
        case .corrupt(let reason): return "request input is corrupt: \(reason)"
        case .storage(let reason): return "request input storage failed: \(reason)"
        case .closed: return "request input store is closed"
        }
    }
}

public final class RequestInputStore: @unchecked Sendable {
    public static let databaseFilename = "request-inputs.sqlite"

    private let gate = NSRecursiveLock()
    private let directory: URL
    private let policy: RequestInputPolicy
    private let nowProvider: () -> Date
    private var db: SQLiteDB?
    private var owner: RequestInputOwnerLock?
    private var closedFlag = false
    private var didRecover = false

    public var isExclusiveOwner: Bool {
        gate.lock(); defer { gate.unlock() }
        return !closedFlag && (owner?.isOwner ?? false)
    }

    public init(directory: URL, policy: RequestInputPolicy = .standard,
                now: @escaping () -> Date = Date.init) throws {
        let canonical = directory.standardizedFileURL.resolvingSymlinksInPath()
        self.directory = canonical
        self.policy = policy
        self.nowProvider = now
        do {
            try FileManager.default.createDirectory(at: canonical, withIntermediateDirectories: true)
            try Self.protectFiles(in: canonical)
            let lock = try RequestInputOwnerLock.acquire(canonicalDirectory: canonical)
            self.owner = lock
            let database = try SQLiteDB(path: canonical.appendingPathComponent(Self.databaseFilename).path)
            self.db = database
            try Self.protectFiles(in: canonical)
            try database.exec("PRAGMA journal_mode=DELETE; PRAGMA synchronous=FULL; PRAGMA secure_delete=ON; PRAGMA busy_timeout=5000;")
            try database.exec(Self.schema)
            try Self.protectFiles(in: canonical)
        } catch let error as RequestInputError {
            self.owner?.release()
            throw error
        } catch {
            self.owner?.release()
            throw RequestInputError.storage("could not open request input store")
        }
    }

    deinit {
        db = nil
        owner?.release()
    }

    public func close() {
        gate.lock(); defer { gate.unlock() }
        if closedFlag { return }
        closedFlag = true
        db = nil
        owner?.release()
    }

    private static let schema = """
    CREATE TABLE IF NOT EXISTS request_inputs (
      request_id TEXT PRIMARY KEY,
      state TEXT NOT NULL CHECK (state IN ('staged','claimed','interrupted','completed','discarded','expired')),
      origin TEXT NOT NULL CHECK (origin IN ('typed','share','voice','shortcut','camera')),
      payload_kind TEXT NOT NULL CHECK (payload_kind IN ('text','sharedText','voice','camera')),
      utterance TEXT,
      payload_text TEXT,
      payload_blob BLOB,
      voice_duration REAL,
      camera_concept TEXT,
      camera_mode TEXT,
      transcript TEXT,
      preview TEXT NOT NULL,
      byte_count INTEGER NOT NULL CHECK (byte_count >= 0),
      created REAL NOT NULL,
      expires REAL NOT NULL CHECK (expires > created),
      claimed_at REAL,
      updated REAL NOT NULL,
      interruption TEXT CHECK (interruption IS NULL OR interruption IN ('appStopped','handleFailed','transcriptionFailed')),
      captured_tz TEXT NOT NULL,
      CHECK (
        (state IN ('completed','discarded','expired')
          AND utterance IS NULL AND payload_text IS NULL AND payload_blob IS NULL
          AND voice_duration IS NULL AND camera_concept IS NULL AND camera_mode IS NULL
          AND transcript IS NULL AND preview = '' AND interruption IS NULL)
        OR
        (state IN ('staged','claimed','interrupted')
          AND (utterance IS NOT NULL OR payload_blob IS NOT NULL)
          AND (payload_kind <> 'text' OR utterance IS NOT NULL)
          AND (payload_kind <> 'sharedText' OR (utterance IS NOT NULL AND payload_text IS NOT NULL))
          AND (payload_kind <> 'voice' OR payload_blob IS NOT NULL)
          AND (payload_kind <> 'camera' OR (payload_blob IS NOT NULL AND utterance IS NOT NULL AND payload_text IS NOT NULL AND camera_mode IS NOT NULL)))
      ),
      CHECK ((state = 'interrupted' AND interruption IS NOT NULL) OR (state <> 'interrupted' AND interruption IS NULL)),
      CHECK (transcript IS NULL OR (payload_kind = 'voice' AND state IN ('claimed','interrupted')))
    );
    CREATE INDEX IF NOT EXISTS request_inputs_active ON request_inputs(state, created);
    CREATE TRIGGER IF NOT EXISTS request_inputs_identity_immutable
    BEFORE UPDATE OF origin, payload_kind, byte_count, created, expires, captured_tz ON request_inputs
    BEGIN SELECT RAISE(ABORT, 'request input identity is immutable'); END;
    CREATE TRIGGER IF NOT EXISTS request_inputs_body_immutable
    BEFORE UPDATE OF utterance, payload_text, payload_blob, voice_duration, camera_concept, camera_mode ON request_inputs
    WHEN NOT (NEW.utterance IS NULL AND NEW.payload_text IS NULL AND NEW.payload_blob IS NULL
              AND NEW.voice_duration IS NULL AND NEW.camera_concept IS NULL AND NEW.camera_mode IS NULL)
    BEGIN SELECT RAISE(ABORT, 'request input body is immutable'); END;
    CREATE TRIGGER IF NOT EXISTS request_inputs_transcript_write_once
    BEFORE UPDATE OF transcript ON request_inputs
    WHEN OLD.transcript IS NOT NULL AND NEW.transcript IS NOT NULL
    BEGIN SELECT RAISE(ABORT, 'request input transcript is write-once'); END;
    CREATE TRIGGER IF NOT EXISTS request_inputs_state_transitions
    BEFORE UPDATE OF state ON request_inputs
    WHEN NOT (
      NEW.state = OLD.state
      OR (OLD.state = 'staged' AND NEW.state IN ('claimed','discarded','expired'))
      OR (OLD.state = 'claimed' AND NEW.state IN ('completed','interrupted'))
      OR (OLD.state = 'interrupted' AND NEW.state IN ('claimed','discarded','expired'))
    )
    BEGIN SELECT RAISE(ABORT, 'request input state transition is not allowed'); END;
    """

    private static func protectFiles(in directory: URL) throws {
        try applyFileProtection(to: directory)
        for name in [databaseFilename, databaseFilename + "-journal", databaseFilename + "-wal", databaseFilename + "-shm", "owner.lock"] {
            let url = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { try applyFileProtection(to: url) }
        }
    }

    private static func applyFileProtection(to url: URL) throws {
        #if os(iOS) || os(tvOS) || os(watchOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let protection = (attributes[.protectionKey] as? FileProtectionType)?.rawValue
            ?? attributes[.protectionKey] as? String
        guard protection == FileProtectionType.complete.rawValue else {
            throw RequestInputError.storage("request input file protection could not be verified")
        }
        #endif
        #if os(iOS) || os(tvOS) || os(watchOS) || os(macOS)
        var mutable = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutable.setResourceValues(values)
        mutable.removeAllCachedResourceValues()
        guard try mutable.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true else {
            throw RequestInputError.storage("request input backup exclusion could not be verified")
        }
        #endif
    }
}

extension RequestInputStore {
    private func withStore<T>(_ body: (SQLiteDB) throws -> T) throws -> T {
        gate.lock(); defer { gate.unlock() }
        if closedFlag { throw RequestInputError.closed }
        guard let db else { throw RequestInputError.closed }
        do { return try body(db) }
        catch let error as RequestInputError { throw error }
        catch let error as SQLiteError { throw RequestInputError.storage(error.description) }
        catch { throw RequestInputError.storage("request input database operation failed") }
    }

    private func requireOwner() throws {
        if closedFlag { throw RequestInputError.closed }
        guard owner?.isOwner == true else { throw RequestInputError.notOwner }
    }

    private func requireRecoveredOwner() throws {
        try requireOwner()
        guard didRecover else { throw RequestInputError.recoveryRequired }
    }

    private struct PreparedBody {
        var kind: String
        var utterance: String?
        var payloadText: String?
        var blob: Data?
        var voiceDuration: Double?
        var concept: String?
        var mode: String?
        var preview: String
        var byteCount: Int
    }

    private func validateText(_ value: String, field: String, allowEmpty: Bool = false) throws {
        if value.contains("\0") { throw RequestInputError.invalidPayload("\(field) contains a NUL character") }
        if !allowEmpty && value.isEmpty { throw RequestInputError.invalidPayload("\(field) must not be empty") }
        if value.count > policy.maxTextCharacters { throw RequestInputError.tooLarge }
    }

    private func prepare(_ body: RequestInputBody) throws -> PreparedBody {
        switch body {
        case .text(let text):
            try validateText(text, field: "text")
            return PreparedBody(kind: "text", utterance: text, payloadText: nil, blob: nil, voiceDuration: nil,
                                concept: nil, mode: nil, preview: String(text.prefix(policy.previewCharacters)),
                                byteCount: text.utf8.count)
        case .sharedText(let utterance, let text):
            try validateText(utterance, field: "utterance")
            try validateText(text, field: "shared text")
            return PreparedBody(kind: "sharedText", utterance: utterance, payloadText: text, blob: nil, voiceDuration: nil,
                                concept: nil, mode: nil, preview: String(utterance.prefix(policy.previewCharacters)),
                                byteCount: utterance.utf8.count + text.utf8.count)
        case .voice(let wav, let duration):
            guard wav.count > 0 else { throw RequestInputError.invalidPayload("voice data must not be empty") }
            guard duration.isFinite && duration >= 0 else { throw RequestInputError.invalidPayload("voice duration is invalid") }
            guard wav.count <= policy.maxVoiceBytes else { throw RequestInputError.tooLarge }
            return PreparedBody(kind: "voice", utterance: nil, payloadText: nil, blob: wav, voiceDuration: duration,
                                concept: nil, mode: nil, preview: "", byteCount: wav.count)
        case .camera(let jpeg, let question, let concept, let mode, let photoText):
            guard jpeg.count > 0 else { throw RequestInputError.invalidPayload("camera image must not be empty") }
            guard jpeg.count <= policy.maxCameraBytes else { throw RequestInputError.tooLarge }
            try validateText(question, field: "question")
            try validateText(photoText, field: "photo text", allowEmpty: true)
            try validateText(mode, field: "mode")
            if let concept { try validateText(concept, field: "concept") }
            let bytes = jpeg.count + question.utf8.count + photoText.utf8.count + (concept?.utf8.count ?? 0) + mode.utf8.count
            return PreparedBody(kind: "camera", utterance: question, payloadText: photoText, blob: jpeg, voiceDuration: nil,
                                concept: concept, mode: mode, preview: String(question.prefix(policy.previewCharacters)),
                                byteCount: bytes)
        }
    }

    @discardableResult
    public func stage(_ body: RequestInputBody, origin: RequestOrigin) throws -> RequestInputSummary {
        let prepared = try prepare(body)
        return try withStore { db in
            let id = UserRequestID()
            let created = nowProvider()
            let lifetime = prepared.kind == "camera" ? policy.cameraTTL : policy.ttl
            let expires = created.addingTimeInterval(lifetime)
            try db.transaction {
                _ = try expireLocked(db, at: created)
                let rows = try db.query("SELECT COUNT(*) AS n, COALESCE(SUM(byte_count + COALESCE(length(CAST(transcript AS BLOB)), 0)), 0) AS total FROM request_inputs WHERE state IN ('staged','claimed','interrupted')")
                let active = rows.first?["n"]?.int ?? 0
                let total = rows.first?["total"]?.int ?? 0
                if active >= Int64(policy.maxActive) || total + Int64(prepared.byteCount) > Int64(policy.maxTotalBytes) {
                    throw RequestInputError.capacity
                }
                do {
                    try db.run("""
                        INSERT INTO request_inputs
                        (request_id, state, origin, payload_kind, utterance, payload_text, payload_blob, voice_duration,
                         camera_concept, camera_mode, transcript, preview, byte_count, created, expires, claimed_at, updated,
                         interruption, captured_tz)
                        VALUES (?, 'staged', ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, ?, ?, NULL, ?, NULL, ?)
                        """, [
                            .text(id.raw.uuidString), .text(origin.rawValue), .text(prepared.kind),
                            prepared.utterance.map(SQLValue.text) ?? .null,
                            prepared.payloadText.map(SQLValue.text) ?? .null,
                            prepared.blob.map { SQLValue.blob([UInt8]($0)) } ?? .null,
                            prepared.voiceDuration.map(SQLValue.double) ?? .null,
                            prepared.concept.map(SQLValue.text) ?? .null,
                            prepared.mode.map(SQLValue.text) ?? .null,
                            .text(prepared.preview), .int(Int64(prepared.byteCount)),
                            .double(created.timeIntervalSince1970), .double(expires.timeIntervalSince1970),
                            .double(created.timeIntervalSince1970), .text(TimeZone.current.identifier),
                        ])
                } catch let error as SQLiteError {
                    if error.description.lowercased().contains("unique") || error.description.lowercased().contains("constraint") {
                        throw RequestInputError.alreadyExists
                    }
                    throw error
                }
            }
            return RequestInputSummary(id: id, origin: origin, preview: prepared.preview, byteCount: prepared.byteCount,
                                       createdAt: created, expiresAt: expires, state: .staged, interruption: nil)
        }
    }

    private enum ClaimOutcome {
        case success(ClaimedRequestInput)
        case failure(RequestInputError)
    }

    public func claim(_ id: UserRequestID) throws -> ClaimedRequestInput {
        try claimLocked(id, from: .staged)
    }

    public func retryInterrupted(_ id: UserRequestID) throws -> ClaimedRequestInput {
        try claimLocked(id, from: .interrupted)
    }

    private func claimLocked(_ id: UserRequestID, from expected: RequestInputState) throws -> ClaimedRequestInput {
        gate.lock(); defer { gate.unlock() }
        try requireRecoveredOwner()
        let outcome: ClaimOutcome = try withStore { db in
            var result: ClaimOutcome = .failure(.notResumable)
            try db.transaction {
                guard let row = try fullRow(db, id) else { result = .failure(.notFound); return }
                let decoded = try decodeFull(row)
                switch decoded.state {
                case .claimed: result = .failure(.alreadyClaimed); return
                case .completed, .discarded, .expired: result = .failure(.notResumable); return
                case .staged, .interrupted:
                    if decoded.state != expected { result = .failure(.notResumable); return }
                }
                let now = nowProvider()
                if decoded.expiresAt <= now {
                    try terminateLocked(db, id: id, to: .expired, at: now)
                    result = .failure(.expired)
                    return
                }
                guard let body = decoded.body else { throw RequestInputError.corrupt("active request input has no body") }
                try db.run("UPDATE request_inputs SET state = 'claimed', claimed_at = ?, updated = ?, interruption = NULL WHERE request_id = ? AND state = ? AND expires > ?",
                           [.double(now.timeIntervalSince1970), .double(now.timeIntervalSince1970),
                            .text(id.raw.uuidString), .text(expected.rawValue), .double(now.timeIntervalSince1970)])
                guard db.changes() == 1 else { result = .failure(.alreadyClaimed); return }
                result = .success(ClaimedRequestInput(id: id, body: body, origin: decoded.origin, transcript: decoded.transcript,
                                                      createdAt: decoded.createdAt, capturedTimeZoneID: decoded.capturedTimeZoneID,
                                                      expiresAt: decoded.expiresAt))
            }
            return result
        }
        switch outcome {
        case .success(let claimed): return claimed
        case .failure(let error): throw error
        }
    }

    public func setTranscript(_ text: String, for id: UserRequestID) throws {
        gate.lock(); defer { gate.unlock() }
        try requireRecoveredOwner()
        try validateText(text, field: "transcript")
        try withStore { db in
            try db.transaction {
                guard let row = try fullRow(db, id) else { throw RequestInputError.notFound }
                let decoded = try decodeFull(row)
                if decoded.state == .completed || decoded.state == .discarded || decoded.state == .expired {
                    throw RequestInputError.notResumable
                }
                guard decoded.state == .claimed else { throw RequestInputError.notResumable }
                guard decoded.kind == "voice" else { throw RequestInputError.invalidPayload("transcripts belong to voice requests") }
                guard decoded.transcript == nil else { throw RequestInputError.transcriptAlreadySet }
                let rows = try db.query("SELECT COALESCE(SUM(byte_count + COALESCE(length(CAST(transcript AS BLOB)), 0)), 0) AS total FROM request_inputs WHERE state IN ('staged','claimed','interrupted')")
                let total = rows.first?["total"]?.int ?? 0
                guard Int64(text.utf8.count) <= Int64(policy.maxTotalBytes) - total else {
                    throw RequestInputError.capacity
                }
                try db.run("UPDATE request_inputs SET transcript = ?, updated = ? WHERE request_id = ? AND state = 'claimed' AND transcript IS NULL",
                           [.text(text), .double(nowProvider().timeIntervalSince1970), .text(id.raw.uuidString)])
                guard db.changes() == 1 else { throw RequestInputError.transcriptAlreadySet }
            }
        }
    }

    public func complete(_ id: UserRequestID) throws {
        gate.lock(); defer { gate.unlock() }
        try requireRecoveredOwner()
        try withStore { db in
            try db.transaction {
                guard let row = try fullRow(db, id) else { throw RequestInputError.notFound }
                let decoded = try decodeFull(row)
                switch decoded.state {
                case .completed: return
                case .claimed: try terminateLocked(db, id: id, to: .completed, at: nowProvider())
                default: throw RequestInputError.notResumable
                }
            }
        }
    }

    public func interrupt(_ id: UserRequestID, reason: RequestInterruption) throws {
        gate.lock(); defer { gate.unlock() }
        try requireRecoveredOwner()
        try withStore { db in
            try db.transaction {
                guard let row = try fullRow(db, id) else { throw RequestInputError.notFound }
                let decoded = try decodeFull(row)
                switch decoded.state {
                case .interrupted: return
                case .claimed:
                    let now = nowProvider()
                    try db.run("UPDATE request_inputs SET state = 'interrupted', interruption = ?, updated = ? WHERE request_id = ? AND state = 'claimed'",
                               [.text(reason.rawValue), .double(now.timeIntervalSince1970), .text(id.raw.uuidString)])
                    guard db.changes() == 1 else { throw RequestInputError.notResumable }
                default: throw RequestInputError.notResumable
                }
            }
        }
    }

    public func discard(_ id: UserRequestID) throws {
        try withStore { db in
            try db.transaction {
                guard let row = try fullRow(db, id) else { throw RequestInputError.notFound }
                let decoded = try decodeFull(row)
                switch decoded.state {
                case .discarded: return
                case .staged, .interrupted: try terminateLocked(db, id: id, to: .discarded, at: nowProvider())
                case .claimed: throw RequestInputError.alreadyClaimed
                case .completed, .expired: throw RequestInputError.notDiscardable
                }
            }
        }
    }

    public func recoverOnLaunch() throws -> [RequestInputSummary] {
        gate.lock(); defer { gate.unlock() }
        try requireOwner()
        if !didRecover {
            try withStore { db in
                try db.transaction {
                    let now = nowProvider()
                    try db.run("UPDATE request_inputs SET state = 'interrupted', interruption = 'appStopped', updated = ? WHERE state = 'claimed'",
                               [.double(now.timeIntervalSince1970)])
                }
            }
            didRecover = true
        }
        return try summaries()
    }

    public func summaries() throws -> [RequestInputSummary] {
        try withStore { db in
            var result: [RequestInputSummary] = []
            try db.transaction {
                _ = try expireLocked(db, at: nowProvider())
                let rows = try db.query("""
                    SELECT request_id, state, origin, payload_kind, preview, byte_count, created, expires, interruption,
                           (utterance IS NULL) AS utterance_null, (payload_text IS NULL) AS payload_text_null,
                           (payload_blob IS NULL) AS blob_null, (camera_mode IS NULL) AS mode_null,
                           length(CAST(utterance AS BLOB)) AS utterance_bytes,
                           length(CAST(payload_text AS BLOB)) AS payload_bytes,
                           length(payload_blob) AS blob_bytes,
                           length(CAST(camera_concept AS BLOB)) AS concept_bytes,
                           length(CAST(camera_mode AS BLOB)) AS mode_bytes,
                           length(CAST(preview AS BLOB)) AS preview_bytes
                    FROM request_inputs WHERE state IN ('staged','interrupted') ORDER BY created ASC, request_id ASC
                    """)
                for row in rows { result.append(try decodeSummary(row)) }
            }
            return result
        }
    }

    @discardableResult
    public func purgeExpired() throws -> Int {
        try withStore { db in
            var count = 0
            try db.transaction { count = try expireLocked(db, at: nowProvider()) }
            return count
        }
    }
}

extension RequestInputStore {
    private func expireLocked(_ db: SQLiteDB, at now: Date) throws -> Int {
        let stamp = now.timeIntervalSince1970
        try db.run("""
            UPDATE request_inputs
            SET state = 'expired', utterance = NULL, payload_text = NULL, payload_blob = NULL, voice_duration = NULL,
                camera_concept = NULL, camera_mode = NULL, transcript = NULL, preview = '', interruption = NULL, updated = ?
            WHERE state IN ('staged','interrupted') AND expires <= ?
            """, [.double(stamp), .double(stamp)])
        var count = db.changes()
        try db.run("DELETE FROM request_inputs WHERE state IN ('completed','discarded','expired') AND updated <= ?",
                   [.double(now.addingTimeInterval(-policy.tombstoneRetention).timeIntervalSince1970)])
        count += db.changes()
        return count
    }

    private func terminateLocked(_ db: SQLiteDB, id: UserRequestID, to state: RequestInputState, at now: Date) throws {
        try db.run("""
            UPDATE request_inputs
            SET state = ?, utterance = NULL, payload_text = NULL, payload_blob = NULL, voice_duration = NULL,
                camera_concept = NULL, camera_mode = NULL, transcript = NULL, preview = '', interruption = NULL, updated = ?
            WHERE request_id = ?
            """, [.text(state.rawValue), .double(now.timeIntervalSince1970), .text(id.raw.uuidString)])
        guard db.changes() == 1 else { throw RequestInputError.notResumable }
    }

    private func fullRow(_ db: SQLiteDB, _ id: UserRequestID) throws -> [String: SQLValue]? {
        let rows = try db.query("""
            SELECT request_id, state, origin, payload_kind, utterance, payload_text, payload_blob, voice_duration,
                   camera_concept, camera_mode, transcript, preview, byte_count, created, expires, claimed_at, updated,
                   interruption, captured_tz,
                   length(CAST(utterance AS BLOB)) AS utterance_bytes,
                   length(CAST(payload_text AS BLOB)) AS payload_bytes,
                   length(payload_blob) AS blob_bytes,
                   length(CAST(camera_concept AS BLOB)) AS concept_bytes,
                   length(CAST(camera_mode AS BLOB)) AS mode_bytes,
                   length(CAST(transcript AS BLOB)) AS transcript_bytes,
                   length(CAST(preview AS BLOB)) AS preview_bytes
            FROM request_inputs WHERE request_id = ?
            """, [.text(id.raw.uuidString)])
        return rows.first
    }

    private struct DecodedRow {
        var state: RequestInputState
        var origin: RequestOrigin
        var kind: String
        var body: RequestInputBody?
        var transcript: String?
        var createdAt: Date
        var expiresAt: Date
        var capturedTimeZoneID: String
    }

    private func corrupt(_ reason: String) -> RequestInputError { .corrupt(reason) }

    private func requiredText(_ row: [String: SQLValue], _ key: String) throws -> String {
        guard case .text(let value)? = row[key] else { throw corrupt("field \(key) has the wrong type") }
        return value
    }

    private func optionalText(_ row: [String: SQLValue], _ key: String) throws -> String? {
        switch row[key] {
        case .text(let value): return value
        case .null, nil: return nil
        default: throw corrupt("field \(key) has the wrong type")
        }
    }

    private func requiredInt(_ row: [String: SQLValue], _ key: String) throws -> Int64 {
        guard let value = row[key]?.int else { throw corrupt("field \(key) has the wrong type") }
        return value
    }

    private func requiredDouble(_ row: [String: SQLValue], _ key: String) throws -> Double {
        guard let value = row[key]?.double, value.isFinite else { throw corrupt("field \(key) has the wrong type") }
        return value
    }

    private func optionalDouble(_ row: [String: SQLValue], _ key: String) throws -> Double? {
        switch row[key] {
        case .double(let value): return value
        case .int(let value): return Double(value)
        case .null, nil: return nil
        default: throw corrupt("field \(key) has the wrong type")
        }
    }

    private func optionalBlob(_ row: [String: SQLValue], _ key: String) throws -> Data? {
        switch row[key] {
        case .blob(let bytes): return Data(bytes)
        case .null, nil: return nil
        default: throw corrupt("field \(key) has the wrong type")
        }
    }

    private func checkTextBytes(_ swiftValue: String?, _ sqlBytes: Int64?, field: String) throws {
        if let swiftValue {
            guard sqlBytes == Int64(swiftValue.utf8.count) else { throw corrupt("field \(field) is malformed") }
            if swiftValue.contains("\0") { throw corrupt("field \(field) is malformed") }
        } else if sqlBytes != nil {
            throw corrupt("field \(field) is malformed")
        }
    }

    private func decodeFull(_ row: [String: SQLValue]) throws -> DecodedRow {
        guard let state = RequestInputState(rawValue: try requiredText(row, "state")) else { throw corrupt("unknown state") }
        guard let origin = RequestOrigin(rawValue: try requiredText(row, "origin")) else { throw corrupt("unknown origin") }
        let kind = try requiredText(row, "payload_kind")
        guard ["text", "sharedText", "voice", "camera"].contains(kind) else { throw corrupt("unknown payload kind") }
        let utterance = try optionalText(row, "utterance")
        let payloadText = try optionalText(row, "payload_text")
        let blob = try optionalBlob(row, "payload_blob")
        let duration = try optionalDouble(row, "voice_duration")
        let concept = try optionalText(row, "camera_concept")
        let mode = try optionalText(row, "camera_mode")
        let transcript = try optionalText(row, "transcript")
        let preview = try requiredText(row, "preview")
        let byteCount = try requiredInt(row, "byte_count")
        let created = try requiredDouble(row, "created")
        let expires = try requiredDouble(row, "expires")
        guard byteCount >= 0, expires > created else { throw corrupt("timestamps or byte count are malformed") }
        try checkTextBytes(utterance, row["utterance_bytes"]?.int, field: "utterance")
        try checkTextBytes(payloadText, row["payload_bytes"]?.int, field: "payload_text")
        try checkTextBytes(concept, row["concept_bytes"]?.int, field: "camera_concept")
        try checkTextBytes(mode, row["mode_bytes"]?.int, field: "camera_mode")
        try checkTextBytes(transcript, row["transcript_bytes"]?.int, field: "transcript")
        try checkTextBytes(preview, row["preview_bytes"]?.int, field: "preview")
        if let blob, row["blob_bytes"]?.int != Int64(blob.count) { throw corrupt("payload blob is malformed") }
        if blob == nil && row["blob_bytes"]?.int != nil { throw corrupt("payload blob is malformed") }

        let interruptionRaw = try optionalText(row, "interruption")
        if state == .interrupted {
            guard interruptionRaw != nil, RequestInterruption(rawValue: interruptionRaw!) != nil else { throw corrupt("interruption is malformed") }
        } else if interruptionRaw != nil {
            throw corrupt("interruption is malformed")
        }
        if let transcript, kind != "voice" || !(state == .claimed || state == .interrupted) {
            throw corrupt("transcript is malformed")
        }

        let isTerminal = state == .completed || state == .discarded || state == .expired
        if isTerminal {
            guard utterance == nil, payloadText == nil, blob == nil, duration == nil, concept == nil, mode == nil,
                  transcript == nil, preview.isEmpty else { throw corrupt("terminal row still holds a body") }
            return DecodedRow(state: state, origin: origin, kind: kind, body: nil, transcript: nil,
                              createdAt: Date(timeIntervalSince1970: created), expiresAt: Date(timeIntervalSince1970: expires),
                              capturedTimeZoneID: try requiredText(row, "captured_tz"))
        }

        let body: RequestInputBody
        let expectedBytes: Int64
        switch kind {
        case "text":
            guard let utterance, !utterance.isEmpty, payloadText == nil, blob == nil else { throw corrupt("text body is malformed") }
            body = .text(utterance)
            expectedBytes = Int64(utterance.utf8.count)
        case "sharedText":
            guard let utterance, !utterance.isEmpty, let payloadText, !payloadText.isEmpty, blob == nil else { throw corrupt("shared text body is malformed") }
            body = .sharedText(utterance: utterance, text: payloadText)
            expectedBytes = Int64(utterance.utf8.count + payloadText.utf8.count)
        case "voice":
            guard let blob, !blob.isEmpty, let duration, duration >= 0, utterance == nil, payloadText == nil else { throw corrupt("voice body is malformed") }
            body = .voice(wav: blob, duration: duration)
            expectedBytes = Int64(blob.count)
        default:
            guard let blob, !blob.isEmpty, let utterance, !utterance.isEmpty, let payloadText, let mode, !mode.isEmpty,
                  utterance != nil else { throw corrupt("camera body is malformed") }
            body = .camera(jpeg: blob, question: utterance, concept: concept, mode: mode, photoText: payloadText)
            expectedBytes = Int64(blob.count + utterance.utf8.count + payloadText.utf8.count + (concept?.utf8.count ?? 0) + mode.utf8.count)
        }
        guard byteCount == expectedBytes else { throw corrupt("byte count does not match the body") }
        return DecodedRow(state: state, origin: origin, kind: kind, body: body, transcript: transcript,
                          createdAt: Date(timeIntervalSince1970: created), expiresAt: Date(timeIntervalSince1970: expires),
                          capturedTimeZoneID: try requiredText(row, "captured_tz"))
    }

    private func decodeSummary(_ row: [String: SQLValue]) throws -> RequestInputSummary {
        guard let idRaw = try? requiredText(row, "request_id"), let uuid = UUID(uuidString: idRaw) else { throw corrupt("request id is malformed") }
        guard let state = RequestInputState(rawValue: try requiredText(row, "state")),
              state == .staged || state == .interrupted else { throw corrupt("summary state is malformed") }
        guard let origin = RequestOrigin(rawValue: try requiredText(row, "origin")) else { throw corrupt("unknown origin") }
        let kind = try requiredText(row, "payload_kind")
        let preview = try requiredText(row, "preview")
        try checkTextBytes(preview, row["preview_bytes"]?.int, field: "preview")
        let byteCount = try requiredInt(row, "byte_count")
        let utteranceNull = try requiredInt(row, "utterance_null") == 1
        let payloadTextNull = try requiredInt(row, "payload_text_null") == 1
        let blobNull = try requiredInt(row, "blob_null") == 1
        let modeNull = try requiredInt(row, "mode_null") == 1
        let expected: Int64
        switch kind {
        case "text":
            guard !utteranceNull, payloadTextNull, blobNull, let bytes = row["utterance_bytes"]?.int, bytes > 0 else { throw corrupt("text body is malformed") }
            expected = bytes
        case "sharedText":
            guard !utteranceNull, !payloadTextNull, blobNull,
                  let a = row["utterance_bytes"]?.int, let b = row["payload_bytes"]?.int, a > 0, b > 0 else { throw corrupt("shared text body is malformed") }
            expected = a + b
        case "voice":
            guard utteranceNull, payloadTextNull, !blobNull, let bytes = row["blob_bytes"]?.int, bytes > 0 else { throw corrupt("voice body is malformed") }
            expected = bytes
        case "camera":
            guard !utteranceNull, !payloadTextNull, !blobNull, !modeNull,
                  let blob = row["blob_bytes"]?.int, let a = row["utterance_bytes"]?.int,
                  let b = row["payload_bytes"]?.int, let m = row["mode_bytes"]?.int,
                  blob > 0, a > 0 else { throw corrupt("camera body is malformed") }
            expected = blob + a + b + (row["concept_bytes"]?.int ?? 0) + m
        default: throw corrupt("unknown payload kind")
        }
        guard byteCount == expected else { throw corrupt("byte count does not match the body") }
        let interruption: RequestInterruption?
        if state == .interrupted {
            guard let raw = try optionalText(row, "interruption"), let parsed = RequestInterruption(rawValue: raw) else {
                throw corrupt("interruption is malformed")
            }
            interruption = parsed
        } else {
            guard try optionalText(row, "interruption") == nil else { throw corrupt("interruption is malformed") }
            interruption = nil
        }
        return RequestInputSummary(id: UserRequestID(raw: uuid), origin: origin, preview: preview, byteCount: Int(byteCount),
                                   createdAt: Date(timeIntervalSince1970: try requiredDouble(row, "created")),
                                   expiresAt: Date(timeIntervalSince1970: try requiredDouble(row, "expires")),
                                   state: state, interruption: interruption)
    }
}


