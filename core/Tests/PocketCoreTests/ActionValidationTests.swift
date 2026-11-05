import XCTest
@testable import PocketCore

final class ActionValidationTests: XCTestCase {
    func testAllCapabilitiesHaveExportableRulesAndRejectUnknownFields() throws {
        let descriptions = ActionContractDescription.all
        XCTAssertEqual(Set(descriptions.map { $0.capability.id }), Set(CapabilityCatalog.all.map(\.id)))
        XCTAssertTrue(Set(BuiltinSkills.all.map(\.id)).isSubset(of: Set(descriptions.map { $0.capability.id })))
        for d in descriptions {
            XCTAssertEqual(Set(d.argumentRules.keys), Set(d.capability.arguments.map(\.name)), d.capability.id)
            let issues = ActionValidation.issues(contract: d.capability, args: ["unsupported_option": "yes"])
            XCTAssertTrue(issues.contains { $0.field == "unsupported_option" && $0.code == .unsupported })
            for spec in d.capability.arguments where spec.required {
                XCTAssertTrue(issues.contains { $0.field == spec.name && $0.code == .missing })
            }
            if d.capability.effect == .externalHandoff { XCTAssertEqual(d.capability.confirmation, .always) }
        }
        XCTAssertNoThrow(try JSONDecoder().decode([ActionContractDescription].self, from: JSONEncoder().encode(descriptions)))
    }

    func testTimerRejectsInvalidAndSupportsCompoundDurations() async throws {
        let ledger = try EffectLedger(db: SQLiteDB(path: ":memory:"))
        let effects = FakePhoneEffects()
        let session = EffectSession(ledger: ledger, effects: effects)
        let contract = try validationHandoff("timer_start")
        for value in ["0 minutes", "-5 minutes", "NaN", "90", "100 hours", "1 hour then 2 minutes"] {
            let result = try await session.evaluate(requestID: UserRequestID(), capability: .compiled(contract),
                raw: PlannedAction(tool: "skill:timer_start", args: ["duration": value]), modelAskedConfirm: false, explicitDraft: false)
            guard case .staged(let card) = result else { return XCTFail("\(value): \(result)") }
            XCTAssertFalse(card.canConfirm, value)
            let retried = try await session.confirm(attemptID: card.attemptID, edits: [], expectedRevision: card.revision)
            guard case .staged = retried else { return XCTFail("invalid timer executed") }
        }
        XCTAssertEqual(effects.performCount, 0)
        let result = try await session.evaluate(requestID: UserRequestID(), capability: .compiled(contract),
            raw: PlannedAction(tool: "skill:timer_start", args: ["duration": "1 hour 30 minutes"]), modelAskedConfirm: false, explicitDraft: false)
        guard case .staged(let card) = result else { return XCTFail("\(result)") }
        XCTAssertTrue(card.canConfirm)
        _ = try await session.confirm(attemptID: card.attemptID, edits: [], expectedRevision: card.revision)
        XCTAssertEqual(effects.performCount, 1)
        XCTAssertEqual(EffectLedger.textArg(effects.performed[0].action, "duration"), "1 hour 30 minutes")
        let skill = try XCTUnwrap(BuiltinSkills.all.first { $0.id == "timer_start" })
        XCTAssertEqual(SkillArgs.extract(skill, utterance: "timer for 1 hour 30 minutes")["duration"], "1 hour 30 minutes")
        XCTAssertEqual(SkillArgs.extract(skill, utterance: "timer for -5 minutes")["duration"], "-5 minutes")
    }

    func testEditedTextIsNeverTruncatedAndCanBeRepaired() async throws {
        let effects = FakePhoneEffects()
        let session = EffectSession(ledger: try EffectLedger(db: SQLiteDB(path: ":memory:")), effects: effects)
        let contract = try validationHandoff("notes_create")
        let long = String(repeating: "a", count: 2001)
        let result = try await session.evaluate(requestID: UserRequestID(), capability: .compiled(contract),
            raw: PlannedAction(tool: "skill:notes_create", args: ["text": long]), modelAskedConfirm: false, explicitDraft: false)
        guard case .staged(let card) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(card.fields.first { $0.name == "text" }?.value, long)
        XCTAssertFalse(card.canConfirm)
        let invalid = try await session.confirm(attemptID: card.attemptID, edits: [.init(field: "text", value: .text(long + "b"))], expectedRevision: card.revision)
        guard case .staged(let second) = invalid else { return XCTFail("long edited text executed") }
        XCTAssertEqual(second.fields.first { $0.name == "text" }?.value, long + "b")
        XCTAssertEqual(effects.performCount, 0)
        let repaired = try await session.edit(attemptID: card.attemptID, edits: [.init(field: "text", value: .text("$25 for lunch"))], expectedRevision: second.revision)
        XCTAssertTrue(repaired.canConfirm, "literal currency is not an output binding")
        _ = try await session.confirm(attemptID: card.attemptID, edits: [], expectedRevision: repaired.revision)
        XCTAssertEqual(EffectLedger.textArg(effects.performed[0].action, "text"), "$25 for lunch")
    }

