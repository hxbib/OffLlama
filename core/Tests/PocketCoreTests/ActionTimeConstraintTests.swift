import Foundation
import XCTest
@testable import PocketCore

/// Positive tests for the independent review's C3/C4/W2 counterexamples. A fake resolver and fake
/// PhoneEffects prove the core contract; they do not prove NSDataDetector, EventKit, or a phone.
final class ActionTimeConstraintTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func assistant(engine: ScriptedEngine) throws -> (Assistant, FakePhoneEffects) {
        let db = try SQLiteDB(path: ":memory:")
        let effects = FakePhoneEffects()
        let assistant = Assistant(reflex: Reflex(engine: engine), memory: try MemoryStore(db: db),
                                  actions: RecordingActions(), ledger: try EffectLedger(db: db, now: { self.now }),
                                  effects: effects, cloud: CloudBrainChain([]), isOnline: { false })
        return (assistant, effects)
    }

    private func calendarEngine() -> ScriptedEngine {
        let engine = ScriptedEngine()
        engine.script(whenPromptContains: "long-term memory", logits: ["A": -3, "B": -3, "C": 3])
        engine.script(whenPromptContains: "How should", logits: ["A": -3, "B": 5, "C": -3, "D": -3])
        engine.script(whenPromptContains: "Which tool", logits: ["A": 0, "B": 6, "C": 0, "D": 0, "E": 0, "F": 0, "G": 0])
        engine.script(whenPromptContains: "explicit confirmation", logits: ["A": 4, "B": -2])
        return engine
    }

    private func calendarSession() throws -> (EffectSession, FakePhoneEffects, CapabilityContract) {
        let effects = FakePhoneEffects()
        let session = EffectSession(ledger: try EffectLedger(db: SQLiteDB(path: ":memory:"), now: { self.now }), effects: effects)
        return (session, effects, try XCTUnwrap(CapabilityCatalog.current(id: "calendar_create")))
    }

    // MARK: C3 calendar duration, attendee, location

    func testCalendarConstraintVariantsRequireCorrectionButSimpleRequestsDoNot() {
        let unsupported = [
            "Schedule a 2-hour planning meeting tomorrow at 3pm",
            "Schedule a meeting for 2 hrs tomorrow at 3pm",
            "Schedule a meeting for 90 min tomorrow at 3pm",
            "Schedule a 90-minute meeting tomorrow at 3pm",
            "Schedule a meeting 3pm-5pm tomorrow",
            "Schedule lunch with Sam tomorrow at noon",
            "Schedule a meeting with Dana tomorrow at 3pm",
            "Schedule a meeting at the office tomorrow at 3pm",
            "Schedule a meeting in the conference room tomorrow at 3pm",
            "Schedule a meeting at 123 Main Street tomorrow at 3pm",
            "Schedule a meeting tomorrow 9am-11am",
            "Schedule a meeting from 3pm to 5pm tomorrow",
            "Schedule a meeting between 9am and 11am tomorrow",
            "Schedule a meeting for two hours tomorrow at 3pm",
            "Schedule a meeting on November 5 at 3pm",
        ]
        for utterance in unsupported {
            XCTAssertNotNil(ActionValidation.requestIssue(capabilityID: "calendar_create", utterance: utterance), utterance)
        }
        XCTAssertNotNil(ActionValidation.requestIssue(capabilityID: "reminder_create",
                                                      utterance: "Remind me to call Mom on Nov 5 at 9am"),
                        "an explicit month/day must not be reduced to its clock time")
        XCTAssertNil(ActionValidation.requestIssue(capabilityID: "reminder_create",
                                                   utterance: "Remind me to buy November 5 concert tickets tomorrow at 9am"),
                     "a month name in the title is not an explicit date request")
        let durationArgs = ArgumentExtractor.heuristic(tool: "create_event",
                                                       utterance: "Schedule a 2-hour planning meeting tomorrow at 3pm")
        XCTAssertEqual(durationArgs["title"], "2-hour planning meeting")
        XCTAssertEqual(durationArgs["when"], "tomorrow at 3pm",
                       "the supported title and time are preserved for the correction; no fake duration field is added")
        for utterance in ["Schedule a meeting tomorrow at 3pm",
                          "Schedule lunch tomorrow at noon",
                          "Schedule a meeting in 20 minutes",
                          "Schedule a meeting tomorrow at 9am",
                          "Schedule a meeting tomorrow at 3pm to discuss the 2-hour plan",
                          "Schedule a meeting tomorrow at 3pm about the 90-minute review"] {
            XCTAssertNil(ActionValidation.requestIssue(capabilityID: "calendar_create", utterance: utterance), utterance)
        }
    }

    func testCalendarSimpleRequestAlwaysShowsCompleteReviewAndActsOnlyAfterConfirm() async throws {
        let (session, effects, contract) = try calendarSession()
        let start = now.addingTimeInterval(86_400)
        effects.instantPhrases["tomorrow at 3pm"] = .parsed(start)
        let result = try await session.evaluate(
            requestID: UserRequestID(), capability: .compiled(contract),
            raw: PlannedAction(tool: "create_event", args: ["title": "meeting", "when": "tomorrow at 3pm"]),
            modelAskedConfirm: false, explicitDraft: false)
        guard case .staged(let card) = result else { return XCTFail("modelMayAct must not bypass the calendar review: \(result)") }
        XCTAssertTrue(card.canConfirm)
        XCTAssertTrue(card.reviewSentence.contains("one-hour"), card.reviewSentence)
        XCTAssertTrue(card.reviewSentence.contains("no invitations"), card.reviewSentence)
        XCTAssertTrue(card.reviewSentence.contains("no location"), card.reviewSentence)
        XCTAssertEqual(effects.performCount, 0, "staging must not write an event")

        let done = try await session.confirm(attemptID: card.attemptID, edits: [], expectedRevision: card.revision)
        guard case .finished(let effect) = done else { return XCTFail("\(done)") }
        XCTAssertTrue(effect.phase.isCommitted)
        XCTAssertEqual(effects.performCount, 1)
        XCTAssertEqual(effects.saveCount, 1)
        XCTAssertEqual(EffectLedger.textArg(effects.performed[0].action, "title"), "meeting")
        guard case .instant(let performed)? = effects.performed[0].action.arguments["when"] else { return XCTFail() }
        XCTAssertEqual(Int(performed.timeIntervalSince1970 / 60), Int(start.timeIntervalSince1970 / 60))
        XCTAssertTrue(effect.summary.contains("one hour"), effect.summary)
        XCTAssertTrue(effect.summary.contains("no invitations"), effect.summary)
        XCTAssertTrue(effect.summary.contains("no location"), effect.summary)
    }

    func testCalendarUnsupportedRequestsNeverReachEffects() async throws {
        let (assistant, effects) = try assistant(engine: calendarEngine())
        let unsupported = ["Schedule a 2-hour planning meeting tomorrow at 3pm",
                           "Schedule a meeting with Dana tomorrow at 3pm",
                           "Schedule a meeting at the office tomorrow at 3pm",
                           "Schedule a meeting 3pm-5pm tomorrow"]
        for utterance in unsupported {
            let turn = try await assistant.handle(utterance)
            guard case .clarify(let question) = turn.reply else { return XCTFail("\(utterance) -> \(turn.reply)") }
            XCTAssertTrue(question.contains("one-hour") || question.contains("one exact time"), question)
        }
        XCTAssertEqual(effects.performCount, 0)
        XCTAssertEqual(effects.saveCount, 0)

        // Even an already-extracted action cannot turn a duration-bearing title into a silent one-hour write.
        let (session, directEffects, contract) = try calendarSession()
        let direct = try await session.evaluate(
            requestID: UserRequestID(), capability: .compiled(contract),
            raw: PlannedAction(tool: "create_event", args: ["title": "2-hour planning meeting", "when": "tomorrow at 3pm"]),
            modelAskedConfirm: false, explicitDraft: false)
        guard case .finished(let refused) = direct else { return XCTFail("a two-hour title reached a card: \(direct)") }
        XCTAssertTrue(refused.summary.contains("one-hour"), refused.summary)
        XCTAssertEqual(directEffects.performCount, 0)
    }

    // MARK: C4 time extraction and validation

    func testTimeExtractionPreservesTheWholePhraseAndResolverInput() {
        let cases: [(String, String, String, Bool)] = [
            ("create_reminder", "Remind me to call Mom the day after tomorrow at 9am", "the day after tomorrow at 9am", true),
            ("create_reminder", "Remind me to call Mom tomorrow at noon", "tomorrow at noon", true),
            ("create_reminder", "Remind me to call Mom tomorrow about 3pm", "tomorrow about 3pm", false),
            ("create_reminder", "Remind me to call Mom at noon tomorrow", "noon tomorrow", true),
            ("create_reminder", "Remind me to call Mom tonight at 9pm", "tonight at 9pm", true),
            ("create_reminder", "Remind me to call Mom yesterday morning at 9am", "yesterday morning at 9am", false),
            ("create_reminder", "Remind me to call Mom 3 days ago at 9am", "3 days ago at 9am", false),
            ("create_reminder", "Remind me to call Mom last night at 9pm", "last night at 9pm", false),
            ("create_reminder", "Remind me to call Mom tomorrow at 9am and 11am", "tomorrow at 9am and 11am", false),
            ("create_event", "Schedule a meeting tomorrow at 9am and 11am", "tomorrow at 9am and 11am", false),
            ("create_event", "Schedule a meeting tomorrow 9am-11am", "tomorrow 9am-11am", false),
            ("create_event", "Schedule a meeting tomorrow at 7pm Eastern", "tomorrow at 7pm Eastern", false),
            ("create_event", "Schedule a meeting tomorrow at 7pm ET", "tomorrow at 7pm ET", false),
            ("create_event", "Schedule a meeting tomorrow at 7pm Eastern Standard Time", "tomorrow at 7pm Eastern Standard Time", false),
            ("create_event", "Schedule a meeting tomorrow at 7pm Berlin", "tomorrow at 7pm Berlin", false),
            ("create_event", "Schedule a meeting tomorrow at 9am in berlin", "tomorrow at 9am in berlin", false),
        ]
        for (tool, utterance, expected, supported) in cases {
            let args = ArgumentExtractor.heuristic(tool: tool, utterance: utterance)
            XCTAssertEqual(args["when"], expected, utterance)
            var resolvedPhrase: String?
            let parsed = InstantParser.parse(expected, dateResolver: { phrase in
                resolvedPhrase = phrase
                return supported ? self.now.addingTimeInterval(86_400) : nil
            })
            if supported {
                guard case .parsed = parsed else { return XCTFail("\(utterance) -> \(parsed)") }
                XCTAssertEqual(resolvedPhrase, expected, "the resolver must receive the whole phrase")
            } else {
                guard case .unparsed = parsed else { return XCTFail("\(utterance) accepted -> \(parsed)") }
                XCTAssertNil(resolvedPhrase, "an unsupported phrase must never reach the resolver")
            }
        }
        XCTAssertEqual(ArgumentExtractor.heuristic(tool: "create_reminder",
                                                   utterance: "Remind me to call Mom the day after tomorrow at 9am")["title"],
                       "call Mom")
        XCTAssertEqual(ArgumentExtractor.heuristic(tool: "create_event",
                                                   utterance: "Schedule a meeting the day after tomorrow at 3pm")["title"],
                       "meeting")
    }

    func testTimeParserRefusesZonesRangesMultipleTimesAndPast() {
        let refused = ["tomorrow at 7pm Eastern",
                       "tomorrow at 7pm ET",
                       "tomorrow at 7pm Berlin",
                       "tomorrow at 9am Berlin time",
                       "tomorrow at 9am in Berlin",
                       "tomorrow at 9am and 11am",
                       "tomorrow at 9am, 11am",
                       "tomorrow 9am-11am",
                       "tomorrow at 9am to 11am",
                       "tomorrow at 9am or 11am",
                       "tomorrow about 3pm",
                       "around 3pm",
                       "yesterday at 9am",
                       "yesterday morning at 9am",
                       "3 days ago at 9am",
                       "last night at 9pm",
                       "last Friday at 3pm",
                       "tonight",
                       "tomorrow",
                       "at 25:00",
                       "at 7:99pm"]
        for phrase in refused {
            var called = false
            let parsed = InstantParser.parse(phrase, now: now, dateResolver: { _ in called = true; return self.now.addingTimeInterval(3600) })
            guard case .unparsed = parsed else { return XCTFail("\(phrase) accepted -> \(parsed)") }
            XCTAssertFalse(called, phrase)
        }
        let pastArgs = ["time": "yesterday at 9am", "label": "test"]
        XCTAssertFalse(ActionValidation.issues(contract: CapabilityCatalog.current(id: "alarm_create")!, args: pastArgs).isEmpty)
    }

    func testNoonMidnightTonightAndDayAfterTomorrowStayExact() {
        for phrase in ["tomorrow at noon", "midnight", "tonight at 9pm", "day after tomorrow at 9am"] {
            var received: String?
            let parsed = InstantParser.parse(phrase, now: now, dateResolver: { received = $0; return self.now.addingTimeInterval(86_400) })
            guard case .parsed = parsed else { return XCTFail("\(phrase) -> \(parsed)") }
            XCTAssertEqual(received, phrase)
        }
    }

    func testPastAlarmAndReminderStageCorrectionAndNeverExecute() async throws {
        let past = "yesterday at 9am"
        let resolvedPast = now.addingTimeInterval(-86_400)
        for (id, args) in [("alarm_create", ["time": past, "label": "test"]),
                           ("reminder_create", ["title": "test", "when": past])] {
            let contract = try XCTUnwrap(CapabilityCatalog.current(id: id))
            XCTAssertFalse(ActionValidation.issues(contract: contract, args: args).isEmpty, id)
            let effects = FakePhoneEffects()
            effects.instantPhrases[past] = .parsed(resolvedPast)
            let session = EffectSession(ledger: try EffectLedger(db: SQLiteDB(path: ":memory:"), now: { self.now }), effects: effects)
            let result = try await session.evaluate(requestID: UserRequestID(), capability: .compiled(contract),
                                                    raw: PlannedAction(tool: "skill:\(id)", args: args),
                                                    modelAskedConfirm: false, explicitDraft: false)
            guard case .staged(let card) = result else { return XCTFail("\(id): \(result)") }
            XCTAssertFalse(card.canConfirm, id)
            let confirmed = try await session.confirm(attemptID: card.attemptID, edits: [], expectedRevision: card.revision)
            guard case .staged(let still) = confirmed else { return XCTFail("\(id) executed a past time: \(confirmed)") }
            XCTAssertFalse(still.canConfirm, id)
            XCTAssertEqual(effects.performCount, 0, id)
        }
    }

    func testRelativeHandoffThatResolvedPastDoesNotBecomeConfirmable() async throws {
        let phrase = "tonight at 9pm"
        let contract = try XCTUnwrap(CapabilityCatalog.current(id: "alarm_create"))
        let effects = FakePhoneEffects()
        effects.instantPhrases[phrase] = .parsed(now.addingTimeInterval(-3_600))
        let session = EffectSession(ledger: try EffectLedger(db: SQLiteDB(path: ":memory:"), now: { self.now }), effects: effects)
        let result = try await session.evaluate(requestID: UserRequestID(), capability: .compiled(contract),
                                                raw: PlannedAction(tool: "skill:alarm_create", args: ["time": phrase, "label": "wake"]),
                                                modelAskedConfirm: false, explicitDraft: false)
        guard case .staged(let card) = result else { return XCTFail("\(result)") }
        XCTAssertFalse(card.canConfirm)
        let confirmed = try await session.confirm(attemptID: card.attemptID, edits: [], expectedRevision: card.revision)
        guard case .staged(let still) = confirmed else { return XCTFail("a past-resolved phrase was executed: \(confirmed)") }
        XCTAssertFalse(still.canConfirm)
        XCTAssertEqual(effects.performCount, 0)
    }

    func testFutureAlarmHandoffKeepsTheExactPhrase() async throws {
        let phrase = "tomorrow at 9am"
        let contract = try XCTUnwrap(CapabilityCatalog.current(id: "alarm_create"))
        let effects = FakePhoneEffects()
        effects.instantPhrases[phrase] = .parsed(now.addingTimeInterval(86_400))
        let session = EffectSession(ledger: try EffectLedger(db: SQLiteDB(path: ":memory:"), now: { self.now }), effects: effects)
        let result = try await session.evaluate(requestID: UserRequestID(), capability: .compiled(contract),
                                                raw: PlannedAction(tool: "skill:alarm_create", args: ["time": phrase, "label": "wake"]),
                                                modelAskedConfirm: false, explicitDraft: false)
        guard case .staged(let card) = result else { return XCTFail("\(result)") }
        XCTAssertTrue(card.canConfirm)
        _ = try await session.confirm(attemptID: card.attemptID, edits: [], expectedRevision: card.revision)
        XCTAssertEqual(effects.performCount, 1)
        XCTAssertEqual(text(effects.performed[0].action, "time"), phrase, "the Shortcut receives the reviewed words, not a rewritten date")
    }

    func testDatetimeTextLimitAppliesToArgumentsAndExecution() async throws {
        let phrase = String(repeating: "x", count: 2_500) + " at 9am"
        for (id, args) in [("alarm_create", ["time": phrase, "label": "test"]),
                           ("reminder_create", ["title": "test", "when": phrase])] {
            let contract = try XCTUnwrap(CapabilityCatalog.current(id: id))
            XCTAssertFalse(ActionValidation.issues(contract: contract, args: args).isEmpty, id)
            let effects = FakePhoneEffects()
            effects.instantPhrases[phrase] = .parsed(now.addingTimeInterval(86_400))
            let session = EffectSession(ledger: try EffectLedger(db: SQLiteDB(path: ":memory:"), now: { self.now }), effects: effects)
            let result = try await session.evaluate(requestID: UserRequestID(), capability: .compiled(contract),
                                                    raw: PlannedAction(tool: "skill:\(id)", args: args),
                                                    modelAskedConfirm: false, explicitDraft: false)
            guard case .staged(let card) = result else { return XCTFail("\(id): \(result)") }
            XCTAssertFalse(card.canConfirm, id)
            let confirmed = try await session.confirm(attemptID: card.attemptID, edits: [], expectedRevision: card.revision)
            guard case .staged = confirmed else { return XCTFail("\(id) executed an over-limit time: \(confirmed)") }
            XCTAssertEqual(effects.performCount, 0, id)
        }
    }

    func testStaleCalendarSnapshotCannotExecuteUnderTheNewPolicy() async throws {
        let (db, ledger) = try makeLedger(now: { self.now })
        let action = BoundAction(capabilityID: "calendar_create", contractVersion: 2, title: "Add a calendar event",
                                 arguments: ["title": .text("old two-hour request"),
                                             "when": .instant(self.now.addingTimeInterval(86_400))],
                                 source: .userUtterance, executor: .eventCreate,
                                 timeZoneID: TimeZone(identifier: "America/New_York")!.identifier)
        let record = try ledger.insertAwaiting(requestID: UserRequestID(), capabilityID: action.capabilityID,
                                                contractVersion: action.contractVersion, action: action,
                                                pause: nil, notice: "")
        let recovery = try ledger.recover(now: now)
        XCTAssertTrue(recovery.showAgain.isEmpty)
        XCTAssertEqual(recovery.unresolved.map(\.attemptID), [record.attemptID])
        let effects = FakePhoneEffects()
        let result = try await EffectSession(ledger: ledger, effects: effects)
            .confirm(attemptID: record.attemptID, edits: [], expectedRevision: nil)
        guard case .staged(let stale) = result else { return XCTFail("\(result)") }
        XCTAssertFalse(stale.canConfirm)
        XCTAssertEqual(effects.performCount, 0)
        _ = db
    }

    // MARK: W2 recipients and attachments

    func testRecipientListsAndAttachmentsRequireCorrection() {
        let cases = [
            ("email_compose", "Email Dana,Sam about the launch"),
            ("email_compose", "Email Dana, Sam about the launch"),
            ("email_compose", "Email dana, sam about the launch"),
            ("email_compose", "Email Dana + Sam about the launch"),
            ("email_compose", "Email Dana; Sam about the launch"),
            ("email_compose", "Email Dana/Sam about the launch"),
            ("email_compose", "Email Dana and Sam saying hello"),
            ("imessage_send", "Text Sam,Dana that I am late"),
            ("imessage_send", "Text Sam, Dana that I am late"),
            ("imessage_send", "Text sam, dana that I am late"),
            ("imessage_send", "Text Sam + Dana that I am late"),
            ("instagram_dm", "DM @sam,@dana saying hi"),
            ("x_dm", "DM @Sam, @Dana saying hi"),
            ("email_compose", "Email Dana with the report attached"),
            ("email_compose", "Email Dana with an attachment"),
            ("email_compose", "Email Dana and copy Sam on it"),
            ("imessage_send", "Text Sam with an attachment"),
            ("email_compose", "Email Dana, cc Sam"),
            ("email_compose", "Email Dana, bcc Sam"),
            ("imessage_send", "Send Dana and Sam a text about the launch"),
            ("imessage_send", "Send a message to Dana and Sam about the launch"),
        ]
        for (id, utterance) in cases {
            XCTAssertNotNil(ActionValidation.requestIssue(capabilityID: id, utterance: utterance), "\(id): \(utterance)")
        }
    }

    func testMessageBodyMentionsAreNotCommandOptions() {
        let cases = [
            ("imessage_send", "Text Sam saying I'll attach the report tomorrow"),
            ("imessage_send", "Text Sam: I'll cc Dana when I reply"),
            ("imessage_send", #"Text Sam "please attach the file tomorrow""#),
            ("email_compose", "Email Dana saying the attachment is on the shared drive"),
            ("email_compose", "Email Dana about the launch"),
            ("email_compose", "Email Dana about the schedule"),
            ("email_compose", "Email Dana that the schedule works"),
            ("email_compose", "Email Dana, subject: launch"),
            ("imessage_send", "Text Sam that I'm running 10 minutes late"),
            ("imessage_send", "Send Dana a text saying I'll attach the file"),
            ("email_compose", "Send Dana an email about the schedule"),
        ]
        for (id, utterance) in cases {
            XCTAssertNil(ActionValidation.requestIssue(capabilityID: id, utterance: utterance), "\(id): \(utterance)")
        }
    }

    func testMalformedRecipientListDoesNotBecomeConfirmableBody() async throws {
        let engine = ScriptedEngine()
        engine.script(whenPromptContains: "long-term memory", logits: ["A": -3, "B": -3, "C": 3])
        engine.script(whenPromptContains: "How should", logits: ["A": 5, "B": -3, "C": -3, "D": -3])
        let (assistant, effects) = try assistant(engine: engine)
        assistant.skills = SkillRegistry()
        let turn = try await assistant.handle("Email Dana, Sam: launch update")
        guard case .clarify(let question) = turn.reply else { return XCTFail("\(turn.reply)") }
        XCTAssertTrue(question.contains("one recipient"), question)
        XCTAssertNil(turn.action)
        XCTAssertEqual(effects.performCount, 0)

        let contract = try XCTUnwrap(CapabilityCatalog.current(id: "email_compose"))
        let args = ["contact": "Dana", "subject": "", "body": ", Sam: launch update"]
        XCTAssertTrue(ActionValidation.issues(contract: contract, args: args).contains { $0.field == "body" && $0.code == .unsupported })
        let session = EffectSession(ledger: try EffectLedger(db: SQLiteDB(path: ":memory:")), effects: FakePhoneEffects())
        let result = try await session.evaluate(requestID: UserRequestID(), capability: .compiled(contract),
                                                raw: PlannedAction(tool: "skill:email_compose", args: args),
                                                modelAskedConfirm: false, explicitDraft: false)
        guard case .finished(let effect) = result else { return XCTFail("a malformed body reached a card: \(result)") }
        XCTAssertTrue(effect.summary.contains("one recipient"), effect.summary)
    }
}
