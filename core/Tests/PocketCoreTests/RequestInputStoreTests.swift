import XCTest
import PocketCore

private final class TestClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date = Date(timeIntervalSince1970: 1_800_000_000)) { self.now = now }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

private final class ClaimResults: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var claimed: [ClaimedRequestInput] = []
    private(set) var errors: [RequestInputError] = []
    func record(_ result: Result<ClaimedRequestInput, RequestInputError>) {
        lock.lock(); defer { lock.unlock() }
        switch result { case .success(let value): claimed.append(value); case .failure(let error): errors.append(error) }
    }
}

final class RequestInputStoreTests: XCTestCase {
    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pg-input-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeStore(_ directory: URL, policy: RequestInputPolicy = .standard, clock: TestClock) throws -> RequestInputStore {
        let store = try RequestInputStore(directory: directory, policy: policy, now: { clock.now })
        if store.isExclusiveOwner { _ = try store.recoverOnLaunch() }
        return store
    }

    private func rawDB(_ directory: URL) throws -> SQLiteDB {
        try SQLiteDB(path: directory.appendingPathComponent("request-inputs.sqlite").path)
    }

    private func expectError(_ expected: RequestInputError, _ body: () throws -> Void,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            XCTAssertEqual(error as? RequestInputError, expected, file: file, line: line)
        }
    }

    func testProcessingRequiresRecoveryAndLaterRecoveryCannotInterruptLiveClaim() throws {
        let store = try RequestInputStore(directory: makeDirectory())
        defer { store.close() }
        let saved = try store.stage(.voice(wav: Data([1, 2]), duration: 1), origin: .voice)
        expectError(.recoveryRequired) { _ = try store.claim(saved.id) }
        expectError(.recoveryRequired) { _ = try store.retryInterrupted(saved.id) }
        expectError(.recoveryRequired) { try store.setTranscript("hi", for: saved.id) }
        expectError(.recoveryRequired) { try store.complete(saved.id) }
        expectError(.recoveryRequired) { try store.interrupt(saved.id, reason: .handleFailed) }
        XCTAssertEqual(try store.recoverOnLaunch().map(\.id), [saved.id])
        _ = try store.claim(saved.id)
        XCTAssertTrue(try store.recoverOnLaunch().isEmpty)
        expectError(.alreadyClaimed) { _ = try store.retryInterrupted(saved.id) }
        try store.complete(saved.id)
    }

    func testTranscriptCapacityRefusalPreservesTheSavedAudio() throws {
        let clock = TestClock()
        let store = try makeStore(makeDirectory(), policy: .init(maxTotalBytes: 3_000), clock: clock)
        defer { store.close() }
        let wav = Data(repeating: 7, count: 2_900)
        let saved = try store.stage(.voice(wav: wav, duration: 1), origin: .voice)
        _ = try store.claim(saved.id)
        expectError(.capacity) { try store.setTranscript(String(repeating: "a", count: 500), for: saved.id) }
        try store.interrupt(saved.id, reason: .transcriptionFailed)
        let retry = try store.retryInterrupted(saved.id)
        XCTAssertEqual(retry.body, .voice(wav: wav, duration: 1))
        XCTAssertNil(retry.transcript)
        try store.setTranscript(String(repeating: "a", count: 100), for: saved.id)
    }

    func testTranscriptByteCapIncludesOneOversizedGrapheme() throws {
        let clock = TestClock()
        let store = try makeStore(makeDirectory(), policy: .init(maxTotalBytes: 3_000), clock: clock)
        defer { store.close() }
        let saved = try store.stage(.voice(wav: Data([1]), duration: 1), origin: .voice)
        _ = try store.claim(saved.id)
        let text = "e" + String(repeating: "\u{301}", count: 500_000)
        XCTAssertEqual(text.count, 1)
        expectError(.capacity) { try store.setTranscript(text, for: saved.id) }
        try store.setTranscript("small transcript", for: saved.id)
    }

    func testNewStageCountsInterruptedTranscriptsUntilBodyDeletion() throws {
        let clock = TestClock()
        let store = try makeStore(makeDirectory(), policy: .init(maxTotalBytes: 3_000), clock: clock)
        defer { store.close() }
        let saved = try store.stage(.voice(wav: Data(repeating: 1, count: 2_000), duration: 1), origin: .voice)
        _ = try store.claim(saved.id)
        try store.setTranscript(String(repeating: "a", count: 500), for: saved.id)
        try store.interrupt(saved.id, reason: .handleFailed)
        expectError(.capacity) { _ = try store.stage(.text(String(repeating: "b", count: 501)), origin: .typed) }
        XCTAssertEqual(try store.summaries().map(\.id), [saved.id])
        try store.discard(saved.id)
        _ = try store.stage(.text(String(repeating: "b", count: 3_000)), origin: .typed)
    }

    #if os(iOS) || os(tvOS) || os(watchOS) || os(macOS)
    func testStoreFilesAreExcludedFromBackup() throws {
        let directory = makeDirectory()
        let store = try RequestInputStore(directory: directory)
        defer { store.close() }
        for url in [directory, directory.appendingPathComponent(RequestInputStore.databaseFilename), directory.appendingPathComponent("owner.lock")] {
            XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
            #if os(iOS) || os(tvOS) || os(watchOS)
            let value = try FileManager.default.attributesOfItem(atPath: url.path)[.protectionKey]
            XCTAssertEqual((value as? FileProtectionType)?.rawValue ?? value as? String, FileProtectionType.complete.rawValue)
            #endif
        }
    }
    #endif

    func testStageClaimCompleteRoundTripsEachBodyKind() throws {
        let clock = TestClock(); let dir = makeDirectory()
        let store = try makeStore(dir, clock: clock)
        let text = try store.stage(.text("Remind me about Dana"), origin: .typed)
        let shared = try store.stage(.sharedText(utterance: "Summarize this", text: "Shared body"), origin: .share)
        let voice = try store.stage(.voice(wav: Data([1, 2, 3, 4]), duration: 1.5), origin: .voice)
        XCTAssertEqual(text.state, .staged)
        XCTAssertEqual(text.preview, "Remind me about Dana")
        XCTAssertEqual(shared.byteCount, "Summarize this".utf8.count + "Shared body".utf8.count)

        let claimedText = try store.claim(shared.id)
        XCTAssertEqual(claimedText.body, .sharedText(utterance: "Summarize this", text: "Shared body"))
        XCTAssertEqual(claimedText.origin, .share)
        try store.complete(shared.id)
        XCTAssertEqual(try store.claim(text.id).body, .text("Remind me about Dana"))
        let claimedVoice = try store.claim(voice.id)
        XCTAssertEqual(claimedVoice.body, .voice(wav: Data([1, 2, 3, 4]), duration: 1.5))
        store.close()
    }

    func testStagedBodiesAreIsolatedPerRequest() throws {
        let clock = TestClock(); let store = try makeStore(makeDirectory(), clock: clock)
        let a = try store.stage(.text("alpha body"), origin: .typed)
        let b = try store.stage(.text("beta body"), origin: .typed)
        XCTAssertEqual(try store.claim(b.id).body, .text("beta body"))
        XCTAssertEqual(try store.claim(a.id).body, .text("alpha body"))
        store.close()
    }

    func testConcurrentClaimsHaveExactlyOneWinner() throws {
        let clock = TestClock(); let store = try makeStore(makeDirectory(), clock: clock)
        let staged = try store.stage(.text("claim me once"), origin: .typed)
        let results = ClaimResults()
        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            do { results.record(.success(try store.claim(staged.id))) }
            catch let error as RequestInputError { results.record(.failure(error)) }
            catch { results.record(.failure(.storage("\(error)"))) }
        }
        XCTAssertEqual(results.claimed.count, 1)
        XCTAssertEqual(results.claimed.first?.body, .text("claim me once"))
        XCTAssertEqual(results.errors, Array(repeating: .alreadyClaimed, count: 7))
        store.close()
    }

    func testSecondInstanceInSameProcessIsNotOwnerAndCannotInterruptLiveClaim() throws {
        let clock = TestClock(); let dir = makeDirectory()
        let owner = try makeStore(dir, clock: clock)
        let live = try owner.stage(.text("live work"), origin: .typed)
        _ = try owner.claim(live.id)

        let second = try makeStore(dir, clock: clock)
        XCTAssertTrue(owner.isExclusiveOwner)
        XCTAssertFalse(second.isExclusiveOwner)
        expectError(.notOwner) { _ = try second.recoverOnLaunch() }
        expectError(.notOwner) { _ = try second.claim(live.id) }
        expectError(.notOwner) { _ = try second.retryInterrupted(live.id) }
        expectError(.notOwner) { try second.complete(live.id) }
        expectError(.notOwner) { try second.interrupt(live.id, reason: .handleFailed) }
        expectError(.alreadyClaimed) { try second.discard(live.id) }

        let stagedBySecond = try second.stage(.text("staged elsewhere"), origin: .share)
        XCTAssertEqual(try second.summaries().map(\.id), [stagedBySecond.id])
        try second.discard(stagedBySecond.id)
        XCTAssertTrue(try second.summaries().isEmpty)

        try owner.complete(live.id)
        second.close(); owner.close()
    }

    func testReleasingOwnerLetsNextInstanceRecoverClaimAsInterrupted() throws {
        let clock = TestClock(); let dir = makeDirectory()
        let first = try makeStore(dir, clock: clock)
        let staged = try first.stage(.voice(wav: Data([9, 8, 7]), duration: 2), origin: .voice)
        _ = try first.claim(staged.id)
        try first.setTranscript("saved transcript", for: staged.id)
        first.close()
        XCTAssertFalse(first.isExclusiveOwner)
        expectError(.closed) { _ = try first.stage(.text("too late"), origin: .typed) }

        let second = try makeStore(dir, clock: clock)
        XCTAssertTrue(second.isExclusiveOwner)
        let recovered = try second.recoverOnLaunch()
        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered.first?.state, .interrupted)
        XCTAssertEqual(recovered.first?.interruption, .appStopped)
        let retried = try second.retryInterrupted(staged.id)
        XCTAssertEqual(retried.transcript, "saved transcript")
        XCTAssertEqual(retried.body, .voice(wav: Data([9, 8, 7]), duration: 2))
        second.close()
    }

    func testRecoverIsOneShotAndNeverClaimsStagedRows() throws {
        let clock = TestClock(); let dir = makeDirectory()
        let first = try makeStore(dir, clock: clock)
        let staged = try first.stage(.text("still waiting"), origin: .typed)
        first.close()

        let second = try makeStore(dir, clock: clock)
        XCTAssertEqual(try second.recoverOnLaunch().map(\.state), [.staged])
        _ = try second.claim(staged.id)
        XCTAssertEqual(try second.recoverOnLaunch().count, 0)
        try second.complete(staged.id)
        second.close()
    }

    func testSummariesDoNotClaimOrExecute() throws {
        let clock = TestClock(); let store = try makeStore(makeDirectory(), clock: clock)
        let staged = try store.stage(.text("do not run me"), origin: .typed)
        XCTAssertEqual(try store.summaries().map(\.state), [.staged])
        XCTAssertEqual(try store.summaries().map(\.state), [.staged])
        XCTAssertEqual(try store.claim(staged.id).body, .text("do not run me"))
        store.close()
    }

    func testBodyCannotBeReplacedThroughStorageBoundary() throws {
        let clock = TestClock(); let dir = makeDirectory()
        let store = try makeStore(dir, clock: clock)
        let staged = try store.stage(.text("original body"), origin: .typed)
        do {
            let raw = try rawDB(dir)
            XCTAssertThrowsError(try raw.run(
                "UPDATE request_inputs SET utterance = 'replaced body' WHERE request_id = ?",
                [.text(staged.id.raw.uuidString)]))
        }
        XCTAssertEqual(try store.claim(staged.id).body, .text("original body"))
        store.close()
    }

    func testTerminalRowsDeleteSensitiveFieldsAndCannotRegainBody() throws {
        let clock = TestClock(); let dir = makeDirectory()
        let store = try makeStore(dir, clock: clock)
        let secret = "terminal secret body"
        let staged = try store.stage(.sharedText(utterance: "handle \(secret)", text: secret), origin: .share)
        _ = try store.claim(staged.id)
        try store.complete(staged.id)

        XCTAssertTrue(try store.summaries().isEmpty)
        expectError(.notResumable) { _ = try store.claim(staged.id) }
        expectError(.notResumable) { _ = try store.retryInterrupted(staged.id) }
        do {
            let raw = try rawDB(dir)
            let rows = try raw.query("SELECT utterance, payload_text, payload_blob, transcript, preview, interruption FROM request_inputs WHERE request_id = ?",
                                     [.text(staged.id.raw.uuidString)])
            XCTAssertEqual(rows.count, 1)
            for key in ["utterance", "payload_text", "payload_blob", "transcript", "interruption"] {
                XCTAssertEqual(rows[0][key], .null, key)
            }
            XCTAssertEqual(rows[0]["preview"], .text(""))
            XCTAssertFalse(rows.description.contains(secret))
            XCTAssertThrowsError(try raw.run(
                "UPDATE request_inputs SET utterance = 'resurrected' WHERE request_id = ?",
                [.text(staged.id.raw.uuidString)]))
        }
        store.close()
    }

    func testDiscardOnlyAcceptsStagedOrInterrupted() throws {
        let clock = TestClock(); let store = try makeStore(makeDirectory(), clock: clock)
        let staged = try store.stage(.text("discard staged"), origin: .typed)
        try store.discard(staged.id)
        try store.discard(staged.id)

        let running = try store.stage(.text("running"), origin: .typed)
        _ = try store.claim(running.id)
        expectError(.alreadyClaimed) { try store.discard(running.id) }
        try store.interrupt(running.id, reason: .handleFailed)
        try store.discard(running.id)
        XCTAssertTrue(try store.summaries().isEmpty)
        store.close()
    }

    func testTranscriptIsWriteOnceAndSurvivesInterruptRetry() throws {
        let clock = TestClock(); let store = try makeStore(makeDirectory(), clock: clock)
        let staged = try store.stage(.voice(wav: Data([1, 1, 2, 3]), duration: 1), origin: .voice)
        expectError(.notResumable) { try store.setTranscript("early", for: staged.id) }
        _ = try store.claim(staged.id)
        try store.setTranscript("hello world", for: staged.id)
        expectError(.transcriptAlreadySet) { try store.setTranscript("replacement", for: staged.id) }
        try store.interrupt(staged.id, reason: .transcriptionFailed)
        XCTAssertEqual(try store.retryInterrupted(staged.id).transcript, "hello world")
        store.close()
    }

    func testInterruptedRowsCountTowardActiveCaps() throws {
        let clock = TestClock()
        let store = try makeStore(makeDirectory(), policy: RequestInputPolicy(maxActive: 2), clock: clock)
        for index in 0..<2 {
            let staged = try store.stage(.text("interrupted \(index)"), origin: .typed)
            _ = try store.claim(staged.id)
            try store.interrupt(staged.id, reason: .handleFailed)
        }
        expectError(.capacity) { _ = try store.stage(.text("one too many"), origin: .typed) }
        store.close()

        let bytes = try makeStore(makeDirectory(), policy: RequestInputPolicy(maxTotalBytes: 10), clock: clock)
        _ = try bytes.stage(.text("123456"), origin: .typed)
        expectError(.capacity) { _ = try bytes.stage(.text("123456"), origin: .typed) }
        bytes.close()
    }

    func testExpiryRemovesBodyAndTombstoneExpiresAfterThirtyDays() throws {
        let clock = TestClock(); let store = try makeStore(makeDirectory(), clock: clock)
        let staged = try store.stage(.text("short lived"), origin: .typed)
        clock.advance(24 * 60 * 60 + 1)
        expectError(.expired) { _ = try store.claim(staged.id) }
        XCTAssertTrue(try store.summaries().isEmpty)
        expectError(.notResumable) { _ = try store.claim(staged.id) }

        let done = try store.stage(.text("finish then age out"), origin: .typed)
        _ = try store.claim(done.id)
        try store.complete(done.id)
        clock.advance(30 * 24 * 60 * 60 + 1)
        XCTAssertGreaterThanOrEqual(try store.purgeExpired(), 1)
        expectError(.notFound) { _ = try store.claim(done.id) }
        store.close()
    }

    func testUnicodeRoundTripsAndNULEmptyAndOversizeAreRefused() throws {
        let clock = TestClock(); let store = try makeStore(makeDirectory(), clock: clock)
        let unicode = "caf\u{00E9} \u{1F600}\u{200D}\u{1F525} \u{05E9}\u{05DC}\u{05D5}\u{05DD} \u{4E2D}\u{6587} e\u{0301}"
        let staged = try store.stage(.text(unicode), origin: .typed)
        XCTAssertEqual(staged.byteCount, unicode.utf8.count)
        XCTAssertEqual(try store.claim(staged.id).body, .text(unicode))
        try store.complete(staged.id)

        expectError(.invalidPayload("text contains a NUL character")) { _ = try store.stage(.text("bad\0body"), origin: .typed) }
        expectError(.invalidPayload("text must not be empty")) { _ = try store.stage(.text(""), origin: .typed) }
        expectError(.tooLarge) { _ = try store.stage(.text(String(repeating: "a", count: 24_001)), origin: .typed) }
        expectError(.tooLarge) { _ = try store.stage(.voice(wav: Data(repeating: 1, count: 2 * 1024 * 1024 + 1), duration: 1), origin: .voice) }
        XCTAssertTrue(try store.summaries().isEmpty)
        store.close()
    }

    func testCorruptRowsFailClosed() throws {
        let clock = TestClock(); let dir = makeDirectory()
        let store = try makeStore(dir, clock: clock)
        let planted = UserRequestID()
        do {
            let raw = try rawDB(dir)
            let now = clock.now.timeIntervalSince1970
            try raw.run("""
                INSERT INTO request_inputs (request_id, state, origin, payload_kind, utterance, preview, byte_count, created, expires, updated, captured_tz)
                VALUES (?, 'staged', 'typed', 'text', '', '', 0, ?, ?, ?, 'UTC')
                """, [.text(planted.raw.uuidString), .double(now), .double(now + 3600), .double(now)])
        }
        XCTAssertThrowsError(try store.claim(planted)) { error in
            guard case .corrupt = error as? RequestInputError else { return XCTFail("expected corrupt, got \(error)") }
        }
        XCTAssertThrowsError(try store.summaries()) { error in
            guard case .corrupt = error as? RequestInputError else { return XCTFail("expected corrupt, got \(error)") }
        }

        let mismatch = UserRequestID()
        do {
            let raw = try rawDB(dir)
            let now = clock.now.timeIntervalSince1970
            try raw.run("""
                INSERT INTO request_inputs (request_id, state, origin, payload_kind, utterance, preview, byte_count, created, expires, updated, captured_tz)
                VALUES (?, 'staged', 'typed', 'text', 'planted body', 'planted body', 999999, ?, ?, ?, 'UTC')
                """, [.text(mismatch.raw.uuidString), .double(now), .double(now + 3600), .double(now)])
        }
        XCTAssertThrowsError(try store.claim(mismatch)) { error in
            guard case .corrupt = error as? RequestInputError else { return XCTFail("expected corrupt, got \(error)") }
        }
        store.close()
    }

    func testCameraPayloadIsBoundedAndExpiresAfterOneHour() throws {
        let clock = TestClock()
        let store = try makeStore(makeDirectory(), policy: RequestInputPolicy(maxCameraBytes: 4), clock: clock)
        expectError(.tooLarge) {
            _ = try store.stage(.camera(jpeg: Data([1, 2, 3, 4, 5]), question: "What is this?", concept: nil, mode: "identify", photoText: "leaf"), origin: .camera)
        }
        let staged = try store.stage(.camera(jpeg: Data([1, 2, 3]), question: "What is this?", concept: "leaf", mode: "identify", photoText: "leaf"), origin: .camera)
        XCTAssertEqual(staged.expiresAt, staged.createdAt.addingTimeInterval(60 * 60))
        XCTAssertEqual(try store.claim(staged.id).body,
                       .camera(jpeg: Data([1, 2, 3]), question: "What is this?", concept: "leaf", mode: "identify", photoText: "leaf"))
        store.close()

        let expiring = try makeStore(makeDirectory(), clock: clock)
        _ = try expiring.stage(.camera(jpeg: Data([1]), question: "q", concept: nil, mode: "identify", photoText: ""), origin: .camera)
        clock.advance(60 * 60 + 1)
        XCTAssertTrue(try expiring.summaries().isEmpty)
        expiring.close()
    }

    func testCompleteAndInterruptAreIdempotentForTheirTerminalDirection() throws {
        let clock = TestClock(); let store = try makeStore(makeDirectory(), clock: clock)
        let a = try store.stage(.text("complete twice"), origin: .typed)
        _ = try store.claim(a.id)
        try store.complete(a.id); try store.complete(a.id)

        let b = try store.stage(.text("interrupt twice"), origin: .typed)
        _ = try store.claim(b.id)
        try store.interrupt(b.id, reason: .handleFailed)
        try store.interrupt(b.id, reason: .appStopped)
        XCTAssertEqual(try store.summaries().first?.interruption, .handleFailed)
        store.close()
    }
}
