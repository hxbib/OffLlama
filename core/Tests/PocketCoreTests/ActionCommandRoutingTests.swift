import XCTest
@testable import PocketCore

final class ActionCommandRoutingTests: XCTestCase {
    static let answerLocal = ["A": 5.0, "B": -3, "C": -3, "D": -3]
    static let toolRoute = ["A": -3.0, "B": 5, "C": -3, "D": -3]
    static let flatRoute = ["A": 0.0, "B": 0, "C": 0, "D": 0]
    static let searchMemoryTool = ["A": 0.0, "B": 0, "C": 0, "D": 0, "E": 0, "F": 6, "G": 0]

    func make(route: [String: Double], tool: [String: Double]? = nil) throws -> (Assistant, FakePhoneEffects, ScriptedEngine) {
        let e = ScriptedEngine()
        e.script(whenPromptContains: "long-term memory", logits: ["A": -3, "B": -3, "C": 3])
        e.script(whenPromptContains: "How should", logits: route)
        if let tool { e.script(whenPromptContains: "Which tool", logits: tool) }
        e.script(whenPromptContains: "explicit confirmation", logits: ["A": -4, "B": 4])
        e.generated = "Done! I set that for you."
        let db = try SQLiteDB(path: ":memory:"); let tel = try TelemetryLog(db: db)
        let effects = FakePhoneEffects()
        let a = Assistant(reflex: Reflex(engine: e, telemetry: tel, source: "test"), memory: try MemoryStore(db: db),
                          actions: RecordingActions(), ledger: try EffectLedger(db: db), effects: effects,
                          cloud: CloudBrainChain([]), isOnline: { false })
        return (a, effects, e)
    }

    func testExplicitAppleTVAlwaysReviewsWithoutChatOrSkillGuess() async throws {
        for route in [Self.answerLocal, Self.flatRoute, Self.toolRoute, ["A": -3, "B": -3, "C": -3, "D": 5]] {
            for registryPresent in [false, true] {
                let (assistant, effects, engine) = try make(route: route, tool: Self.searchMemoryTool)
                if registryPresent { assistant.skills = SkillRegistry() }
                engine.script(whenPromptContains: "Which phone action", logits: ["A": 0, "B": 0, "C": 0, "D": 0, "E": 0, "F": 0, "G": 0, "H": 0])
                engine.script(whenPromptContains: "explicit confirmation", logits: ["A": 4, "B": -4])
                let turn = try await assistant.handle("Open Ted Lasso on Apple TV")
                guard case .needsConfirmation(let card) = turn.reply else { return XCTFail("\(turn.reply)") }
                XCTAssertEqual(card.capabilityID, "appletv_play")
                XCTAssertEqual(card.fields.first { $0.name == "show" }?.value, "Ted Lasso")
                XCTAssertTrue(engine.generatePrompts.isEmpty)
                XCTAssertEqual(effects.performCount, 0)
                let result = try await assistant.confirmEffect(card.attemptID, expectedRevision: card.revision)
                guard case .finished(let effect) = result else { return XCTFail("\(result)") }
                XCTAssertEqual(effect.phase, .settled(.handedOff(.systemAcceptedURL)))
                XCTAssertEqual(effects.performCount, 1)
                _ = try await assistant.confirmEffect(card.attemptID, expectedRevision: card.revision)
                XCTAssertEqual(effects.performCount, 1)
            }
        }
    }

    func testAppleTVLatestEpisodeStillReviewsSearchForTheShow() async throws {
        for utterance in ["Play the latest episode of Ted Lasso on Apple TV",
                          "Please open Ted Lasso on Apple TV.",
                          "Could you open Ted Lasso in the Apple TV app?"] {
            let (assistant, effects, engine) = try make(route: Self.answerLocal)
            let turn = try await assistant.handle(utterance)
            guard case .needsConfirmation(let card) = turn.reply else { return XCTFail("\(turn.reply)") }
            XCTAssertEqual(card.capabilityID, "appletv_play")
            XCTAssertEqual(card.fields.first { $0.name == "show" }?.value, "Ted Lasso")
            XCTAssertTrue(card.reviewSentence.contains("does not start playback"))
            XCTAssertEqual(effects.performCount, 0)
            XCTAssertTrue(engine.generatePrompts.isEmpty)
        }
    }

    func testAppleTVMentionDoesNotForceAnAction() async throws {
        for utterance in ["How do I open Ted Lasso on Apple TV?",
                          "Don't open Ted Lasso on Apple TV", "Never play Ted Lasso on Apple TV",
                          "Text Sam open Ted Lasso on Apple TV", "Email Sam: play Ted Lasso on Apple TV",
                          "\"Open Ted Lasso on Apple TV\"", "Is Ted Lasso on Apple TV?",
                          "Open Ted Lasso on Apple TV and send Sam a message"] {
            XCTAssertFalse(ActionPlanner.isExplicitAppleTVRequest(utterance), utterance)
        }
        let (assistant, effects, _) = try make(route: Self.answerLocal)
        let turn = try await assistant.handle("How do I open Ted Lasso on Apple TV?")
        guard case .local = turn.reply else { return XCTFail("\(turn.reply)") }
        XCTAssertNil(turn.action)
        XCTAssertEqual(effects.performCount, 0)
    }

