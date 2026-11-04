import XCTest
@testable import PocketCore

final class CloudPrivacyTests: XCTestCase {
    func testPartnerProfileValueIsMaskedInTheWholeCloudPayload() async throws {
        let memory = try emptyMemory()
        for fact in RuleFactExtractor.extract("My wife is Linda") { try await memory.upsert(fact) }
        XCTAssertTrue(try memory.entityNames().contains("Linda"))
        let engine = ScriptedEngine()
        engine.script(whenPromptContains: "acceptable to send this request", logits: ["A": 5, "B": -5])
        let capture = Capture()
        let assistant = try makeAssistant(engine, cloud: [capturingBrain(capture)], memory: memory)
        _ = try await assistant.handle("Plan a weekend trip for us")
        XCTAssertEqual(capture.calls, 1)
        let body = try XCTUnwrap(capture.bodies.first)
        XCTAssertFalse(body.contains("Linda"), body)
        XCTAssertTrue(body.contains("[PERSON_"), body)
    }

    private final class Capture: @unchecked Sendable {
        var bodies: [String] = []
        var calls: Int { bodies.count }
    }

    private func makeAssistant(_ engine: LLMEngine, online: Bool = true, cloud: [CloudBrain] = [],
                               memory: MemoryStore? = nil, telemetry: TelemetryLog? = nil) throws -> Assistant {
        let db = try SQLiteDB(path: ":memory:")
        let store = try memory ?? MemoryStore(db: db)
        return Assistant(reflex: Reflex(engine: engine, telemetry: telemetry), memory: store,
                         actions: RecordingActions(), cloud: CloudBrainChain(cloud), isOnline: { online })
    }

