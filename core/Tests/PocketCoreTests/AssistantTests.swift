import XCTest
@testable import PocketCore

final class RecordingActions: ActionExecutor, @unchecked Sendable {
    var performed: [PlannedAction] = []
    var contacts = ["Sam Lee", "Sam Ortiz"]
    func searchContacts(_ q: String) async throws -> [String] { contacts.filter { $0.lowercased().contains(q.lowercased()) } }
    func searchEvents(_ q: String) async throws -> [String] { [] }
    func perform(_ a: PlannedAction) async throws -> String { performed.append(a); return "Done: \(a.tool)" }
}

final class AssistantTests: XCTestCase {
    func make(_ e: ScriptedEngine, online: Bool = false, cloud: [CloudBrain] = []) throws -> (Assistant, RecordingActions, TelemetryLog) {
        let db = try SQLiteDB(path: ":memory:"); let tel = try TelemetryLog(db: db)
        let acts = RecordingActions()
        let a = Assistant(reflex: Reflex(engine: e, telemetry: tel, source: "test"), memory: try MemoryStore(db: db), actions: acts,
                          cloud: CloudBrainChain(cloud), isOnline: { online })
        return (a, acts, tel)
    }

    func testReminderActsWithoutConfirmation() async throws {
        let e = ScriptedEngine()
        e.script(whenPromptContains: "long-term memory", logits: ["A": -3, "B": -3, "C": 3])
        e.script(whenPromptContains: "How should", logits: ["A": -3, "B": 5, "C": -3, "D": -3])
        e.script(whenPromptContains: "Which tool", logits: ["A": 5, "B": 0, "C": 0, "D": 0, "E": 0, "F": 0, "G": 0])
        e.script(whenPromptContains: "explicit confirmation", logits: ["A": 4, "B": -2])
        let (a, acts, tel) = try make(e)
        let t = try await a.handle("Remind me to call the dentist tomorrow at 9am")
        XCTAssertEqual(t.reply, .acted("Done: create_reminder"))
        XCTAssertEqual(acts.performed.first?.args["title"], "call the dentist")
        XCTAssertEqual(acts.performed.first?.args["when"], "tomorrow at 9am")
        XCTAssertEqual(try tel.all().map(\.decisionType), [.rememberOrNot, .route, .toolChoice, .confirmBeforeAct])
        XCTAssertEqual(t.action?.tool, "create_reminder")
        XCTAssertTrue(t.action!.json.contains("\"tool\" : \"create_reminder\""), t.action!.json)
    }

    func testMessageDisambiguatesContactAndAlwaysConfirms() async throws {
        let e = ScriptedEngine()
        e.script(whenPromptContains: "long-term memory", logits: ["A": -3, "B": -3, "C": 3])
        e.script(whenPromptContains: "How should", logits: ["A": -3, "B": 5, "C": -3, "D": -3])
        e.script(whenPromptContains: "Which tool", logits: ["A": 0, "B": 0, "C": 0, "D": 6, "E": 0, "F": 0, "G": 0])
        e.script(whenPromptContains: "Which contact", logits: ["A": -1, "B": 5, "C": -2])
        e.script(whenPromptContains: "explicit confirmation", logits: ["A": 4, "B": -2])
        let (a, acts, _) = try make(e)
        let t = try await a.handle("Text Sam that I'm running 10 minutes late")
        guard case .needsConfirmation(let act, _) = t.reply else { return XCTFail("\(t.reply)") }
        XCTAssertEqual(act.args["contact"], "Sam Ortiz"); XCTAssertEqual(act.args["body"], "I'm running 10 minutes late")
        XCTAssertTrue(acts.performed.isEmpty)
        _ = try await a.confirm(act); XCTAssertEqual(acts.performed.count, 1)
    }

    func testUncertainRouteOfflineFallsBackLocally() async throws {
        let e = ScriptedEngine(); e.generated = " local best effort "
        e.script(whenPromptContains: "acceptable to send this request", logits: ["A": 5, "B": -5])
        let (a, _, tel) = try make(e)  // uniform route logits => escalate; sensitivity says ok
        let t = try await a.handle("Explain the tax implications of exercising ISOs")
        XCTAssertEqual(t.reply, .offlineFallback("local best effort"))
        XCTAssertFalse(t.cloudWithheldForSensitivity)
        XCTAssertEqual(try tel.all().map(\.decisionType), [.rememberOrNot, .route, .sensitivity])
        XCTAssertTrue(try tel.all().filter { $0.decisionType != .sensitivity }.allSatisfy(\.escalated))
    }