    func testConfidentChatRouteForReminderStagesCardInsteadOfGeneratedDone() async throws {
        let (a, effects, e) = try make(route: Self.answerLocal)
        effects.instantPhrases["tomorrow at 9am"] = .parsed(Date().addingTimeInterval(86_400))
        let t = try await a.handle("Remind me to call the dentist tomorrow at 9am")
        guard case .needsConfirmation(let card) = t.reply else { return XCTFail("\(t.reply)") }
        XCTAssertEqual(card.capabilityID, "reminder_create")
        XCTAssertEqual(card.fields.first { $0.name == "title" }?.value, "call the dentist")
        XCTAssertTrue(e.generatePrompts.isEmpty, "no chat text claims the reminder was set")
        XCTAssertEqual(effects.performCount, 0, "nothing runs before Confirm")
        let done = try await a.confirmEffect(card.attemptID, edits: [], expectedRevision: card.revision)
        guard case .finished(let effect) = done else { return XCTFail("\(done)") }
        XCTAssertTrue(effect.phase.isCommitted)
        XCTAssertEqual(effects.performCount, 1)
    }

    func testConfidentWrongToolChoiceForCalendarStagesEventCard() async throws {
        let (a, effects, e) = try make(route: Self.toolRoute, tool: Self.searchMemoryTool)
        let t = try await a.handle("Add lunch to my calendar tomorrow at noon")
        guard case .needsConfirmation(let card) = t.reply else { return XCTFail("\(t.reply)") }
        XCTAssertEqual(card.capabilityID, "calendar_create")
        XCTAssertEqual(t.action?.tool, "create_event")
        XCTAssertTrue(e.generatePrompts.isEmpty)
        XCTAssertEqual(effects.performCount, 0)
    }

    func testUnderconfidentRouteForMeetingStagesCardOffline() async throws {
        let (a, effects, e) = try make(route: Self.flatRoute)
        let t = try await a.handle("Schedule a team meeting tomorrow at 3pm")
        guard case .needsConfirmation(let card) = t.reply else { return XCTFail("\(t.reply)") }
        XCTAssertEqual(card.capabilityID, "calendar_create")
        XCTAssertTrue(e.generatePrompts.isEmpty, "offline fallback must not answer conversationally")
        XCTAssertEqual(effects.performCount, 0)
    }

    func testMissingTimeKeepsEditableReminderUntilTimeIsChosen() async throws {
        let (a, effects, e) = try make(route: Self.answerLocal)
        let t = try await a.handle("Remind me to call mom")
        guard case .needsConfirmation(let card) = t.reply else { return XCTFail("\(t.reply)") }
        XCTAssertFalse(card.canConfirm)
        XCTAssertEqual(card.fields.first { $0.name == "title" }?.value, "call mom")
        XCTAssertNil(card.fields.first { $0.name == "when" }?.instant)
        XCTAssertTrue(e.generatePrompts.isEmpty)
        XCTAssertEqual(effects.performCount, 0)
        let edited = try await a.editEffect(card.attemptID,
            edits: [DraftEdit(field: "when", value: .instant(Date().addingTimeInterval(3600)))],
            expectedRevision: card.revision)
        XCTAssertTrue(edited.canConfirm)
        XCTAssertEqual(effects.performCount, 0)
        let done = try await a.confirmEffect(edited.attemptID, expectedRevision: edited.revision)
        guard case .finished(let effect) = done else { return XCTFail("\(done)") }
        XCTAssertTrue(effect.phase.isCommitted)
        XCTAssertEqual(effects.performCount, 1)
    }

    func testUnsupportedConstraintsStillRejectedOnForcedPath() async throws {
        for u in ["Remind me to pay rent every month at 9am", "Add standup to my calendar on March 3 at 9am",
                  "Schedule a meeting with Dana tomorrow at 3pm"] {
            let (a, effects, _) = try make(route: Self.answerLocal)
            let t = try await a.handle(u)
            guard case .clarify(let q) = t.reply else { return XCTFail("\(u): \(t.reply)") }
            XCTAssertTrue(q.contains("not supported") || q.contains("no invitations"), "\(u): \(q)")
            XCTAssertEqual(effects.performCount, 0)
        }
    }

    func testHardNegativesKeepTheirRoute() {
        for u in ["Can you remind me what I said about Sam?", "Don't remind me to call mom tomorrow",
                  "Text Sam \"remind me to call mom\"", "Set an alarm for 6am", "Wake me at 6",
                  "Add milk to my shopping list", "What meetings do I have tomorrow?"] {
            XCTAssertNil(ActionPlanner.explicitToolCommand(u), u)
        }
        XCTAssertEqual(ActionPlanner.explicitToolCommand("Please set a reminder to water plants at 6pm"), "create_reminder")
        XCTAssertEqual(ActionPlanner.explicitToolCommand("Put dinner with Ana on my calendar Friday at 7pm"), "create_event")
        XCTAssertEqual(ActionPlanner.explicitToolCommand("Book an appointment with the dentist tomorrow at 2pm"), "create_event")
    }

    func testChatQuestionAboutRemindersStillAnswersLocally() async throws {
        let (a, _, e) = try make(route: Self.answerLocal)
        let t = try await a.handle("How do reminders work on iPhone?")
        guard case .local = t.reply else { return XCTFail("\(t.reply)") }
        XCTAssertFalse(e.generatePrompts.isEmpty)
    }
}