    private func capturingBrain(_ capture: Capture, reply: String = "Cloud summary", echoUserText: Bool = false) -> OpenAICompatibleBrain {
        var brain = OpenAICompatibleBrain(providerName: "Test", model: "test-model",
                                          baseURL: URL(string: "https://example.invalid/v1/")!, apiKey: "k")
        brain.transport = { request in
            capture.bodies.append(String(decoding: request.httpBody ?? Data(), as: UTF8.self))
            var content = reply
            if echoUserText {
                let requestBody = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
                let messages = try XCTUnwrap(requestBody["messages"] as? [[String: String]])
                content = try XCTUnwrap(messages.last?["content"]?.components(separatedBy: "\n").last)
            }
            let data = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]])
            return (data, 200)
        }
        return brain
    }

    private func payload(_ body: String) throws -> [(role: String, content: String)] {
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        return try messages.map {
            (role: try XCTUnwrap($0["role"] as? String), content: try XCTUnwrap($0["content"] as? String))
        }
    }

    private func emptyMemory() throws -> MemoryStore {
        try MemoryStore(db: SQLiteDB(path: ":memory:"))
    }

    func testReplyPayloadIsTheScreenedTurnAndFiltersRetrievedSensitiveFacts() async throws {
        let memory = try emptyMemory()
        for fact in RuleFactExtractor.extract("My mom's name is Linda") { try await memory.upsert(fact) }
        try await memory.upsert(.init(subject: "user", attribute: "lives_in", value: "the Bronx", text: "User lives in the Bronx"))
        try await memory.upsert(.init(subject: "user", attribute: "allergy", value: "peanuts", text: "User is allergic to peanuts"))
        try await memory.upsert(.init(subject: "user", attribute: "likes", value: "bouldering", text: "User likes bouldering"))

        let engine = ScriptedEngine()
        engine.script(whenPromptContains: "acceptable to send this request", logits: ["A": 5, "B": -5])
        let capture = Capture()
        let assistant = try makeAssistant(engine, cloud: [capturingBrain(capture, echoUserText: true)],
                                          memory: memory)
        assistant.cloudProfileMaxChars = 400

        let turn = try await assistant.handle("Plan a bouldering weekend trip for me and Linda")
        XCTAssertEqual(capture.calls, 1)
        let messages = try payload(try XCTUnwrap(capture.bodies.first))
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, "system")
        XCTAssertEqual(messages[0].content, CloudTurnComposer.systemPrompt)
        XCTAssertEqual(messages[1].role, "user")
        XCTAssertEqual(messages[1].content, turn.cloudPromptSent)
        XCTAssertFalse(messages[1].content.contains("peanuts"), messages[1].content)
        XCTAssertTrue(messages[1].content.contains("User likes bouldering"), messages[1].content)
        XCTAssertTrue(messages[1].content.contains("[PERSON_1]"), messages[1].content)
        XCTAssertFalse(capture.bodies[0].contains("Linda"), capture.bodies[0])
        XCTAssertEqual(turn.reply, .cloud("Plan a bouldering weekend trip for me and Linda", provider: "Test · test-model"))

        let facts = try memory.active()
        let allergy = try XCTUnwrap(facts.first { $0.attribute == "allergy" })
        XCTAssertTrue(MemoryDisclosure.local.render([allergy]).contains("peanuts"))
        XCTAssertFalse(MemoryDisclosure.cloud.render([allergy]).contains("peanuts"))
        let likes = try XCTUnwrap(facts.first { $0.attribute == "likes" })
        XCTAssertTrue(MemoryDisclosure.cloud.render([likes]).contains("bouldering"))
    }

    func testFullSensitiveMemoryStillReachesLocalPrompt() async throws {
        let memory = try emptyMemory()
        try await memory.upsert(.init(subject: "user", attribute: "allergy", value: "peanuts", text: "User is allergic to peanuts"))
        try await memory.upsert(.init(subject: "user", attribute: "lives_in", value: "the Bronx", text: "User lives in the Bronx"))

        let engine = ScriptedEngine()
        engine.generated = "Local answer."
        engine.script(whenPromptContains: "acceptable to send this request", logits: ["A": -5, "B": 5])
        let capture = Capture()
        let assistant = try makeAssistant(engine, cloud: [capturingBrain(capture)], memory: memory)

        let turn = try await assistant.handle("Plan a weekend trip for me")
        XCTAssertEqual(capture.calls, 0)
        XCTAssertTrue(turn.cloudWithheldForSensitivity)
        XCTAssertNil(turn.cloudPromptSent)
        let localPrompt = try XCTUnwrap(engine.generatePrompts.last)
        XCTAssertTrue(localPrompt.contains("User is allergic to peanuts"), localPrompt)
        XCTAssertTrue(localPrompt.contains("lives in the Bronx"), localPrompt)
    }

    func testRememberedAliasIsMaskedInProfileAndUtteranceAndRestored() async throws {
        let memory = try emptyMemory()
        try await memory.upsert(.init(subject: "Dana", attribute: "role", value: "colleague",
                                      text: "Dana is a colleague", aliases: ["Starling"]))
        let engine = ScriptedEngine()
        engine.script(whenPromptContains: "acceptable to send this request", logits: ["A": 5, "B": -5])
        let capture = Capture()
        let assistant = try makeAssistant(engine, cloud: [capturingBrain(capture, echoUserText: true)],
                                          memory: memory)

        let turn = try await assistant.handle("Plan a weekend with Starling")
        XCTAssertEqual(capture.calls, 1)
        let sent = try XCTUnwrap(turn.cloudPromptSent)
        XCTAssertFalse(sent.contains("Dana"), sent)
        XCTAssertFalse(sent.contains("Starling"), sent)
        XCTAssertTrue(sent.contains("[PERSON_1]"), sent)
        XCTAssertEqual(turn.reply, .cloud("Plan a weekend with Starling", provider: "Test · test-model"))
        XCTAssertEqual(try memory.active().first?.aliases, ["starling"])
    }

    func testCloudProfileFiltersCorrectionHistoryAndSensitiveAliasesButLocalKeepsThem() async throws {
        let memory = try emptyMemory()
        try await memory.upsert(.init(subject: "user", attribute: "lives_in", value: "password hunter2",
                                      text: "User lives in password hunter2"))
        try await memory.upsert(.init(subject: "user", attribute: "lives_in", value: "the Bronx",
                                      text: "User lives in the Bronx"))
        try await memory.upsert(.init(subject: "linda", attribute: "relation", value: "sister",
                                      text: "Linda is the user's sister", aliases: ["therapist"]))
        try await memory.upsert(.init(subject: "user", attribute: "likes", value: "bouldering",
                                      text: "User likes bouldering"))
        try await memory.upsert(.init(subject: "user", attribute: "likes", value: "prescription refills",
                                      text: "User likes quiet Sunday walks"))

        let local = try memory.profileOnePager(maxChars: 4_000)
        let cloud = try memory.profileOnePager(maxChars: 4_000, redactSensitive: true)
        XCTAssertTrue(local.contains("password hunter2"), local)
        XCTAssertTrue(local.contains("Corrected by you"), local)
        XCTAssertTrue(local.contains("therapist"), local)
        XCTAssertTrue(local.contains("prescription refills"), local)
        XCTAssertTrue(local.contains("the Bronx"), local)
        XCTAssertFalse(cloud.contains("password"), cloud)
        XCTAssertFalse(cloud.contains("hunter2"), cloud)
        XCTAssertFalse(cloud.contains("therapist"), cloud)
        XCTAssertFalse(cloud.contains("prescription refills"), cloud)
        XCTAssertFalse(cloud.contains("Linda"), cloud)
        XCTAssertTrue(cloud.contains("the Bronx"), cloud)
        XCTAssertFalse(MemoryDisclosure.cloud.render(try memory.active()).contains("quiet Sunday walks"))
    }

    func testBenignLongDocumentStillEscalatesWithFullTail() async throws {
        let engine = ScriptedEngine()
        engine.script(whenPromptContains: "acceptable to send this request", logits: ["A": 5, "B": -5])
        let capture = Capture()
        let assistant = try makeAssistant(engine, cloud: [capturingBrain(capture)], memory: try emptyMemory())
        let text = String(repeating: "The quarterly planning meeting covered budgets and hiring. ", count: 120)
            + "BENIGN_TAIL_MARKER"

        let reply = try await assistant.reason("Summarize this document", text: text)
        XCTAssertEqual(capture.calls, 1)
        let messages = try payload(try XCTUnwrap(capture.bodies.first))
        XCTAssertEqual(messages.count, 2)
        XCTAssertTrue(messages[1].content.contains("BENIGN_TAIL_MARKER"), messages[1].content)
        XCTAssertGreaterThan(messages[1].content.count, 2_500)
        XCTAssertEqual(reply.text, "Cloud summary")
    }

    func testSensitiveUnicodeTailPreventsCallAndStatesLocalReadingLimit() async throws {
        let engine = ScriptedEngine()
        engine.generated = "Local summary"
        engine.script(whenPromptContains: "acceptable to send this request", logits: ["A": 5, "B": -5])
        engine.script(whenPromptContains: "PRIVATE_NOTE_6E0B", logits: ["A": -5, "B": 5])
        let capture = Capture()
        let assistant = try makeAssistant(engine, cloud: [capturingBrain(capture)], memory: try emptyMemory())
        let text = String(repeating: "会議のメモです。", count: 500)
            + " 👩🏽‍💻 "
            + String(repeating: "続き。", count: 200)
            + " PRIVATE_NOTE_6E0B"
        XCTAssertGreaterThan(text.count, 2_500)

        let result = try await assistant.reason("Summarize this document", text: text)
        XCTAssertEqual(capture.calls, 0)
        XCTAssertTrue(result.text.contains("Local summary"), result.text)
        XCTAssertTrue(result.text.contains("first 2500 characters"), result.text)
    }

    func testSensitiveInstructionWithholdsCloud() async throws {
        let engine = ScriptedEngine()
        engine.generated = "Local summary"
        engine.script(whenPromptContains: "acceptable to send this request", logits: ["A": 5, "B": -5])
        engine.script(whenPromptContains: "PRIVATE_NOTE_6E0B", logits: ["A": -5, "B": 5])
        let capture = Capture()
        let assistant = try makeAssistant(engine, cloud: [capturingBrain(capture)], memory: try emptyMemory())
        let text = String(repeating: "Benign meeting notes. ", count: 400)

        let result = try await assistant.reason("Summarize PRIVATE_NOTE_6E0B", text: text)
        XCTAssertEqual(capture.calls, 0)
        XCTAssertTrue(result.text.contains("Local summary"), result.text)
        XCTAssertTrue(result.text.contains("first 2500 characters"), result.text)
    }

    func testSensitiveTextInsideTheCapPreventsCall() async throws {
        let engine = ScriptedEngine()
        engine.generated = "Local summary"
        engine.script(whenPromptContains: "acceptable to send this request", logits: ["A": 5, "B": -5])
        engine.script(whenPromptContains: "PRIVATE_NOTE_6E0B", logits: ["A": -5, "B": 5])
        let capture = Capture()
        let assistant = try makeAssistant(engine, cloud: [capturingBrain(capture)], memory: try emptyMemory())
        let text = String(repeating: "Project notes cover budgets and schedules. ", count: 500)
            + "PRIVATE_NOTE_6E0B" + String(repeating: " tail", count: 100)

        let result = try await assistant.reason("Summarize this document", text: text)
        XCTAssertEqual(capture.calls, 0)
        XCTAssertTrue(result.text.contains("Local summary"), result.text)
        XCTAssertTrue(result.text.contains("first 2500 characters"), result.text)
    }

    func testTextBeyondTheCapIsNotSent() async throws {
        let engine = ScriptedEngine()
        engine.script(whenPromptContains: "acceptable to send this request", logits: ["A": 5, "B": -5])
        let capture = Capture()
        let assistant = try makeAssistant(engine, cloud: [capturingBrain(capture)], memory: try emptyMemory())
        let text = String(repeating: "Project notes cover budgets and schedules. ", count: 600)
            + "OUTSIDE_CAP_MARKER"

        _ = try await assistant.reason("Summarize this document", text: text)
        XCTAssertEqual(capture.calls, 1)
        let messages = try payload(try XCTUnwrap(capture.bodies.first))
        XCTAssertFalse(messages[1].content.contains("OUTSIDE_CAP_MARKER"), messages[1].content)
        XCTAssertTrue(messages[1].content.contains("[Truncated: only the first 24000 characters are included.]"),
                      messages[1].content)
        XCTAssertLessThan(messages[1].content.count, 24_100)
    }

    func testUncertainScreeningPreventsCall() async throws {
        let engine = ScriptedEngine()   // uniform logits -> below tau -> frozen sensitive fallback
        engine.generated = "Local summary"
        let capture = Capture()
        let assistant = try makeAssistant(engine, cloud: [capturingBrain(capture)], memory: try emptyMemory())
        let text = String(repeating: "Benign meeting notes. ", count: 400)

        let result = try await assistant.reason("Summarize this document", text: text)
        XCTAssertEqual(capture.calls, 0)
        XCTAssertTrue(result.text.contains("Local summary"), result.text)
        XCTAssertTrue(result.text.contains("first 2500 characters"), result.text)
        XCTAssertTrue(result.text.contains("privacy check was unsure"), result.text)
    }

    func testScreeningModelErrorPreventsCall() async throws {
        let engine = FailingSensitivityEngine()
        let capture = Capture()
        let assistant = try makeAssistant(engine, cloud: [capturingBrain(capture)], memory: try emptyMemory())
        let text = String(repeating: "Benign meeting notes. ", count: 400)

        let result = try await assistant.reason("Summarize this document", text: text)
        XCTAssertEqual(capture.calls, 0)
        XCTAssertTrue(result.text.contains("Local fallback"), result.text)
        XCTAssertTrue(result.text.contains("first 2500 characters"), result.text)
        XCTAssertTrue(result.text.contains("privacy check was unavailable"), result.text)
    }

    func testNonfiniteScreeningPreventsCall() async throws {
        for logit in [Double.nan, .infinity, -.infinity] {
            let engine = ScriptedEngine()
            engine.generated = "Local fallback"
            engine.script(whenPromptContains: "acceptable to send this request", logits: ["A": logit, "B": logit])
            let capture = Capture()
            let assistant = try makeAssistant(engine, cloud: [capturingBrain(capture)], memory: try emptyMemory())

            let result = try await assistant.reason("Summarize this document",
                                                    text: String(repeating: "Benign notes. ", count: 300))
            XCTAssertEqual(capture.calls, 0)
            XCTAssertTrue(result.text.contains("Local fallback"), result.text)
        }
    }

    func testOversizedGraphemeWithholdsInsteadOfSending() async throws {
        let engine = ScriptedEngine()
        engine.generated = "Local summary"
        engine.script(whenPromptContains: "acceptable to send this request", logits: ["A": 5, "B": -5])
        let capture = Capture()
        let assistant = try makeAssistant(engine, cloud: [capturingBrain(capture)], memory: try emptyMemory())
        let text = String(repeating: "a", count: 2_600) + "b" + String(repeating: "\u{0301}", count: 1_400)

        let result = try await assistant.reason("Summarize this document", text: text)
        XCTAssertEqual(capture.calls, 0)
        XCTAssertTrue(result.text.contains("Local summary"), result.text)
        XCTAssertTrue(result.text.contains("first 2500 characters"), result.text)
        XCTAssertTrue(result.text.contains("too large to screen completely"), result.text)
    }

    func testCancellationDuringScreeningMakesNoCloudCall() async throws {
        let engine = PausingSensitivityEngine()
        let capture = Capture()
        let assistant = try makeAssistant(engine, cloud: [capturingBrain(capture)], memory: try emptyMemory())
        let text = String(repeating: "benign notes ", count: 200)
        XCTAssertGreaterThan(text.count, 2_500)

        let task = Task { try await assistant.reason("Summarize this document", text: text) }
        await engine.waitUntilStarted()
        task.cancel()
        await engine.release()
        do {
            _ = try await task.value
            XCTFail("expected cancellation, not a local or cloud answer")
        } catch is CancellationError {
            // Expected.
        }
        XCTAssertEqual(capture.calls, 0)
    }

    func testSettingsChangedDuringScreeningDoNotAffectInFlightRequest() async throws {
        let engine = PausingSensitivityEngine()
        let first = Capture()
        let second = Capture()
        let assistant = try makeAssistant(engine, cloud: [capturingBrain(first, reply: "[PERSON_1] replied")],
                                          memory: try emptyMemory())
        assistant.scrubber = PrivacyScrubber(knownNames: ["Dana"])
        let text = "Dana: " + String(repeating: "a", count: 2_550)

        let task = Task { try await assistant.reason("Summarize this document", text: text) }
        await engine.waitUntilStarted()
        assistant.cloud = CloudBrainChain([capturingBrain(second, reply: "New brain")])
        assistant.scrubber = PrivacyScrubber(knownNames: ["Morgan"])
        await engine.release()

        let reply = try await task.value
        XCTAssertEqual(first.calls, 1)
        XCTAssertEqual(second.calls, 0)
        let messages = try payload(try XCTUnwrap(first.bodies.first))
        XCTAssertFalse(messages[1].content.contains("Dana"), messages[1].content)
        XCTAssertTrue(messages[1].content.contains("[PERSON_1]"), messages[1].content)
        XCTAssertEqual(reply.text, "Dana replied")
    }

    func testScanTelemetryDoesNotStoreDocumentText() async throws {
        let db = try SQLiteDB(path: ":memory:")
        let telemetry = try TelemetryLog(db: db)
        let engine = ScriptedEngine()
        engine.script(whenPromptContains: "acceptable to send this request", logits: ["A": 5, "B": -5])
        let capture = Capture()
        let assistant = try makeAssistant(engine, cloud: [capturingBrain(capture)],
                                          memory: try MemoryStore(db: db), telemetry: telemetry)
        let text = String(repeating: "Quarterly notes. ", count: 300) + "TELEMETRY_TAIL_MARKER"

        _ = try await assistant.reason("Summarize this document", text: text)
        XCTAssertEqual(capture.calls, 1)
        let rows = try telemetry.all()
        XCTAssertFalse(rows.isEmpty)
        for row in rows {
            XCTAssertEqual(row.decisionType, .sensitivity)
            XCTAssertNil(row.context)
        }
    }

    func testWithheldDocumentScreenIsNotExportedAsATrainingExample() async throws {
        let db = try SQLiteDB(path: ":memory:")
        let telemetry = try TelemetryLog(db: db)
        let engine = ScriptedEngine()
        let capture = Capture()
        let assistant = try makeAssistant(engine, cloud: [capturingBrain(capture)],
                                          memory: try MemoryStore(db: db), telemetry: telemetry)

        _ = try await assistant.reason("Summarize", text: String(repeating: "Meeting notes. ", count: 300))
        XCTAssertEqual(capture.calls, 0)
        XCTAssertTrue(try telemetry.all().contains { $0.escalated })
        XCTAssertEqual(try telemetry.exportDistillationQueue(), "")
    }
}

