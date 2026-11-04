import XCTest
@testable import PocketCore

final class ChartRequestTests: XCTestCase {
    private func assistant(route: String) throws -> (Assistant, ScriptedEngine, FakePhoneEffects) {
        let engine = ScriptedEngine()
        engine.generated = "rent 1200 | food 400 | transit 130"
        engine.script(whenPromptContains: "long-term memory", logits: ["A": -3, "B": -3, "C": 5])
        engine.script(whenPromptContains: "How should", logits: ["A": -5, "B": -5, "C": -5, "D": -5].merging([route: 8]) { _, new in new })
        engine.script(whenPromptContains: "Which tool", logits: ["A": 0, "B": 0, "C": 0, "D": 0, "E": 0, "F": 0, "G": 6])
        let db = try SQLiteDB(path: ":memory:")
        let effects = FakePhoneEffects()
        let assistant = Assistant(reflex: Reflex(engine: engine, telemetry: try TelemetryLog(db: db), source: "test"),
                                  memory: try MemoryStore(db: db), actions: RecordingActions(),
                                  ledger: try EffectLedger(db: db), effects: effects,
                                  cloud: CloudBrainChain([]), isOnline: { false })
        assistant.skills = SkillRegistry()
        return (assistant, engine, effects)
    }

    func testExplicitNumericChartRendersForEveryClassifierRoute() async throws {
        for (letter, id) in [("A", "answer_local"), ("B", "tool"), ("C", "escalate_cloud"), ("D", "clarify")] {
            let (a, engine, effects) = try assistant(route: letter)
            let turn = try await a.handle("Make a chart: rent 1200, food 400, transit 130")
            guard case .local(let reply) = turn.reply else { XCTFail("\(letter): \(turn.reply)"); continue }
            XCTAssertTrue(RichReply.containsMarkup(reply), reply)
            XCTAssertTrue(reply.contains("3 bars"), reply)
            XCTAssertEqual(turn.action?.tool, "skill:html_viz")
            XCTAssertEqual(turn.decisions.first { $0.type == .route }?.chosen.id, id)
            XCTAssertTrue(engine.generatePrompts.isEmpty)
            XCTAssertEqual(effects.performCount, 0)
            XCTAssertNil(turn.cloudPromptSent)
        }
    }

    func testSharedChartDataBecomesInlineMarkup() async throws {
        let (a, engine, effects) = try assistant(route: "C")
        let turn = try await a.handle("Please make a chart in HTML", sharedText: "rent 1200, food 400, transit 130")
        guard case .local(let text) = turn.reply else { return XCTFail("\(turn.reply)") }
        XCTAssertTrue(RichReply.containsMarkup(text))
        XCTAssertTrue(engine.generatePrompts.isEmpty)
        XCTAssertEqual(effects.performCount, 0)
    }

    func testChartDefinitionIsStillConversation() async throws {
        let (a, engine, _) = try assistant(route: "A")
        engine.generated = "A chart shows values visually."
        let turn = try await a.handle("What is a chart? Explain 3 kinds.")
        XCTAssertEqual(turn.reply, .local("A chart shows values visually."))
        XCTAssertNil(turn.action)
    }

    func testChartInstructionInsideMessageDoesNotExecuteChart() async throws {
        let (a, _, effects) = try assistant(route: "A")
        let dana = candidate("Dana", id: "dana", methods: [phone("mobile", "5550103")])
        effects.contactQueries["Dana"] = ContactLookup(access: .full, matches: [dana])
        effects.contactIDs["dana"] = ContactLookup(access: .full, matches: [dana])
        let turn = try await a.handle("text Dana saying make a chart: rent 1200, food 400")
        guard case .needsConfirmation(let card) = turn.reply else { return XCTFail("\(turn.reply)") }
        XCTAssertEqual(card.capabilityID, "imessage_send")
        XCTAssertEqual(card.fields.first { $0.name == "body" }?.value, "make a chart: rent 1200, food 400")
        XCTAssertEqual(effects.performCount, 0)
    }

    func testLargeFiniteNumbersRenderWithoutIntegerOverflow() throws {
        let number = String(repeating: "9", count: 200)
        let chart = try XCTUnwrap(HTMLViz.render(text: "large \(number), small 1"))
        XCTAssertEqual(chart.bars, 2)
        XCTAssertFalse(chart.html.contains("inf"))
        XCTAssertFalse(chart.html.contains("nan"))
    }

    func testNonFiniteNumbersAreNotRendered() {
        XCTAssertNil(HTMLViz.render(text: "unrepresentable " + String(repeating: "9", count: 500)))
    }

    func testChartRequestWithoutNumbersDoesNotInventData() {
        XCTAssertNil(HTMLViz.requestData(in: "Make a chart in HTML"))
        XCTAssertNil(HTMLViz.reply(text: "rent, food, transit"))
    }

    func testNewChartRequestIsNotUsedAsPendingMessageBody() async throws {
        let (a, _, effects) = try assistant(route: "A")
        let draft = MessageDraft(requestID: UserRequestID(), contact: "Dana", channel: .imessage, lastAsked: .body)
        let turn = try await a.handle("Make a chart: rent 1200, food 400, transit 130", pendingDrafts: [draft])
        guard case .local(let text) = turn.reply else { return XCTFail("\(turn.reply)") }
        XCTAssertTrue(RichReply.containsMarkup(text))
        XCTAssertTrue(turn.consumedDrafts.isEmpty)
        XCTAssertEqual(effects.performCount, 0)
    }
}
