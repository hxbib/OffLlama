import XCTest
@testable import PocketCore

/// Two-turn messaging-action repair (2026-11-04). The reported repro: `text Dana`
/// asks who and on which app; answering produces `Hi Dana!` as ordinary chat with
/// no composer. These tests pin explicit routing, recipient-first extraction, typed
/// draft retention across the follow-up, and honest native outcomes. All model
/// decisions here are scripted; they are not real-model behavior.
final class MessageDraftTests: XCTestCase {
    private func make(_ e: ScriptedEngine, online: Bool = false) throws -> (Assistant, FakePhoneEffects) {
        let db = try SQLiteDB(path: ":memory:")
        let effects = FakePhoneEffects()
        let a = Assistant(reflex: Reflex(engine: e, telemetry: try TelemetryLog(db: db), source: "test"),
                          memory: try MemoryStore(db: db), actions: RecordingActions(),
                          ledger: try EffectLedger(db: db), effects: effects,
                          cloud: CloudBrainChain([]), isOnline: { online })
        a.skills = SkillRegistry()
        return (a, effects)
    }

    private func toolMessageEngine() -> ScriptedEngine {
        let e = ScriptedEngine()
        e.script(whenPromptContains: "long-term memory", logits: ["A": -3, "B": -3, "C": 3])
        e.script(whenPromptContains: "How should", logits: ["A": -3, "B": 5, "C": -3, "D": -3])
        e.script(whenPromptContains: "Which tool", logits: ["A": 0, "B": 0, "C": 0, "D": 6, "E": 0, "F": 0, "G": 0])
        e.script(whenPromptContains: "explicit confirmation", logits: ["A": 4, "B": -2])
        return e
    }

    // MARK: explicit routing

    func testExplicitMessageDetectorCoversPoliteAndRecipientFirstForms() {
        let yes = ["text Dana", "Text Dana", "please text Dana", "can you text Dana saying hi",
                   "could you text Mom I'll be late", "would you please message Dana",
                   "message Dana", "send Dana a message", "send Dana a message saying happy birthday",
                   "Send Sam a message saying happy birthday", "tell Mom I'll be home by 8",
                   "DM Sam on Instagram saying congrats", "message @sam on twitter",
                   "text Dana on WhatsApp saying hi", "reply to Mom saying on my way"]
        for u in yes { XCTAssertTrue(ActionPlanner.isExplicitMessageRequest(u), u) }
        let no = ["Explain how text messages work", "The text of this poem is confusing",
                  "message failed to send yesterday", "send Dana an email",
                  "email Dana the slides are ready", "what's 7 times 8", "Thanks, good night!"]
        for u in no { XCTAssertFalse(ActionPlanner.isExplicitMessageRequest(u), u) }
    }

    func testChannelWordsResolveWithoutGuessing() {
        XCTAssertEqual(MessageChannel.parse(in: "text Dana"), .imessage)
        XCTAssertEqual(MessageChannel.parse(in: "send Dana a message"), .imessage)
        XCTAssertEqual(MessageChannel.parse(in: "text Dana on WhatsApp saying hi"), .whatsapp)
        XCTAssertEqual(MessageChannel.parse(in: "DM Sam on Instagram saying congrats"), .instagram)
        XCTAssertEqual(MessageChannel.parse(in: "message @sam on twitter"), .x)
        XCTAssertNil(MessageChannel.parse(in: "dm Sam"))
        XCTAssertEqual(MessageChannel.parse(in: "message Dana"), .imessage)
    }

    // MARK: extraction

    func testRecipientFirstExtractionKeepsContactAndBody() {
        func args(_ u: String) -> [String: String] {
            ArgumentExtractor.heuristic(tool: "send_message", utterance: u)
        }
        XCTAssertEqual(args("send Dana a message")["contact"], "Dana")
        XCTAssertEqual(args("send Dana a message")["body"], "")
        XCTAssertEqual(args("send Dana a message saying happy birthday")["body"], "happy birthday")
        XCTAssertEqual(args("Send Sam a message saying happy birthday")["contact"], "Sam")
        XCTAssertEqual(args("can you text Dana saying hi")["contact"], "Dana")
        XCTAssertEqual(args("can you text Dana saying hi")["body"], "hi")
        let skill = SkillRegistry().skill(id: "imessage_send")!
        XCTAssertEqual(SkillArgs.extract(skill, utterance: "send Dana a message")["contact"], "Dana")
        XCTAssertEqual(SkillArgs.extract(skill, utterance: "send Dana a message saying happy birthday")["body"], "happy birthday")
    }