final class TextWindowsTests: XCTestCase {
    func testMaximumWindowLeavesRoomForTheFrozenDecisionPrompt() {
        let window = String(repeating: "x", count: CloudTurnComposer.maxScanUTF8Bytes)
        for style in [PromptStyle.fewShot, .zeroShot] {
            let prompt = DecisionPrompt.llama3(set: OptionSets.sensitivity, context: "User: " + window, style: style)
            XCTAssertLessThan(prompt.utf8.count + 1, 4_096, "Byte bound must include the frozen prompt and BOS, not only scanned content")
        }
    }

    func testCoverIsContiguousBoundedAndUnicodeSafe() {
        let samples = [
            "",
            "hello world",
            String(repeating: "界", count: 300),
            "e\u{0301}a\u{0301}o\u{0301}" + String(repeating: "x", count: 100),
            "👩🏽‍💻👨‍👩‍👧‍👦🇺🇸🏳️‍🌈" + String(repeating: "y", count: 60),
            "line one\r\nline two\r\nline three"
        ]
        for text in samples {
            let result = TextWindows.cover(text, maxUTF8Bytes: 64, overlap: 16)
            guard case .success(let windows) = result else {
                XCTFail("unexpected window failure for \(text.debugDescription)")
                continue
            }
            if text.isEmpty {
                XCTAssertTrue(windows.isEmpty)
                continue
            }
            XCTAssertEqual(windows.first?.lowerBound, text.startIndex, text.debugDescription)
            XCTAssertEqual(windows.last?.upperBound, text.endIndex, text.debugDescription)
            for window in windows {
                XCTAssertFalse(window.isEmpty, text.debugDescription)
                XCTAssertLessThanOrEqual(text[window].utf8.count, 64, text.debugDescription)
            }
            for (previous, next) in zip(windows, windows.dropFirst()) {
                XCTAssertLessThanOrEqual(next.lowerBound, previous.upperBound, text.debugDescription)
            }
        }
    }