    func testOfflineSensitiveEscalationRunsSensitivityAndKeepsOnDevice() async throws {
        let e = ScriptedEngine(); e.generated = " LDL 210 is high. "
        e.script(whenPromptContains: "acceptable to send this request", logits: ["A": -5, "B": 5])
        final class Box: @unchecked Sendable { var called = false }
        let box = Box()
        var brain = OpenAICompatibleBrain(providerName: "Meta Model API", model: "muse-spark-1.3", baseURL: URL(string: "https://example.invalid/v1/")!, apiKey: "k")
        brain.transport = { _ in box.called = true; return (Data(#"{"choices":[{"message":{"content":"x"}}]}"#.utf8), 200) }
        for cloud in [[CloudBrain](), [brain]] {   // airplane mode, with and without a configured key
            let (a, _, tel) = try make(e, online: false, cloud: cloud)
            let t = try await a.handle("Explain what my cholesterol numbers mean: LDL 210.")
            XCTAssertEqual(t.reply, .local("LDL 210 is high."))
            XCTAssertTrue(t.cloudWithheldForSensitivity)
            XCTAssertNil(t.cloudPromptSent)
            let sens = t.decisions.first { $0.type == .sensitivity }
            XCTAssertEqual(sens?.chosen.id, "sensitive"); XCTAssertEqual(sens?.escalated, false)
            XCTAssertEqual(try tel.all().map(\.decisionType), [.rememberOrNot, .route, .sensitivity])
        }
        XCTAssertFalse(box.called)
    }

    func testLocallyRoutedSensitiveRequestStillShowsSensitivityCard() async throws {
        let e = ScriptedEngine(); e.generated = "Your PIN stays here."
        e.script(whenPromptContains: "How should", logits: ["A": 5, "B": -3, "C": -3, "D": -3])
        e.script(whenPromptContains: "acceptable to send this request", logits: ["A": -5, "B": 5])
        let (a, _, _) = try make(e, online: true)
        let t = try await a.handle("What's my bank account password hint?")
        XCTAssertEqual(t.reply, .local("Your PIN stays here."))
        XCTAssertTrue(t.cloudWithheldForSensitivity)
        XCTAssertEqual(t.decisions.last?.type, .sensitivity)
        // Non-sensitive small talk: no extra decision, behavior unchanged.
        let t2 = try await a.handle("Thanks, good night!")
        XCTAssertFalse(t2.decisions.contains { $0.type == .sensitivity })
        XCTAssertFalse(t2.cloudWithheldForSensitivity)
        XCTAssertTrue(SensitivityHint.matches("Explain what my cholesterol numbers mean: LDL 210"))
        XCTAssertFalse(SensitivityHint.matches("Suggest names for a golden retriever puppy"))
    }

    func testOnlineEscalationScrubsAndRestores() async throws {
        let e = ScriptedEngine()
        e.script(whenPromptContains: "acceptable to send this request", logits: ["A": 5, "B": -5])
        final class Box: @unchecked Sendable { var sent = "" }
        let box = Box()
        var brain = OpenAICompatibleBrain(providerName: "Meta Model API", model: "muse-spark-1.3", baseURL: URL(string: "https://example.invalid/v1/")!, apiKey: "k")
        brain.transport = { req in
            box.sent = String(decoding: req.httpBody!, as: UTF8.self)
            return (Data(#"{"choices":[{"message":{"content":"Email [EMAIL_1] the plan."}}]}"#.utf8), 200)
        }
        let (a, _, _) = try make(e, online: true, cloud: [brain])
        let t = try await a.handle("Write a careful plan and email it to dana@example.com")
        XCTAssertEqual(t.reply, .cloud("Email dana@example.com the plan.", provider: "Meta Model API · muse-spark-1.3"))
        XCTAssertFalse(box.sent.contains("dana@example.com")); XCTAssertTrue(box.sent.contains("[EMAIL_1]"))
        XCTAssertEqual(t.cloudPromptSent?.contains("[EMAIL_1]"), true)
    }

    func testSensitiveOnlineEscalationStaysOnDeviceAndFlagsWithheld() async throws {
        let e = ScriptedEngine(); e.generated = " LDL 210 is high. "
        e.script(whenPromptContains: "acceptable to send this request", logits: ["A": -5, "B": 5])
        final class Box: @unchecked Sendable { var called = false }
        let box = Box()
        var brain = OpenAICompatibleBrain(providerName: "Meta Model API", model: "muse-spark-1.3", baseURL: URL(string: "https://example.invalid/v1/")!, apiKey: "k")
        brain.transport = { _ in box.called = true; return (Data(#"{"choices":[{"message":{"content":"x"}}]}"#.utf8), 200) }
        let (a, _, _) = try make(e, online: true, cloud: [brain])  // uniform route logits => escalate_cloud
        let t = try await a.handle("Explain what my cholesterol numbers mean: LDL 210.")
        XCTAssertEqual(t.reply, .local("LDL 210 is high."))
        XCTAssertTrue(t.cloudWithheldForSensitivity)
        XCTAssertNil(t.cloudPromptSent)
        XCTAssertFalse(box.called)
        XCTAssertEqual(t.decisions.last?.chosen.id, "sensitive")

        // Offline: sensitivity still runs and still withholds (airplane-mode demo beat).
        let (off, _, _) = try make(e, online: false, cloud: [brain])
        let t2 = try await off.handle("Explain what my cholesterol numbers mean: LDL 210.")
        XCTAssertTrue(t2.cloudWithheldForSensitivity)
        XCTAssertEqual(t2.decisions.last?.chosen.id, "sensitive")
        XCTAssertFalse(box.called)
    }

    func testRememberingThroughAssistantUsesConflictDecision() async throws {
        let e = ScriptedEngine()
        e.script(whenPromptContains: "long-term memory", logits: ["A": 5, "B": -3, "C": -3])
        e.script(whenPromptContains: "relates to an existing memory", logits: ["A": 5, "B": -3, "C": -3])
        e.script(whenPromptContains: "How should", logits: ["A": 5, "B": -3, "C": -3, "D": -3])
        e.generated = "Noted!"
        let (a, _, _) = try make(e)
        _ = try await a.handle("I live in Boston.")
        let t = try await a.handle("I moved to Brooklyn.")
        XCTAssertEqual(t.reply, .local("Noted!"))
        XCTAssertEqual(try a.memory.profile()["lives_in"], ["Brooklyn"])
        XCTAssertTrue(t.decisions.contains { $0.type == .memoryConflict })
        XCTAssertEqual(t.corrections.map { "\($0.old.value)->\($0.new.value)" }, ["Boston->Brooklyn"])
        XCTAssertEqual(try a.memory.corrections().first?.old.value, "Boston")
    }
}

final class ScrubberAndCloudTests: XCTestCase {
    func testScrubRoundTrip() {
        let s = PrivacyScrubber(knownNames: ["Maya", "Sam Lee", "PERSON"])
        let r = s.scrub("Ask Maya and Sam Lee (sam@x.io, 415-555-0134) to meet at 12 Main Street. Maya agreed.")
        XCTAssertFalse(r.text.contains("Maya")); XCTAssertFalse(r.text.contains("sam@x.io")); XCTAssertFalse(r.text.contains("555"))
        XCTAssertEqual(r.text.components(separatedBy: "[PERSON_2]").count, 3) // Maya (2nd: longest names first); same name -> same placeholder
        XCTAssertEqual(s.restore(r.text, mapping: r.mapping), "Ask Maya and Sam Lee (sam@x.io, 415-555-0134) to meet at 12 Main Street. Maya agreed.")
    }
    func testRequestShapeAndChainFallback() async throws {
        let meta = CloudPresets.metaModelAPI(apiKey: "KEY")
        let req = try meta.makeRequest([.init(role: "user", content: "hi")], maxTokens: 5)
        XCTAssertEqual(req.url?.absoluteString, "https://api.meta.ai/v1/chat/completions")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer KEY")
        var bad = meta; bad.transport = { _ in (Data("nope".utf8), 503) }
        var good = CloudPresets.fireworks(model: "accounts/x/models/muse-glimmer-30b", apiKey: "k")
        good.transport = { _ in (Data(#"{"choices":[{"message":{"content":"ok"}}]}"#.utf8), 200) }
        let ans = try await CloudBrainChain([bad, good]).complete([.init(role: "user", content: "hi")])
        XCTAssertEqual(ans.provider, "Fireworks")
        do { _ = try await CloudBrainChain([]).complete([]); XCTFail() } catch { XCTAssertEqual(error as? CloudError, .notConfigured) }
    }
}