    // MARK: first turn retains a typed draft

    func testTextDanaRetainsTypedDraftAskingForBody() async throws {
        let (a, effects) = try make(toolMessageEngine())
        let dana = candidate("Dana", id: "dana", methods: [phone("mobile", "5550103")])
        effects.contactQueries["Dana"] = ContactLookup(access: .full, matches: [dana])
        effects.contactIDs["dana"] = ContactLookup(access: .full, matches: [dana])
        let turn = try await a.handle("text Dana")
        guard case .clarify(let q) = turn.reply else { return XCTFail("expected clarify, got \(turn.reply)") }
        XCTAssertTrue(q.contains("say"), q)
        let draft = try XCTUnwrap(turn.pendingDraft, "clarification must retain a typed draft")
        XCTAssertEqual(draft.contact, "Dana")
        XCTAssertEqual(draft.channel, .imessage)
        XCTAssertNil(draft.body)
        XCTAssertNil(turn.action)
        XCTAssertEqual(effects.performCount, 0)
    }

    func testMissingRecipientRetainsBodyAskingWho() async throws {
        let (a, effects) = try make(toolMessageEngine())
        let turn = try await a.handle("Text I'll be home by 8")
        guard case .clarify(let q) = turn.reply else { return XCTFail("expected clarify, got \(turn.reply)") }
        XCTAssertTrue(q.lowercased().contains("who"), q)
        let draft = try XCTUnwrap(turn.pendingDraft)
        XCTAssertNil(draft.contact)
        XCTAssertEqual(draft.body, "I'll be home by 8")
        XCTAssertEqual(effects.performCount, 0)
    }

    func testAmbiguousChannelAsksAppWithoutGuessing() async throws {
        let (a, _) = try make(toolMessageEngine())
        let turn = try await a.handle("dm Sam")
        guard case .clarify(let q) = turn.reply else { return XCTFail("expected clarify, got \(turn.reply)") }
        XCTAssertTrue(q.contains("Instagram") && q.contains("X"), q)
        let draft = try XCTUnwrap(turn.pendingDraft)
        XCTAssertEqual(draft.contact, "Sam")
        XCTAssertNil(draft.channel, "no guessed channel")
    }

    // MARK: second turn binds to the draft, never to chat

    func testFollowUpBodyCompletesDraftIntoConfirmableCard() async throws {
        let (a, effects) = try make(toolMessageEngine())
        let dana = candidate("Dana", id: "dana", methods: [phone("mobile", "5550103")])
        effects.contactQueries["Dana"] = ContactLookup(access: .full, matches: [dana])
        effects.contactIDs["dana"] = ContactLookup(access: .full, matches: [dana])
        let first = try await a.handle("text Dana")
        let draft = try XCTUnwrap(first.pendingDraft)

        // Simulate the real-model misroute: the bare follow-up would route to chat.
        let e2 = ScriptedEngine(); e2.generated = "Hi Dana!"
        e2.script(whenPromptContains: "long-term memory", logits: ["A": -3, "B": -3, "C": 3])
        e2.script(whenPromptContains: "How should", logits: ["A": 5, "B": -3, "C": -3, "D": -3])
        let db = try SQLiteDB(path: ":memory:")
        let a2 = Assistant(reflex: Reflex(engine: e2, telemetry: try TelemetryLog(db: db), source: "test"),
                           memory: try MemoryStore(db: db), actions: RecordingActions(),
                           ledger: try EffectLedger(db: db), effects: effects,
                           cloud: CloudBrainChain([]), isOnline: { false })
        a2.skills = SkillRegistry()
        _ = a
        let second = try await a2.handle("saying I'll be 10 minutes late", pendingDrafts: [draft])
        guard case .needsConfirmation(let card) = second.reply else {
            return XCTFail("follow-up must complete the draft, got \(second.reply)")
        }
        XCTAssertEqual(card.capabilityID, "imessage_send")
        XCTAssertEqual(card.fields.first { $0.name == "body" }?.value, "I'll be 10 minutes late")
        XCTAssertTrue(card.canConfirm)
        XCTAssertEqual(second.consumedDrafts, [draft.requestID])
        XCTAssertEqual(effects.performCount, 0, "completion stages a card; only Confirm acts")
        XCTAssertTrue(e2.generatePrompts.isEmpty, "no chat generation on the follow-up path")
    }