    func testOverlapKeepsABoundaryPhraseWhole() {
        let phrase = "PRIVATE_NOTE_6E0B"
        let text = String(repeating: "x", count: 70) + phrase + String(repeating: "y", count: 70)
        let result = TextWindows.cover(text, maxUTF8Bytes: 60, overlap: 24)
        guard case .success(let windows) = result else { return XCTFail("unexpected window failure") }
        XCTAssertTrue(windows.contains { String(text[$0]).contains(phrase) },
                      "boundary mitigation: at least one window should carry the whole phrase")
    }

    func testSingleOversizedGraphemeFailsClosed() {
        let text = "a" + String(repeating: "\u{0301}", count: 80)
        XCTAssertEqual(text.count, 1)
        switch TextWindows.cover(text, maxUTF8Bytes: 64, overlap: 10) {
        case .failure(.characterTooLarge(let bytes)):
            XCTAssertGreaterThan(bytes, 64)
        case .success:
            XCTFail("an oversized grapheme must not be split or sent")
        }
    }

    func testEmptyTextHasNoWindows() {
        guard case .success(let windows) = TextWindows.cover("", maxUTF8Bytes: 64, overlap: 10) else {
            return XCTFail("empty text should not fail")
        }
        XCTAssertTrue(windows.isEmpty)
    }
}

private final class FailingSensitivityEngine: LLMEngine, @unchecked Sendable {
    let modelName = "failing-sensitivity"
    func nextTokenLogits(prompt: String, candidates: [String]) async throws -> [String: Double] {
        throw LLMError.badResponse("sensitivity unavailable")
    }
    func generate(prompt: String, maxTokens: Int, temperature: Double) async throws -> String {
        "Local fallback"
    }
}

private actor PausingSensitivityEngine: LLMEngine {
    nonisolated let modelName = "pausing-sensitivity"
    private var started = false
    private var released = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func nextTokenLogits(prompt: String, candidates: [String]) async throws -> [String: Double] {
        started = true
        for waiter in startWaiters { waiter.resume() }
        startWaiters.removeAll()
        if !released { await withCheckedContinuation { releaseContinuation = $0 } }
        return ["A": 5, "B": -5]
    }

    func generate(prompt: String, maxTokens: Int, temperature: Double) async throws -> String { "Local" }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func release() {
        released = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