    func testMissingAndInvalidHandlesRemainEditable() async throws {
        let effects = FakePhoneEffects()
        let session = EffectSession(ledger: try EffectLedger(db: SQLiteDB(path: ":memory:")), effects: effects)
        let contract = try XCTUnwrap(CapabilityCatalog.current(id: "x_dm"))
        let result = try await session.evaluate(requestID: UserRequestID(), capability: .compiled(contract),
            raw: PlannedAction(tool: "skill:x_dm", args: ["contact": "Sam Lee"]), modelAskedConfirm: false, explicitDraft: false)
        guard case .staged(let card) = result else { return XCTFail("\(result)") }
        XCTAssertFalse(card.canConfirm)
        XCTAssertEqual(card.fields.first { $0.name == "body" }?.value, "")
        let repaired = try await session.edit(attemptID: card.attemptID,
            edits: [.init(field: "contact", value: .text("sam_lee")), .init(field: "body", value: .text("Hello!"))], expectedRevision: card.revision)
        XCTAssertTrue(repaired.canConfirm)
        XCTAssertEqual(effects.performCount, 0)
    }

    func testUnsafeURLsAndTypedBypassAreRejected() throws {
        let contract = try XCTUnwrap(CapabilityCatalog.current(id: "open_url"))
        for raw in ["javascript:alert(1)", "file:///secret", "https://user:pass@example.com", "https://", "https://example.com/a b"] {
            XCTAssertFalse(ActionValidation.issues(contract: contract, args: ["url": raw]).isEmpty, raw)
        }
        let action = BoundAction(capabilityID: contract.id, contractVersion: contract.version, title: contract.title,
            arguments: ["url": .url(URL(string: "file:///secret")!)], source: .userEdited, executor: contract.executor)
        XCTAssertFalse(EffectLedger.readiness(action, contract: contract, now: Date()).ready)
        XCTAssertTrue(ActionValidation.issues(contract: contract, args: ["url": "https://example.com/path?q=a%20b"]).isEmpty)
    }

    func testAmbiguousClockNeverUsesDetectorGuess() {
        for phrase in ["tomorrow", "at 6", "at 6:30", "tonight", "at 25:00", "at 7:99pm", "at 7pm or 8pm", "at 7pm EST"] {
            var called = false
            let parsed = InstantParser.parse(phrase) { _ in called = true; return Date().addingTimeInterval(3600) }
            guard case .unparsed = parsed else { return XCTFail("guessed \(phrase)") }
            XCTAssertFalse(called, phrase)
        }
        for phrase in ["tomorrow at 6:30pm", "at 18:30", "in 20 minutes", "noon"] {
            guard case .parsed = InstantParser.parse(phrase, dateResolver: { _ in Date().addingTimeInterval(3600) }) else { return XCTFail(phrase) }
        }
    }

    func testUnsupportedRequestsAreNotSilentlySimplified() {
        let cases = [("calendar_create", "schedule lunch every Friday at 1pm"),
                     ("calendar_create", "schedule lunch for 2 hours at 1pm"),
                     ("reminder_create", "remind me when I arrive home"),
                     ("flashlight_toggle", "turn on the flashlight"),
                     ("email_compose", "email Sam and Dana saying hello")]
        for (id, text) in cases { XCTAssertNotNil(ActionValidation.requestIssue(capabilityID: id, utterance: text), text) }
        XCTAssertNil(ActionValidation.requestIssue(capabilityID: "flashlight_toggle", utterance: "toggle the flashlight"))
        XCTAssertNil(ActionValidation.requestIssue(capabilityID: "imessage_send", utterance: "text Sam saying attach the file tomorrow"))
    }

    func testConfirmedReadCannotAcquireLaterSharedInput() async throws {
        let engine = ScriptedEngine(); engine.generated = "summary"
        let db = try SQLiteDB(path: ":memory:")
        let ledger = try EffectLedger(db: db)
        let effects = FakePhoneEffects()
        let a = Assistant(reflex: Reflex(engine: engine), memory: try MemoryStore(db: db), actions: RecordingActions(),
                          ledger: ledger, effects: effects, cloud: CloudBrainChain([]), isOnline: { false })
        a.skills = SkillRegistry()
        let contract = try XCTUnwrap(CapabilityCatalog.current(id: "email_digest"))
        let session = EffectSession(ledger: ledger, effects: effects)
        let absent = try session.stageRead(requestID: UserRequestID(), contract: contract, raw: .init(tool: "skill:email_digest", args: [:]), sharedText: nil)
        let original = try session.stageRead(requestID: UserRequestID(), contract: contract, raw: .init(tool: "skill:email_digest", args: [:]), sharedText: "Original private document")
        SharedInbox.shared.put("Wrong later document")
        defer { _ = SharedInbox.shared.take() }
        _ = try await a.confirmEffect(absent.attemptID, edits: [])
        XCTAssertTrue(engine.generatePrompts.isEmpty)
        _ = try await a.confirmEffect(original.attemptID, edits: [])
        XCTAssertTrue(engine.generatePrompts.last?.contains("Original private document") == true)
        XCTAssertFalse(engine.generatePrompts.last?.contains("Wrong later document") == true)
        XCTAssertEqual(effects.performCount, 0)
    }
}

// Synthetic ready handoffs exercise validation without claiming bundled Shortcut support.
func validationHandoff(_ id: String) throws -> CapabilityContract {
    var contract = try XCTUnwrap(CapabilityCatalog.current(id: id))
    if contract.availability == .notWired {
        contract.id = "validation_" + id
        contract.availability = .ready
    }
    return contract
}