    func testFollowUpShortAnswerBindsToLastAskedField() async throws {
        let (a, effects) = try make(toolMessageEngine())
        let dana = candidate("Dana", id: "dana", methods: [phone("mobile", "5550103")])
        effects.contactQueries["Dana"] = ContactLookup(access: .full, matches: [dana])
        effects.contactIDs["dana"] = ContactLookup(access: .full, matches: [dana])
        let first = try await a.handle("text Dana")
        let draft = try XCTUnwrap(first.pendingDraft)
        let second = try await a.handle("I'll be 10 minutes late", pendingDrafts: [draft])
        guard case .needsConfirmation(let card) = second.reply else {
            return XCTFail("short answer must fill the asked body, got \(second.reply)")
        }
        XCTAssertEqual(card.fields.first { $0.name == "body" }?.value, "I'll be 10 minutes late")
    }

    func testUnrelatedRequestLeavesDraftUntouched() async throws {
        let (a, _) = try make(toolMessageEngine())
        let first = try await a.handle("text Dana")
        let draft = try XCTUnwrap(first.pendingDraft)
        let e2 = ScriptedEngine(); e2.generated = "It is 3pm."
        e2.script(whenPromptContains: "long-term memory", logits: ["A": -3, "B": -3, "C": 3])
        e2.script(whenPromptContains: "How should", logits: ["A": 5, "B": -3, "C": -3, "D": -3])
        let db = try SQLiteDB(path: ":memory:")
        let a2 = Assistant(reflex: Reflex(engine: e2, telemetry: try TelemetryLog(db: db), source: "test"),
                           memory: try MemoryStore(db: db), actions: RecordingActions(),
                           ledger: nil, effects: nil, cloud: CloudBrainChain([]), isOnline: { false })
        let second = try await a2.handle("what time is it", pendingDrafts: [draft])
        XCTAssertEqual(second.reply, .local("It is 3pm."))
        XCTAssertTrue(second.consumedDrafts.isEmpty, "unrelated chat must not consume the draft")
        XCTAssertNil(second.pendingDraft)
    }

    func testNewMessageRequestDoesNotHijackPendingDraft() async throws {
        let (a, effects) = try make(toolMessageEngine())
        let dana = candidate("Dana", id: "dana", methods: [phone("mobile", "5550103")])
        effects.contactQueries["Dana"] = ContactLookup(access: .full, matches: [dana])
        effects.contactIDs["dana"] = ContactLookup(access: .full, matches: [dana])
        let first = try await a.handle("text Dana")
        let draft = try XCTUnwrap(first.pendingDraft)
        let second = try await a.handle("text Mom saying hi", pendingDrafts: [draft])
        guard case .needsConfirmation(let card) = second.reply else { return XCTFail("\(second.reply)") }
        XCTAssertEqual(card.fields.first { $0.name == "body" }?.value, "hi")
        XCTAssertTrue(second.consumedDrafts.isEmpty, "a new request leaves the old draft pending")
    }

    func testNegativeReplyIsNeverMessageBody() async throws {
        let (a, _) = try make(toolMessageEngine())
        let first = try await a.handle("text Dana")
        let draft = try XCTUnwrap(first.pendingDraft)
        for u in ["no", "don't send that", "never mind", "cancel", "forget it"] {
            let turn = try await a.handle(u, pendingDrafts: [draft])
            XCTAssertNotEqual(turn.pendingDraft?.body, u, u)
            if u == "no" {
                guard case .clarify = turn.reply else { return XCTFail("bare no must ask, got \(turn.reply)") }
                XCTAssertTrue(turn.consumedDrafts.isEmpty)
            } else {
                XCTAssertEqual(turn.consumedDrafts, [draft.requestID], u)
            }
        }
    }

