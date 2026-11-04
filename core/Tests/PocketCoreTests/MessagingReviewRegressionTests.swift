import XCTest
@testable import PocketCore

final class MessagingReviewRegressionTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func draft(contact: String? = nil, channel: MessageChannel? = nil, body: String? = nil,
               lastAsked: DraftMissingField? = nil, age: TimeInterval = 60) -> MessageDraft {
        var d = MessageDraft(requestID: UserRequestID(), contact: contact, channel: channel,
                             body: body, created: now.addingTimeInterval(-age))
        d.lastAsked = lastAsked ?? d.missingField
        return d
    }

    // MARK: pure follow-up binder

    func testLowercaseContactAnswerCompletes() {
        let d = draft(channel: .imessage, body: "hi", lastAsked: .contact)
        let r = MessageFollowUp.resolve("dana", drafts: [d], now: now)
        guard case .completed(let done) = r else { return XCTFail("lowercase name answer must bind, got \(r)") }
        XCTAssertEqual(done.contact?.lowercased(), "dana")
    }

    func testLowercaseToContactAnswerCompletes() {
        let d = draft(channel: .imessage, body: "hi", lastAsked: .contact)
        let r = MessageFollowUp.resolve("to dana", drafts: [d], now: now)
        guard case .completed = r else { return XCTFail("'to dana' must bind, got \(r)") }
    }

    func testBodyThatIsAQuestionCompletes() {
        let d = draft(contact: "Dana", channel: .imessage, lastAsked: .body)
        let r = MessageFollowUp.resolve("Are we still on for tonight?", drafts: [d], now: now)
        guard case .completed(let done) = r else { return XCTFail("question-shaped body must fill body, got \(r)") }
        XCTAssertEqual(done.body, "Are we still on for tonight?")
    }

    func testUnrelatedCommandIsNotStagedAsBody() {
        let d = draft(contact: "Dana", channel: .imessage, lastAsked: .body)
        let r = MessageFollowUp.resolve("Book a flight to Miami", drafts: [d], now: now)
        if case .completed(let done) = r {
            XCTFail("unrelated command became the message body: \(done.body ?? "")")
        }
    }

    func testBodyStartingWithNoCompletes() {
        let d = draft(contact: "Dana", channel: .imessage, lastAsked: .body)
        let r = MessageFollowUp.resolve("No worries, see you at 6", drafts: [d], now: now)
        guard case .completed = r else { return XCTFail("body starting with 'No' must fill body, got \(r)") }
    }

    func testAskedBodyPreservesImperativesAndAppNames() {
        let d = draft(contact: "Dana", channel: .imessage, lastAsked: .body)
        for text in ["Call me when you land", "I posted it on Instagram", "Hi Dana!", "Please don't send the report until Friday"] {
            guard case .completed(let done) = MessageFollowUp.resolve(text, drafts: [d], now: now) else {
                XCTFail("Message text was not retained: \(text)"); continue
            }
            XCTAssertEqual(done.body, text)
            XCTAssertEqual(done.channel, .imessage)
        }
    }

    func testChannelWordInsideBodyDoesNotSwitchChannel() {
        let d = draft(contact: "Dana", channel: .imessage, lastAsked: .body)
        let r = MessageFollowUp.resolve("saying I posted it on Instagram", drafts: [d], now: now)
        guard case .completed(let done) = r else { return XCTFail("expected completion, got \(r)") }
        XCTAssertEqual(done.channel, .imessage, "a channel word inside the body text switched the channel")
        XCTAssertEqual(done.body, "I posted it on Instagram")
    }

    func testStaleDraftYesDoesNotLoop() {
        let d = draft(contact: "Dana", channel: .imessage, lastAsked: .body, age: 7200)
        let r = MessageFollowUp.resolve("yes", drafts: [d], now: now)
        if case .disambiguate = r { XCTFail("'yes' after the stale prompt only repeats the stale prompt") }
    }

    func testNamedCancelAmongMany() {
        let d1 = draft(contact: "Dana", channel: .imessage, lastAsked: .body)
        let d2 = draft(contact: "Mom", channel: .imessage, lastAsked: .body)
        let r = MessageFollowUp.resolve("cancel the Dana one", drafts: [d1, d2], now: now)
        guard case .cancelled(let id) = r else { return XCTFail("named cancel must cancel Dana, got \(r)") }
        XCTAssertEqual(id, d1.requestID)
    }

    func testNewExplicitBodyIsNotBlockedBySavedBody() {
        let d = draft(contact: "Dana", body: "old text", lastAsked: .channel)
        let r = MessageFollowUp.resolve("dm Dana saying new text", drafts: [d], now: now)
        if case .clarifyKeep(let q) = r { XCTFail("new explicit request blocked by saved body: \(q)") }
    }

    func testApostropheContactAnswerCompletes() {
        let d = draft(channel: .imessage, body: "hi", lastAsked: .contact)
        let r = MessageFollowUp.resolve("O'Brien", drafts: [d], now: now)
        guard case .completed(let done) = r else { return XCTFail("apostrophe name must bind, got \(r)") }
        XCTAssertEqual(done.contact, "O'Brien")
    }

    func testNewlineBodyPreserved() {
        let d = draft(contact: "Dana", channel: .imessage, lastAsked: .body)
        let text = "line one\nline two"
        let r = MessageFollowUp.resolve(text, drafts: [d], now: now)
        guard case .completed(let done) = r else { return XCTFail("newline body must fill, got \(r)") }
        XCTAssertEqual(done.body, text)
    }

    func testHandleContactAnswerCompletes() {
        let d = draft(channel: .instagram, body: "hi", lastAsked: .contact)
        let r = MessageFollowUp.resolve("@sam", drafts: [d], now: now)
        guard case .completed(let done) = r else { return XCTFail("handle must bind, got \(r)") }
        XCTAssertEqual(done.contact, "sam")
    }

    func testThreeTurnChannelThenBody() {
        let d = draft(contact: "Sam", lastAsked: .channel)
        let r1 = MessageFollowUp.resolve("Instagram", drafts: [d], now: now)
        guard case .updated(let mid) = r1 else { return XCTFail("channel turn: \(r1)") }
        XCTAssertEqual(mid.channel, .instagram)
        let r2 = MessageFollowUp.resolve("congrats", drafts: [mid], now: now)
        guard case .completed(let done) = r2 else { return XCTFail("body turn: \(r2)") }
        XCTAssertEqual(done.body, "congrats")
    }

    // MARK: detector and extraction

    func testWhatsAppVerbIsExplicit() {
        XCTAssertTrue(ActionPlanner.isExplicitMessageRequest("WhatsApp Dana saying hi"))
    }

    func testSMSVerbIsExplicit() {
        XCTAssertTrue(ActionPlanner.isExplicitMessageRequest("sms Dana saying hi"))
    }

    func testChannelWordInBodyDoesNotHijackFirstTurn() {
        XCTAssertEqual(MessageChannel.parse(in: "text Dana saying ig is down"), .imessage)
    }

    func testSendTextToFormExtracts() {
        XCTAssertTrue(ActionPlanner.isExplicitMessageRequest("send a text to Dana saying hi"))
        let parts = MessageDraft.messageArgs("send a text to Dana saying hi")
        XCTAssertEqual(parts.contact, "Dana")
        XCTAssertEqual(parts.body, "hi")
    }

    func testColonBodyExtracts() {
        let parts = MessageDraft.messageArgs("Text Dana: I'll be late")
        XCTAssertEqual(parts.contact, "Dana")
        XCTAssertEqual(parts.body, "I'll be late")
    }

    func testRecipientFirstWhatsAppMessageExtractsBody() {
        let parts = MessageDraft.messageArgs("please send Dana a WhatsApp message saying hi")
        XCTAssertEqual(parts.contact, "Dana")
        XCTAssertEqual(parts.body, "hi")
        XCTAssertEqual(MessageChannel.parse(in: "please send Dana a WhatsApp message saying hi"), .whatsapp)
    }

    // MARK: assistant level

    private func makeA(_ e: ScriptedEngine) throws -> (Assistant, FakePhoneEffects) {
        let db = try SQLiteDB(path: ":memory:")
        let effects = FakePhoneEffects()
        let a = Assistant(reflex: Reflex(engine: e, telemetry: try TelemetryLog(db: db), source: "test"),
                          memory: try MemoryStore(db: db), actions: RecordingActions(),
                          ledger: try EffectLedger(db: db), effects: effects,
                          cloud: CloudBrainChain([]), isOnline: { false })
        a.skills = SkillRegistry()
        return (a, effects)
    }

    private func toolEngine() -> ScriptedEngine {
        let e = ScriptedEngine()
        e.script(whenPromptContains: "long-term memory", logits: ["A": -3, "B": -3, "C": 3])
        e.script(whenPromptContains: "How should", logits: ["A": -3, "B": 5, "C": -3, "D": -3])
        e.script(whenPromptContains: "Which tool", logits: ["A": 0, "B": 0, "C": 0, "D": 6, "E": 0, "F": 0, "G": 0])
        e.script(whenPromptContains: "explicit confirmation", logits: ["A": 4, "B": -2])
        return e
    }

    private func chatEngine(generated: String) -> ScriptedEngine {
        let e = ScriptedEngine(); e.generated = generated
        e.script(whenPromptContains: "long-term memory", logits: ["A": -3, "B": -3, "C": 3])
        e.script(whenPromptContains: "How should", logits: ["A": 5, "B": -3, "C": -3, "D": -3])
        return e
    }

    private func wireDana(_ effects: FakePhoneEffects, methods: [ContactMethod]? = nil) {
        let dana = candidate("Dana", id: "dana", methods: methods ?? [phone("mobile", "5550103")])
        effects.contactQueries["Dana"] = ContactLookup(access: .full, matches: [dana])
        effects.contactQueries["dana"] = ContactLookup(access: .full, matches: [dana])
        effects.contactIDs["dana"] = ContactLookup(access: .full, matches: [dana])
    }

    func testNoRegistryToolNoneStagesCompiledMessage() async throws {
        let e = ScriptedEngine()
        e.script(whenPromptContains: "long-term memory", logits: ["A": -3, "B": -3, "C": 3])
        e.script(whenPromptContains: "How should", logits: ["A": -3, "B": 5, "C": -3, "D": -3])
        e.script(whenPromptContains: "Which tool", logits: ["A": 0, "B": 0, "C": 0, "D": 0, "E": 0, "F": 0, "G": 6])
        let (a, effects) = try makeA(e)
        a.skills = nil
        wireDana(effects)
        let turn = try await a.handle("text Dana saying hi")
        guard case .needsConfirmation(let card) = turn.reply else { return XCTFail("\(turn.reply)") }
        XCTAssertEqual(card.capabilityID, "imessage_send")
        XCTAssertEqual(card.fields.first { $0.name == "body" }?.value, "hi")
        XCTAssertEqual(effects.performCount, 0)
        XCTAssertTrue(e.generatePrompts.isEmpty)
        XCTAssertEqual(turn.decisions.first { $0.type == .toolChoice }?.chosen.id, "none")
    }

    func testLowercaseFollowUpDoesNotBecomeChat() async throws {
        let (a, effects) = try makeA(toolEngine())
        wireDana(effects)
        let first = try await a.handle("Text I'll be home by 8")
        let d = try XCTUnwrap(first.pendingDraft)
        XCTAssertNil(d.contact)
        let db = try SQLiteDB(path: ":memory:")
        let e2 = chatEngine(generated: "Hi Dana!")
        let a3 = Assistant(reflex: Reflex(engine: e2, telemetry: try TelemetryLog(db: db), source: "test"),
                           memory: try MemoryStore(db: db), actions: RecordingActions(),
                           ledger: try EffectLedger(db: db), effects: effects,
                           cloud: CloudBrainChain([]), isOnline: { false })
        a3.skills = SkillRegistry()
        let second = try await a3.handle("dana", pendingDrafts: [d])
        guard case .needsConfirmation = second.reply else {
            return XCTFail("lowercase follow-up must stage a card, got \(second.reply); generated=\(e2.generatePrompts.count) prompts")
        }
    }

    func testBodyQuestionDoesNotBecomeChat() async throws {
        let (a, effects) = try makeA(toolEngine())
        wireDana(effects)
        let first = try await a.handle("text Dana")
        let d = try XCTUnwrap(first.pendingDraft)
        let db = try SQLiteDB(path: ":memory:")
        let e2 = chatEngine(generated: "Yes, 6pm works.")
        let a2 = Assistant(reflex: Reflex(engine: e2, telemetry: try TelemetryLog(db: db), source: "test"),
                           memory: try MemoryStore(db: db), actions: RecordingActions(),
                           ledger: try EffectLedger(db: db), effects: effects,
                           cloud: CloudBrainChain([]), isOnline: { false })
        a2.skills = SkillRegistry()
        let second = try await a2.handle("Are we still on for tonight?", pendingDrafts: [d])
        guard case .needsConfirmation = second.reply else {
            return XCTFail("question-shaped body must stage a card, got \(second.reply)")
        }
        XCTAssertTrue(e2.generatePrompts.isEmpty)
    }

    func testUnrelatedCommandNotStagedAsBody() async throws {
        let (a, effects) = try makeA(toolEngine())
        wireDana(effects)
        let first = try await a.handle("text Dana")
        let d = try XCTUnwrap(first.pendingDraft)
        let second = try await a.handle("Book a flight to Miami", pendingDrafts: [d])
        if case .needsConfirmation(let card) = second.reply,
           card.fields.first(where: { $0.name == "body" })?.value == "Book a flight to Miami" {
            XCTFail("unrelated command was staged as the message body")
        }
    }

    func testBodyChannelWordDoesNotStageWrongApp() async throws {
        let (a, effects) = try makeA(toolEngine())
        wireDana(effects)
        let turn = try await a.handle("text Dana saying ig is down")
        guard case .needsConfirmation(let card) = turn.reply else { return XCTFail("\(turn.reply)") }
        XCTAssertEqual(card.capabilityID, "imessage_send", "body word 'ig' hijacked the channel")
    }

    func testMultiRecipientIsRefusedPrecisely() async throws {
        let (a, effects) = try makeA(toolEngine())
        wireDana(effects)
        let turn = try await a.handle("text Dana and Mom saying hi")
        guard case .clarify(let q) = turn.reply else { return XCTFail("expected unsupported clarify, got \(turn.reply)") }
        XCTAssertTrue(q.contains("one recipient"), q)
        XCTAssertNil(turn.pendingDraft)
    }

    func testSeveralPhoneMethodsRequireChoiceThenConfirm() async throws {
        let (a, effects) = try makeA(toolEngine())
        wireDana(effects, methods: [phone("mobile", "5550103"), phone("home", "5550199")])
        let turn = try await a.handle("text Dana saying hi")
        guard case .needsConfirmation(let card) = turn.reply else { return XCTFail("\(turn.reply)") }
        XCTAssertFalse(card.canConfirm, "two phone methods must require a choice")
        let done = try await a.confirmEffect(card.attemptID,
                                             edits: [DraftEdit(field: "contact", value: .contactMethod(phone("mobile", "5550103")))],
                                             expectedRevision: card.revision)
        guard case .finished(let effect) = done, effect.phase.isSheet else { return XCTFail("\(done)") }
        XCTAssertEqual(effects.performCount, 1)
        if case .contact(let b)? = effects.performed.first?.action.arguments["contact"] {
            XCTAssertEqual(b.method?.value, "5550103")
        } else { XCTFail("performed action has no bound contact method") }
    }

    func testLimitedContactsStillBind() async throws {
        let (a, effects) = try makeA(toolEngine())
        let dana = candidate("Dana", id: "dana", methods: [phone("mobile", "5550103")])
        effects.contactQueries["Dana"] = ContactLookup(access: .limited, matches: [dana])
        effects.contactIDs["dana"] = ContactLookup(access: .limited, matches: [dana])
        let turn = try await a.handle("text Dana saying hi")
        guard case .needsConfirmation(let card) = turn.reply else { return XCTFail("\(turn.reply)") }
        XCTAssertTrue(card.canConfirm, card.notice)
    }

    func testPermissionGrantRefreshesTheSameCardWithoutPerforming() async throws {
        let (a, effects) = try makeA(toolEngine())
        effects.contactQueries["Dana"] = ContactLookup(access: .notDetermined, matches: [])
        let turn = try await a.handle("text Dana saying hi")
        guard case .needsConfirmation(let card) = turn.reply else { return XCTFail("\(turn.reply)") }
        XCTAssertFalse(card.canConfirm)
        wireDana(effects)
        let refreshed = try await a.editEffect(card.attemptID, edits: [.init(field: "contact", value: .refreshContact)],
                                              expectedRevision: card.revision)
        XCTAssertEqual(refreshed.attemptID, card.attemptID)
        XCTAssertEqual(refreshed.requestID, card.requestID)
        XCTAssertGreaterThan(refreshed.revision, card.revision)
        XCTAssertTrue(refreshed.canConfirm, refreshed.notice)
        XCTAssertEqual(refreshed.fields.first { $0.name == "body" }?.value, "hi")
        XCTAssertEqual(effects.performCount, 0)
        _ = try await a.confirmEffect(refreshed.attemptID, expectedRevision: refreshed.revision)
        XCTAssertEqual(effects.performCount, 1)
    }

    func testDeniedContactRefreshDoesNotBindOrPerform() async throws {
        let (a, effects) = try makeA(toolEngine())
        wireDana(effects)
        let turn = try await a.handle("text Dana saying hi")
        guard case .needsConfirmation(let card) = turn.reply else { return XCTFail("\(turn.reply)") }
        let hidden = candidate("Dana", id: "dana", methods: [phone("mobile", "5550103")])
        effects.contactQueries["Dana"] = ContactLookup(access: .denied, matches: [hidden])
        let refreshed = try await a.editEffect(card.attemptID, edits: [.init(field: "contact", value: .refreshContact)],
                                              expectedRevision: card.revision)
        XCTAssertFalse(refreshed.canConfirm)
        XCTAssertTrue(refreshed.fields.first { $0.kind == .contact }?.choices.isEmpty == true)
        XCTAssertEqual(effects.performCount, 0)
    }

    func testWrongSkillPickStillRetainsMessage() async throws {
        // Candidates for this utterance (see testProbeCandidates):
        // [imessage_send, summarize_text, email_compose]. The model picks s1.
        let e = ScriptedEngine()
        e.script(whenPromptContains: "long-term memory", logits: ["A": -3, "B": -3, "C": 3])
        e.script(whenPromptContains: "How should", logits: ["A": 5, "B": -3, "C": -3, "D": -3])
        e.script(whenPromptContains: "Which phone action", logits: ["A": 0, "B": 6, "C": 0, "D": 0])
        e.script(whenPromptContains: "explicit confirmation", logits: ["A": 4, "B": -2])
        let (a, effects) = try makeA(e)
        wireDana(effects)
        let turn = try await a.handle("text Dana saying hi")
        var retained = turn.pendingDraft != nil
        if case .needsConfirmation(let card) = turn.reply { retained = card.capabilityID == "imessage_send" }
        XCTAssertTrue(retained, "wrong skill pick must retain the message draft, got \(turn.reply), draft=\(String(describing: turn.pendingDraft))")
    }

    func testFollowUpBodyWithAppWordStaysOnDraft() async throws {
        let (a, effects) = try makeA(toolEngine())
        wireDana(effects)
        let first = try await a.handle("text Dana")
        let d = try XCTUnwrap(first.pendingDraft)
        let db = try SQLiteDB(path: ":memory:")
        let e2 = chatEngine(generated: "Nice post!")
        let a2 = Assistant(reflex: Reflex(engine: e2, telemetry: try TelemetryLog(db: db), source: "test"),
                           memory: try MemoryStore(db: db), actions: RecordingActions(),
                           ledger: try EffectLedger(db: db), effects: effects,
                           cloud: CloudBrainChain([]), isOnline: { false })
        a2.skills = SkillRegistry()
        let second = try await a2.handle("saying I posted it on Instagram", pendingDrafts: [d])
        guard case .needsConfirmation = second.reply else {
            return XCTFail("body containing an app word must stay on the draft, got \(second.reply)")
        }
    }

    func testDiagnosticsCapabilityFieldIsFreeText() {
        ActionDiagnostics.shared.resetForTesting()
        ActionDiagnostics.shared.record(capability: "Dana personal body text", phase: .draft, code: .draftCreated)
        let jsonl = ActionDiagnostics.shared.exportJSONL()
        ActionDiagnostics.shared.resetForTesting()
        XCTAssertFalse(jsonl.contains("Dana personal body text"),
                       "capability is a free String; the secret-free claim is call-site convention, not construction")
    }

    func testNamedGroupRequestsNeverSelectTheFirstContact() async throws {
        let (a, effects) = try makeA(toolEngine())
        wireDana(effects)
        for request in ["text Dana group chat saying hi", "send a message to the Family group saying dinner at 7",
                        "text the \"Family Party\" group chat: hi", "message the group called Dana Friends saying hi"] {
            let turn = try await a.handle(request)
            guard case .clarify(let text) = turn.reply else { XCTFail("\(turn.reply)"); continue }
            XCTAssertTrue(text.contains("group"), text)
            XCTAssertNil(turn.action)
            XCTAssertNil(turn.pendingDraft)
            XCTAssertEqual(effects.performCount, 0)
        }
    }

    func testGroupMentionInMessageBodyIsLiteral() async throws {
        let (a, effects) = try makeA(toolEngine())
        wireDana(effects)
        let turn = try await a.handle("text Dana saying the family group chat moved to 7")
        guard case .needsConfirmation(let card) = turn.reply else { return XCTFail("\(turn.reply)") }
        XCTAssertEqual(card.fields.first { $0.name == "body" }?.value, "the family group chat moved to 7")
    }

    func testGroupNameAnswerDoesNotBindAsAnIndividual() {
        let d = draft(channel: .imessage, body: "hi", lastAsked: .contact)
        guard case .clarifyKeep(let text) = MessageFollowUp.resolve("the Family group chat", drafts: [d], now: now) else {
            return XCTFail("A named group must not become a contact")
        }
        XCTAssertTrue(text.contains("group"))
    }

    func testChannelOnlySuffixLeavesTheBodyMissing() {
        let (d, _) = MessageDraft.retain(utterance: "text Dana on WhatsApp", requestID: UserRequestID(), lowConfidence: false, now: now)
        XCTAssertEqual(d.contact, "Dana")
        XCTAssertEqual(d.channel, .whatsapp)
        XCTAssertNil(d.body)
        XCTAssertEqual(d.lastAsked, .body)
    }

    func testUnmarkedBodyAppWordDoesNotChooseDestination() {
        for text in ["text Dana Instagram is down", "text Dana WhatsApp is down", "text Dana ig is down"] {
            XCTAssertEqual(MessageChannel.parse(in: text), .imessage, text)
        }
    }

    func testMessageBodyKeepsInternalQuotesColonAndURL() {
        for body in ["He said \"hi\" to me", "Meet at 6:30", "https://example.com/page"] {
            let parts = MessageDraft.messageArgs("Text Dana " + body)
            XCTAssertEqual(parts.body, body)
            let d = draft(contact: "Dana", channel: .imessage, lastAsked: .body)
            guard case .completed(let done) = MessageFollowUp.resolve(body, drafts: [d], now: now) else {
                XCTFail("Body was not bound: \(body)"); continue
            }
            XCTAssertEqual(done.body, body)
        }
    }

    func testRepeatedMessageAfterChatAndWrongSkillPickStillStagesReview() async throws {
        let engine = toolEngine()
        let (a, effects) = try makeA(engine)
        wireDana(effects)
        let request = "text Dana saying hii"
        let first = try await a.handle(request)
        guard case .needsConfirmation(let original) = first.reply else { return XCTFail("\(first.reply)") }
        engine.generated = "hii"
        engine.script(whenPromptContains: "How should", logits: ["A": 8, "B": -5, "C": -5, "D": -5])
        _ = try await a.handle("What is 2 + 2?")
        let generations = engine.generatePrompts.count
        engine.script(whenPromptContains: "Which phone action", logits: ["A": 0, "B": 6, "C": 0, "D": 0])
        for _ in 0..<3 {
            let later = try await a.handle(request)
            guard case .needsConfirmation(let card) = later.reply else { XCTFail("\(later.reply)"); continue }
            XCTAssertEqual(card.capabilityID, "imessage_send")
            XCTAssertEqual(card.fields.first { $0.name == "body" }?.value, "hii")
            XCTAssertNotEqual(card.attemptID, original.attemptID)
            XCTAssertEqual(engine.generatePrompts.count, generations)
            XCTAssertEqual(effects.performCount, 0)
        }
    }
}
