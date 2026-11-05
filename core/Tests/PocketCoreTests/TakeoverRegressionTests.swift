import XCTest
@testable import PocketCore

final class TakeoverRegressionTests: XCTestCase {
    func testDemoMessagePreservesBodyWithoutSeparator() {
        let args = ArgumentExtractor.heuristic(tool: "send_message", utterance: "Text Mom I'll be home by 8")
        XCTAssertEqual(args["contact"], "Mom")
        XCTAssertEqual(args["body"], "I'll be home by 8")
    }

    func testMessageParserKeepsExplicitAndTwoWordForms() {
        func args(_ utterance: String) -> [String: String] {
            ArgumentExtractor.heuristic(tool: "send_message", utterance: utterance)
        }
        let twoWord = args("Text Sam Lee I'll be home by 8")
        XCTAssertEqual(twoWord["contact"], "Sam Lee")
        XCTAssertEqual(twoWord["body"], "I'll be home by 8")
        XCTAssertEqual(args("Text Sam that I'm running late")["body"], "I'm running late")
        XCTAssertEqual(args("Text Sam saying I'm late")["body"], "I'm late")
        XCTAssertEqual(args("Text Sam: I'm late")["body"], "I'm late")
        XCTAssertEqual(args(#"Text Sam "I'm late""#)["body"], "I'm late")
        XCTAssertEqual(args("Text Sam on Instagram saying congrats")["body"], "congrats")
        XCTAssertEqual(args("Text Mom I think that we should leave: soon")["body"], "I think that we should leave: soon")
        XCTAssertEqual(args(#"Text Mom I liked "that movie" yesterday"#)["body"], #"I liked "that movie" yesterday"#)
        XCTAssertEqual(args("Text Sam")["body"], "")
        XCTAssertTrue((args("Text I'll be home by 8")["contact"] ?? "").isEmpty)
    }

    func testAppleTVRequestReachesSkillRouting() {
        XCTAssertTrue(ActionPlanner.isExplicitRequest("open the latest episode of Severance on Apple TV"))
        XCTAssertTrue(ActionPlanner.isExplicitRequest("play Ted Lasso on appletv"))
        XCTAssertTrue(ActionPlanner.isExplicitRequest("open Severance in the TV app"))
    }

    func testDemoMessagePlansFullBodyAndWaitsForConfirmation() async throws {
        let (a, effects) = try makeAssistant(messageEngine())
        let mom = candidate("Mom", id: "mom", methods: [phone("mobile", "5550100")])
        effects.contactQueries["Mom"] = ContactLookup(access: .full, matches: [mom])
        effects.contactIDs["mom"] = ContactLookup(access: .full, matches: [mom])
        let turn = try await a.handle("Text Mom I'll be home by 8")
        guard case .needsConfirmation(let card) = turn.reply else { return XCTFail("\(turn.reply)") }
        XCTAssertEqual(card.capabilityID, "imessage_send")
        XCTAssertEqual(card.fields.first { $0.name == "body" }?.value, "I'll be home by 8")
        XCTAssertEqual(card.fields.first { $0.kind == .contact }?.value, "Mom — mobile ···0100")
        XCTAssertEqual(effects.performCount, 0)
        let done = try await a.confirmEffect(card.attemptID, edits: [], expectedRevision: card.revision)
        guard case .finished(let effect) = done else { return XCTFail("\(done)") }
        XCTAssertTrue(effect.phase.isSheet)
        XCTAssertEqual(text(effects.performed.first!.action, "body"), "I'll be home by 8")
    }

    func testMissingMessageArgsClarifyWithoutAction() async throws {
        let (a, effects) = try makeAssistant(messageEngine())
        let noBody = try await a.handle("Text Mom")
        guard case .clarify(let bodyQuestion) = noBody.reply else { return XCTFail("\(noBody.reply)") }
        XCTAssertTrue(bodyQuestion.contains("say"), bodyQuestion)
        XCTAssertNil(noBody.action)
        XCTAssertFalse(noBody.decisions.contains { $0.type == .confirmBeforeAct })
        XCTAssertEqual(effects.performCount, 0)

        let noContact = try await a.handle("Text I'll be home by 8")
        guard case .clarify(let contactQuestion) = noContact.reply else { return XCTFail("\(noContact.reply)") }
        XCTAssertTrue(contactQuestion.contains("Who"), contactQuestion)
        XCTAssertNil(noContact.action)
        XCTAssertFalse(noContact.decisions.contains { $0.type == .confirmBeforeAct })
        XCTAssertEqual(effects.performCount, 0)
    }

    func testMessageSkillClarifiesMissingBodyAndKeepsFullBodyWhenGiven() async throws {
        let e = messageEngine(toolChoice: Self.noneTool)
        e.script(whenPromptContains: "Which phone action", logits: ["A": 6, "B": 0, "C": 0, "D": 0, "E": 0, "F": 0, "G": 0, "H": 0])
        let runner = RecordingSkillRunner()
        let (a, effects) = try makeAssistant(e)
        a.skills = SkillRegistry(); a.skillRunner = runner
        let mom = candidate("Mom", id: "mom", methods: [phone("mobile", "5550100")])
        effects.contactQueries["Mom"] = ContactLookup(access: .full, matches: [mom])
        effects.contactIDs["mom"] = ContactLookup(access: .full, matches: [mom])
        let utterance = "Text Mom I'll be home by 8"
        XCTAssertEqual(ActionPlanner.candidates(utterance, registry: a.skills!).first?.id, "imessage_send")

        let turn = try await a.handle(utterance)
        guard case .needsConfirmation(let card) = turn.reply else { return XCTFail("\(turn.reply)") }
        XCTAssertEqual(card.capabilityID, "imessage_send")
        XCTAssertEqual(card.fields.first { $0.name == "body" }?.value, "I'll be home by 8")
        XCTAssertTrue(runner.ran.isEmpty && effects.performCount == 0)

        let missing = try await a.handle("Text Mom")
        guard case .clarify(let question) = missing.reply else { return XCTFail("\(missing.reply)") }
        XCTAssertTrue(question.contains("say"), question)
        XCTAssertNil(missing.action)
        XCTAssertFalse(missing.decisions.contains { $0.type == .confirmBeforeAct })
        XCTAssertTrue(runner.ran.isEmpty && effects.performCount == 0)
    }

    func testAppleTVNonToolRouteReachesRegisteredSkill() async throws {
        let routes: [[String: Double]] = [["A": 5, "B": -3, "C": -3, "D": -3], ["A": -3, "B": -3, "C": 5, "D": -3]]
        for route in routes {
            let e = ScriptedEngine()
            e.script(whenPromptContains: "long-term memory", logits: ["A": -3, "B": -3, "C": 3])
            e.script(whenPromptContains: "How should", logits: route)
            e.script(whenPromptContains: "Which phone action", logits: ["A": 6, "B": 0, "C": 0, "D": 0, "E": 0, "F": 0, "G": 0, "H": 0])
            e.script(whenPromptContains: "explicit confirmation", logits: ["A": 4, "B": -2])
            let runner = RecordingSkillRunner()
            let (a, effects) = try makeAssistant(e)
            a.skills = SkillRegistry(); a.skillRunner = runner
            let utterance = "open the latest episode of Severance on Apple TV"
            XCTAssertEqual(ActionPlanner.candidates(utterance, registry: a.skills!).first?.id, "appletv_play")
            let turn = try await a.handle(utterance)
            guard case .needsConfirmation(let card) = turn.reply else { return XCTFail("\(turn.reply)") }
            XCTAssertEqual(effects.performCount, 0)
            let confirmed = try await a.confirmEffect(card.attemptID, edits: [], expectedRevision: card.revision)
            guard case .finished(let effect) = confirmed else { return XCTFail("\(confirmed)") }
            XCTAssertEqual(effect.phase, .settled(.handedOff(.systemAcceptedURL)))
            XCTAssertFalse(effect.summary.contains("Shortcuts"), effect.summary)
            XCTAssertFalse(effect.summary.lowercased().contains("playing"), effect.summary)
            XCTAssertEqual(effects.performCount, 1)
            // No phantom helper Shortcut: Apple TV search over https, with the show percent-encoded.
            guard case .urlTemplate(let template) = effects.performed.first?.action.executor else { return XCTFail() }
            XCTAssertEqual(template, "https://tv.apple.com/search?term={show}")
            XCTAssertEqual(SkillTemplate.fill(template, args: ["show": "Ted Lasso & Co"]),
                           "https://tv.apple.com/search?term=Ted%20Lasso%20%26%20Co")
            XCTAssertEqual(text(effects.performed.first!.action, "show"), "Severance")
            XCTAssertTrue(runner.ran.isEmpty)
        }
    }

    func testUncertainMessageRouteGetsConfidentSkillAndStillConfirms() async throws {
        let e = messageEngine()
        e.script(whenPromptContains: "How should", logits: ["A": 0, "B": 2.4, "C": 0, "D": 0])
        e.script(whenPromptContains: "Which phone action", logits: ["A": 6, "B": 0, "C": 0, "D": 0, "E": 0, "F": 0, "G": 0, "H": 0])
        let (a, effects) = try makeAssistant(e)
        let mom = candidate("Mom", id: "mom", methods: [phone("mobile", "5550100")])
        effects.contactQueries["Mom"] = ContactLookup(access: .full, matches: [mom])
        effects.contactIDs["mom"] = ContactLookup(access: .full, matches: [mom])
        a.reflex.profile.defaultTau = 0.90
        a.skills = SkillRegistry()
        let turn = try await a.handle("Text Mom I'll be home by 8")
        let route = try XCTUnwrap(turn.decisions.first { $0.type == .route })
        XCTAssertEqual(route.argmax.id, "tool")
        XCTAssertTrue(route.escalated)
        guard case .needsConfirmation(let card) = turn.reply else { return XCTFail("\(turn.reply)") }
        XCTAssertEqual(card.capabilityID, "imessage_send")
        XCTAssertEqual(card.fields.first { $0.name == "body" }?.value, "I'll be home by 8")
        XCTAssertEqual(effects.performCount, 0)
    }

    func testUncertainMessageSkillBecomesEditableDraft() async throws {
        let e = messageEngine()
        e.script(whenPromptContains: "How should", logits: ["A": 0, "B": 2.4, "C": 0, "D": 0])
        e.script(whenPromptContains: "Which phone action", logits: ["A": 0, "B": 0, "C": 0, "D": 0, "E": 0, "F": 0, "G": 0, "H": 0])
        let (a, effects) = try makeAssistant(e)
        let mom = candidate("Mom", id: "mom", methods: [phone("mobile", "5550100")])
        effects.contactQueries["Mom"] = ContactLookup(access: .full, matches: [mom])
        effects.contactIDs["mom"] = ContactLookup(access: .full, matches: [mom])
        a.reflex.profile.defaultTau = 0.90
        a.skills = SkillRegistry()
        let turn = try await a.handle("Text Mom I'll be home by 8")
        let pick = try XCTUnwrap(turn.decisions.first { $0.type == .skillPick })
        XCTAssertTrue(pick.escalated)
        // Below tau, the old path clarified. The explicit message now keeps its recipient/body as a draft card.
        guard case .needsConfirmation(let card) = turn.reply else { return XCTFail("\(turn.reply)") }
        XCTAssertTrue(card.notice.lowercased().contains("not confident"), card.notice)
        XCTAssertEqual(card.fields.first { $0.name == "body" }?.value, "I'll be home by 8")
        XCTAssertEqual(effects.performCount, 0)
        XCTAssertFalse(ActionPlanner.isExplicitRequest("Explain how text messages work"))
        XCTAssertFalse(ActionPlanner.isExplicitRequest("The text of this poem is confusing"))
    }

    func testSharedTextEscalationScrubsRememberedEntityNames() async throws {
        let e = ScriptedEngine()
        e.script(whenPromptContains: "acceptable to send this request", logits: ["A": 5, "B": -5])
        final class Box: @unchecked Sendable { var sent = "" }
        let box = Box()
        var brain = OpenAICompatibleBrain(providerName: "Test", model: "test-model",
                                          baseURL: URL(string: "https://example.invalid/v1/")!, apiKey: "k")
        brain.transport = { req in
            box.sent = String(decoding: req.httpBody ?? Data(), as: UTF8.self)
            return (Data(#"{"choices":[{"message":{"content":"[PERSON_1] replied."}}]}"#.utf8), 200)
        }
        let (a, _) = try makeAssistant(e, online: true, cloud: [brain])
        a.skills = SkillRegistry()
        _ = try await a.memory.upsert(ExtractedFact(subject: "Dana", attribute: "relationship", value: "sister",
                                                    text: "Dana is my sister"))
        _ = SharedInbox.shared.take()
        let shared = "Dana asked for the deck. " + String(repeating: "details ", count: 400)

        let reply = try await a.execute(PlannedAction(tool: "skill:email_digest", args: ["n": "5"]), sharedText: shared)
        XCTAssertFalse(box.sent.contains("Dana"), box.sent)
        XCTAssertTrue(box.sent.contains("[PERSON_1]"), box.sent)
        XCTAssertTrue(reply.text.contains("Dana"), reply.text)
    }

    func testSharedTextScreensSensitiveContentBeyondTheOpeningExcerpt() async throws {
        let e = ScriptedEngine()
        e.generated = "Local summary"
        e.script(whenPromptContains: "acceptable to send this request", logits: ["A": 5, "B": -5])
        e.script(whenPromptContains: "PRIVATE_NOTE_6E0B", logits: ["A": -5, "B": 5])
        final class Box: @unchecked Sendable { var calls = 0 }
        let box = Box()
        var brain = OpenAICompatibleBrain(providerName: "Test", model: "test-model",
                                          baseURL: URL(string: "https://example.invalid/v1/")!, apiKey: "k")
        brain.transport = { _ in
            box.calls += 1
            return (Data(#"{"choices":[{"message":{"content":"Cloud summary"}}]}"#.utf8), 200)
        }
        let (a, _) = try makeAssistant(e, online: true, cloud: [brain])
        let text = String(repeating: "Project meeting notes. ", count: 160)
            + "My marriage is ending. Please keep this private. Reference PRIVATE_NOTE_6E0B."
        let result = try await a.reason("Summarize this document", text: text)
        XCTAssertEqual(box.calls, 0)
        XCTAssertTrue(result.text.contains("Local summary"), result.text)
    }

    private static let noneTool: [String: Double] = ["A": 0, "B": 0, "C": 0, "D": 0, "E": 0, "F": 0, "G": 6]
    private func messageEngine(toolChoice: [String: Double]? = nil) -> ScriptedEngine {
        let e = ScriptedEngine()
        e.script(whenPromptContains: "long-term memory", logits: ["A": -3, "B": -3, "C": 3])
        e.script(whenPromptContains: "How should", logits: ["A": -3, "B": 5, "C": -3, "D": -3])
        e.script(whenPromptContains: "Which tool", logits: toolChoice ?? ["A": 0, "B": 0, "C": 0, "D": 6, "E": 0, "F": 0, "G": 0])
        e.script(whenPromptContains: "explicit confirmation", logits: ["A": 4, "B": -2])
        return e
    }
    private func makeAssistant(_ e: ScriptedEngine, online: Bool = false,
                               cloud: [CloudBrain] = []) throws -> (Assistant, FakePhoneEffects) {
        let db = try SQLiteDB(path: ":memory:")
        let acts = RecordingActions(); acts.contacts = ["Mom"]
        let effects = FakePhoneEffects()
        let a = Assistant(reflex: Reflex(engine: e, telemetry: try TelemetryLog(db: db), source: "test"),
                          memory: try MemoryStore(db: db), actions: acts,
                          ledger: try EffectLedger(db: db), effects: effects,
                          cloud: CloudBrainChain(cloud), isOnline: { online })
        return (a, effects)
    }
}

final class HelperShortcutTruthTests: XCTestCase {
    func testNoCatalogOrSkillUsesPhantomAppleTVShortcut() {
        XCTAssertFalse(BuiltinSkills.all.contains(where: { if case .shortcut(let n, _) = $0.invocation { return n == "PG Play on Apple TV" }; return false }))
        guard let c = CapabilityCatalog.current(id: "appletv_play") else { return XCTFail() }
        guard case .urlTemplate(let t) = c.executor else { return XCTFail("\(c.executor)") }
        XCTAssertTrue(t.hasPrefix("https://tv.apple.com/search?term="))
        XCTAssertEqual(c.availability, .ready)
        XCTAssertTrue(c.reviewSentence.contains("does not start playback"))
    }

    func testEveryHelperShortcutContractDisclosesSetup() {
        var helpers = 0
        for c in CapabilityCatalog.all {
            guard case .shortcut(let name, _) = c.executor else { continue }
            helpers += 1
            XCTAssertTrue(c.reviewSentence.contains("Needs a Shortcut named “\(name)”"), c.id)
        }
        XCTAssertEqual(helpers, 8)
        XCTAssertEqual(CapabilityCatalog.current(id: "run_shortcut")?.availability, .ready)
    }

}