    func testMultiplePendingDraftsDisambiguate() async throws {
        let (a, _) = try make(toolMessageEngine())
        let t1 = try await a.handle("text Dana")
        let d1 = try XCTUnwrap(t1.pendingDraft)
        let t2 = try await a.handle("text Mom")
        let d2 = try XCTUnwrap(t2.pendingDraft)
        let turn = try await a.handle("I'll be late", pendingDrafts: [d1, d2])
        guard case .clarify(let q) = turn.reply else { return XCTFail("expected disambiguation, got \(turn.reply)") }
        XCTAssertTrue(q.contains("Dana") && q.contains("Mom"), q)
        XCTAssertTrue(turn.consumedDrafts.isEmpty)
        let named = try await a.handle("to Dana: I'll be late", pendingDrafts: [d1, d2])
        guard case .needsConfirmation(let card) = named.reply else { return XCTFail("\(named.reply)") }
        XCTAssertEqual(named.consumedDrafts, [d1.requestID])
        XCTAssertEqual(card.fields.first { $0.name == "body" }?.value, "I'll be late")
    }

    func testStaleDraftDisambiguatesInsteadOfApplying() async throws {
        let (a, effects) = try make(toolMessageEngine())
        let dana = candidate("Dana", id: "dana", methods: [phone("mobile", "5550103")])
        effects.contactQueries["Dana"] = ContactLookup(access: .full, matches: [dana])
        effects.contactIDs["dana"] = ContactLookup(access: .full, matches: [dana])
        let first = try await a.handle("text Dana")
        var draft = try XCTUnwrap(first.pendingDraft)
        draft.created = Date().addingTimeInterval(-7200)
        let turn = try await a.handle("I'll be late", pendingDrafts: [draft])
        guard case .clarify(let q) = turn.reply else { return XCTFail("stale draft must ask, got \(turn.reply)") }
        XCTAssertTrue(q.contains("Dana"), q)
        XCTAssertTrue(turn.consumedDrafts.isEmpty)
    }

    func testLowConfidenceRoutingRetainsExplicitDraftHonestly() async throws {
        let e = ScriptedEngine()
        e.script(whenPromptContains: "long-term memory", logits: ["A": -3, "B": -3, "C": 3])
        e.script(whenPromptContains: "How should", logits: ["A": 5, "B": -3, "C": -3, "D": -3])
        let (a, effects) = try make(e)
        let dana = candidate("Dana", id: "dana", methods: [phone("mobile", "5550103")])
        effects.contactQueries["Dana"] = ContactLookup(access: .full, matches: [dana])
        effects.contactIDs["dana"] = ContactLookup(access: .full, matches: [dana])
        let turn = try await a.handle("text Dana")
        guard case .clarify(let q) = turn.reply else { return XCTFail("\(turn.reply)") }
        let draft = try XCTUnwrap(turn.pendingDraft)
        XCTAssertEqual(draft.contact, "Dana")
        XCTAssertTrue(draft.lowConfidence, "retained below tau; must say so")
        XCTAssertTrue(turn.decisions.contains { $0.type == .skillPick && $0.escalated },
                      "model decision evidence is kept")
        XCTAssertTrue(q.contains("say"), q)
        XCTAssertEqual(effects.performCount, 0)
    }

    // MARK: honest outcomes

    func testDoubleConfirmPerformsOnce() async throws {
        let (a, effects) = try make(toolMessageEngine())
        let dana = candidate("Dana", id: "dana", methods: [phone("mobile", "5550103")])
        effects.contactQueries["Dana"] = ContactLookup(access: .full, matches: [dana])
        effects.contactIDs["dana"] = ContactLookup(access: .full, matches: [dana])
        let turn = try await a.handle("text Dana saying hi")
        guard case .needsConfirmation(let card) = turn.reply else { return XCTFail("\(turn.reply)") }
        let first = try await a.confirmEffect(card.attemptID, edits: [], expectedRevision: card.revision)
        guard case .finished(let effect) = first, effect.phase.isSheet else { return XCTFail("\(first)") }
        let second = try await a.confirmEffect(card.attemptID, edits: [], expectedRevision: card.revision)
        guard case .ignoredTerminal(let again) = second else { return XCTFail("\(second)") }
        XCTAssertEqual(again.phase, effect.phase)
        XCTAssertEqual(effects.performCount, 1)
    }

    func testContactsNotDeterminedExplainsInsteadOfNoMatch() async throws {
        let (a, effects) = try make(toolMessageEngine())
        effects.access[.contacts] = .full
        effects.contactQueries["Dana"] = ContactLookup(access: .notDetermined, matches: [])
        let turn = try await a.handle("text Dana saying hi")
        guard case .needsConfirmation(let card) = turn.reply else { return XCTFail("\(turn.reply)") }
        XCTAssertFalse(card.canConfirm)
        XCTAssertTrue(card.notice.contains("access"), card.notice)
        XCTAssertFalse(card.notice.contains("No contact"), card.notice)
    }

    func testUnavailableComposerFailsHonestly() async throws {
        let (a, effects) = try make(toolMessageEngine())
        let dana = candidate("Dana", id: "dana", methods: [phone("mobile", "5550103")])
        effects.contactQueries["Dana"] = ContactLookup(access: .full, matches: [dana])
        effects.contactIDs["dana"] = ContactLookup(access: .full, matches: [dana])
        effects.handler = { _, _ in EffectReport(boundary: .notStarted(.sheetUnavailable(.messages))) }
        let turn = try await a.handle("text Dana saying hi")
        guard case .needsConfirmation(let card) = turn.reply else { return XCTFail("\(turn.reply)") }
        let done = try await a.confirmEffect(card.attemptID, edits: [], expectedRevision: card.revision)
        guard case .finished(let effect) = done else { return XCTFail("\(done)") }
        XCTAssertEqual(effect.phase, .settled(.failed(.sheetUnavailable(.messages))))
        XCTAssertTrue(effect.summary.contains("Nothing was sent"), effect.summary)
    }

    func testRecipientFirstAndPoliteCommandsStageDirectly() async throws {
        let (a, effects) = try make(toolMessageEngine())
        let dana = candidate("Dana", id: "dana", methods: [phone("mobile", "5550103")])
        effects.contactQueries["Dana"] = ContactLookup(access: .full, matches: [dana])
        effects.contactIDs["dana"] = ContactLookup(access: .full, matches: [dana])
        for u in ["send Dana a message saying happy birthday", "can you text Dana saying hi"] {
            let turn = try await a.handle(u)
            guard case .needsConfirmation(let card) = turn.reply else {
                return XCTFail("\(u) must stage a card, got \(turn.reply)")
            }
            XCTAssertEqual(card.capabilityID, "imessage_send", u)
            XCTAssertTrue(card.canConfirm, u)
            XCTAssertNil(turn.pendingDraft, u)
        }
        XCTAssertEqual(effects.performCount, 0)
    }

    func testChannelFollowUpBindsThenStagesChosenApp() async throws {
        let (a, effects) = try make(toolMessageEngine())
        let first = try await a.handle("dm Sam")
        var draft = try XCTUnwrap(first.pendingDraft)
        let second = try await a.handle("Instagram", pendingDrafts: [draft])
        guard case .clarify(let q) = second.reply else { return XCTFail("\(second.reply)") }
        XCTAssertTrue(q.contains("say"), q)
        draft = try XCTUnwrap(second.pendingDraft)
        XCTAssertEqual(draft.channel, .instagram)
        XCTAssertEqual(draft.contact, "Sam")
        let third = try await a.handle("congrats you two", pendingDrafts: [draft])
        guard case .needsConfirmation(let card) = third.reply else { return XCTFail("\(third.reply)") }
        XCTAssertEqual(card.capabilityID, "instagram_dm")
        XCTAssertEqual(card.fields.first { $0.name == "body" }?.value, "congrats you two")
        XCTAssertEqual(third.consumedDrafts, [draft.requestID])
        XCTAssertEqual(effects.performCount, 0)
    }

    func testMisroutedToolChoiceStillStagesMessage() async throws {
        let e = ScriptedEngine()
        e.script(whenPromptContains: "long-term memory", logits: ["A": -3, "B": -3, "C": 3])
        e.script(whenPromptContains: "How should", logits: ["A": -3, "B": 5, "C": -3, "D": -3])
        e.script(whenPromptContains: "Which tool", logits: ["A": 6, "B": 0, "C": 0, "D": 0, "E": 0, "F": 0, "G": 0])
        e.script(whenPromptContains: "explicit confirmation", logits: ["A": 4, "B": -2])
        let (a, effects) = try make(e)
        let dana = candidate("Dana", id: "dana", methods: [phone("mobile", "5550103")])
        effects.contactQueries["Dana"] = ContactLookup(access: .full, matches: [dana])
        effects.contactIDs["dana"] = ContactLookup(access: .full, matches: [dana])
        let turn = try await a.handle("text Dana saying hi")
        guard case .needsConfirmation(let card) = turn.reply else {
            return XCTFail("explicit message must not run the misrouted tool, got \(turn.reply)")
        }
        XCTAssertEqual(card.capabilityID, "imessage_send")
        XCTAssertEqual(turn.decisions.first { $0.type == .toolChoice }?.chosen.id, "create_reminder")
        XCTAssertEqual(effects.performCount, 0)
    }

    func testRecipientFirstEmailNeverBecomesTextDraft() async throws {
        let (a, effects) = try make(toolMessageEngine())
        let turn = try await a.handle("send Dana an email saying hi")
        if case .needsConfirmation(let card) = turn.reply {
            XCTAssertNotEqual(card.capabilityID, "imessage_send")
        }
        if let draft = turn.pendingDraft {
            XCTAssertNotEqual(draft.channel, .imessage)
        }
        XCTAssertEqual(effects.performCount, 0)
    }

    func testContactsDeniedExplainsOnCard() async throws {
        let (a, effects) = try make(toolMessageEngine())
        effects.contactQueries["Dana"] = ContactLookup(access: .denied, matches: [])
        let turn = try await a.handle("text Dana saying hi")
        guard case .needsConfirmation(let card) = turn.reply else { return XCTFail("\(turn.reply)") }
        XCTAssertFalse(card.canConfirm)
        XCTAssertTrue(card.notice.contains("access"), card.notice)
        XCTAssertEqual(effects.performCount, 0)
    }

    func testExplicitMessageBypassesChatWithoutRegistry() async throws {
        let e = ScriptedEngine(); e.generated = "Hi Dana!"
        e.script(whenPromptContains: "long-term memory", logits: ["A": -3, "B": -3, "C": 3])
        e.script(whenPromptContains: "How should", logits: ["A": 5, "B": -3, "C": -3, "D": -3])
        e.script(whenPromptContains: "explicit confirmation", logits: ["A": 4, "B": -2])
        let (a, effects) = try make(e)
        a.skills = nil
        let dana = candidate("Dana", id: "dana", methods: [phone("mobile", "5550103")])
        effects.contactQueries["Dana"] = ContactLookup(access: .full, matches: [dana])
        effects.contactIDs["dana"] = ContactLookup(access: .full, matches: [dana])
        let turn = try await a.handle("text Dana saying hi")
        guard case .needsConfirmation(let card) = turn.reply else {
            return XCTFail("explicit message must never become chat, got \(turn.reply)")
        }
        XCTAssertEqual(card.capabilityID, "imessage_send")
        XCTAssertTrue(e.generatePrompts.isEmpty)
    }

    func testDiagnosticsStaySecretFree() {
        ActionDiagnostics.shared.resetForTesting()
        let req = UserRequestID()
        ActionDiagnostics.shared.record(requestID: req, capability: "imessage_send",
                                        phase: .draft, code: .draftCreated)
        let jsonl = ActionDiagnostics.shared.exportJSONL()
        XCTAssertTrue(jsonl.contains(req.raw.uuidString))
        XCTAssertTrue(jsonl.contains("imessage_send"))
        XCTAssertFalse(jsonl.contains("Dana"))
        ActionDiagnostics.shared.resetForTesting()
    }
}
