import XCTest
@testable import PocketCore

final class ActionPlanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func fixture(path: String = ":memory:") throws -> (SQLiteDB, EffectSession, FakePhoneEffects) {
        let (db, ledger) = try makeLedger(path: path, now: { self.now })
        let effects = FakePhoneEffects()
        let dana = candidate("Dana", id: "dana", methods: [phone("mobile", "5550100")])
        effects.contactQueries["Dana"] = ContactLookup(access: .full, matches: [dana])
        effects.contactIDs["dana"] = ContactLookup(access: .full, matches: [dana])
        effects.instantPhrases["tomorrow at noon"] = .parsed(now.addingTimeInterval(7200))
        return (db, EffectSession(ledger: ledger, effects: effects), effects)
    }

    private func inputs(dependent: Bool = true, producer: String = "calendar_create") -> [PlanStepInput] {
        [PlanStepInput(capabilityID: producer, arguments: ["title": "Lunch", "when": "tomorrow at noon"]),
         PlanStepInput(capabilityID: "imessage_send", arguments: dependent ? ["contact": "Dana"] : ["contact": "Dana", "body": "hi"],
            messageFrom: dependent ? PlanDependency(stepIndex: 0, field: .summary) : nil)]
    }

    private func card(_ plan: ActionPlan, _ index: Int) throws -> DraftCard {
        guard case .review(let card) = plan.steps[index].presentation else {
            XCTFail("Expected review card, got \(plan.steps[index].presentation)")
            throw ActionPlanError.corruptPlan
        }
        return card
    }

    func testDependentUsesVerifiedReceiptAndNeedsFreshReview() async throws {
        let (_, session, effects) = try fixture()
        let request = UserRequestID()
        let plan = try await session.stagePlan(requestID: request, steps: inputs())
        let event = try card(plan, 0), message = try card(plan, 1)
        XCTAssertTrue(event.canConfirm)
        XCTAssertFalse(message.canConfirm)
        XCTAssertEqual(effects.performCount, 0)
        _ = try await session.confirm(attemptID: message.attemptID, edits: [], expectedRevision: message.revision)
        XCTAssertEqual(effects.performCount, 0)

        let readBack = now.addingTimeInterval(7220)
        effects.handler = { action, _ in
            if case .eventCreate = action.executor {
                return EffectReport(boundary: .observed(.eventKit(.init(identifier: "verified-event", title: "Lunch",
                    instant: readBack, attemptTokenFound: true))))
            }
            return EffectReport(boundary: .observed(.message(.acceptedOrQueued)))
        }
        _ = try await session.confirm(attemptID: event.attemptID, edits: [], expectedRevision: event.revision)
        let refreshed = try XCTUnwrap(session.refreshPlan(requestID: request))
        let filled = try card(refreshed, 1)
        XCTAssertTrue(filled.canConfirm)
        let expected = "Lunch · " + InstantText.full(readBack, timeZoneID: TimeZone.current.identifier)
        XCTAssertEqual(filled.fields.first { $0.name == "body" }?.value, expected)
        XCTAssertGreaterThan(filled.revision, message.revision)
        _ = try await session.confirm(attemptID: filled.attemptID, edits: [], expectedRevision: message.revision)
        _ = try await session.confirm(attemptID: filled.attemptID, edits: [])
        XCTAssertEqual(effects.performCount, 1, "stale or absent displayed revision cannot confirm a plan step")
        _ = try await session.confirm(attemptID: filled.attemptID, edits: [], expectedRevision: filled.revision)
        XCTAssertEqual(effects.performCount, 2)
        XCTAssertEqual(text(effects.performed.last!.action, "body"), expected)
        _ = try session.refreshPlan(requestID: request)
        XCTAssertEqual(effects.performCount, 2)
    }

    func testEveryNonProducerOutcomeBlocksDependency() async throws {
        let phases: [AttemptPhase] = [.claimed, .ambiguous(.saveUnverified), .settled(.cancelled(.userCard)),
            .settled(.failed(.unavailable)), .settled(.handedOff(.systemAcceptedURL)),
            .settled(.sheet(.mailDraftSaved)), .settled(.sheet(.messagesQueuedOrSent)),
            .settled(.committed(.memoryFact(id: "memory"))), .settled(.read(ReadReceipt(text: "saved")))]
        for phase in phases {
            let (_, session, effects) = try fixture()
            let request = UserRequestID()
            let plan = try await session.stagePlan(requestID: request, steps: inputs())
            let first = try card(plan, 0), second = try card(plan, 1)
            _ = try session.ledger.claim(attemptID: first.attemptID, expectedRevision: first.revision, action: nil)
            if phase != .claimed { try session.ledger.record(attemptID: first.attemptID, phase: phase) }
            let refreshed = try XCTUnwrap(session.refreshPlan(requestID: request))
            XCTAssertFalse(try card(refreshed, 1).canConfirm, "\(phase)")
            for suppliedAction in [nil, try session.ledger.load(second.attemptID)?.action] {
                let result = try session.ledger.claim(attemptID: second.attemptID, expectedRevision: second.revision, action: suppliedAction)
                guard case .mismatch = result else { XCTFail("\(phase) produced \(result)"); continue }
            }
            XCTAssertEqual(effects.performCount, 0)
        }
    }

    func testIndependentMessageDoesNotWaitForReminder() async throws {
        let (_, session, effects) = try fixture()
        let request = UserRequestID()
        let plan = try await session.stagePlan(requestID: request, steps: inputs(dependent: false, producer: "reminder_create"))
        XCTAssertEqual(effects.performCount, 0, "even modelMayAct steps start as review cards")
        let message = try card(plan, 1)
        _ = try await session.confirm(attemptID: message.attemptID, edits: [], expectedRevision: message.revision)
        XCTAssertEqual(effects.performed.first?.action.capabilityID, "imessage_send")
        let reminder = try card(plan, 0)
        _ = try session.cancel(attemptID: reminder.attemptID)
        XCTAssertEqual(effects.performCount, 1)
    }

    func testUnsupportedProducerAndConsumerNeverClaim() async throws {
        let (_, session, effects) = try fixture()
        let plan = try await session.stagePlan(requestID: UserRequestID(), steps: inputs(producer: "uber_ride"))
        for step in plan.steps {
            guard case .unsupported = step.presentation else { XCTFail("\(step.presentation)"); continue }
            for action in [nil, try session.ledger.load(step.attemptID)?.action] {
                let claim = try session.ledger.claim(attemptID: step.attemptID, expectedRevision: 0, action: action)
                guard case .mismatch = claim else { XCTFail("\(claim)"); continue }
            }
        }
        XCTAssertEqual(effects.performCount, 0)
    }

    func testEditedProducerMaterializesOnlyFinalReceipt() async throws {
        let (_, session, effects) = try fixture()
        let request = UserRequestID()
        let plan = try await session.stagePlan(requestID: request, steps: inputs())
        let event = try card(plan, 0)
        let edited = try await session.edit(attemptID: event.attemptID,
            edits: [DraftEdit(field: "title", value: .text("Dinner"))], expectedRevision: event.revision)
        _ = try await session.confirm(attemptID: edited.attemptID, edits: [], expectedRevision: edited.revision)
        let filled = try card(XCTUnwrap(session.refreshPlan(requestID: request)), 1)
        XCTAssertTrue(filled.fields.first { $0.name == "body" }?.value.hasPrefix("Dinner · ") == true)
        do {
            _ = try await session.edit(attemptID: filled.attemptID,
                edits: [DraftEdit(field: "body", value: .text("Invented result"))], expectedRevision: filled.revision)
            XCTFail("A receipt-bound body must not become editable prose")
        } catch { XCTAssertTrue(error is EffectError) }
        _ = try await session.confirm(attemptID: filled.attemptID,
            edits: [DraftEdit(field: "body", value: .text("Invented result"))], expectedRevision: filled.revision)
        XCTAssertEqual(effects.performCount, 1)
    }

    func testConcurrentConfirmAndRepeatedStageDoNotDuplicate() async throws {
        let (_, session, effects) = try fixture()
        let request = UserRequestID(), steps = inputs(dependent: false)
        async let a = session.stagePlan(requestID: request, steps: steps)
        async let b = session.stagePlan(requestID: request, steps: steps)
        let (first, second) = try await (a, b)
        XCTAssertEqual(first.steps.map(\.attemptID), second.steps.map(\.attemptID))
        let message = try card(first, 1)
        effects.delayNanoseconds = 50_000_000
        async let one = session.confirm(attemptID: message.attemptID, edits: [], expectedRevision: message.revision)
        async let two = session.confirm(attemptID: message.attemptID, edits: [], expectedRevision: message.revision)
        _ = try await (one, two)
        XCTAssertEqual(effects.performCount, 1)
        let again = try await session.stagePlan(requestID: request, steps: inputs())
        XCTAssertEqual(again.steps.map(\.attemptID), first.steps.map(\.attemptID))
    }

    func testReceiptFailureKeepsDependentBlockedWithoutReplay() async throws {
        let (db, session, effects) = try fixture()
        let request = UserRequestID()
        let plan = try await session.stagePlan(requestID: request, steps: inputs())
        let event = try card(plan, 0)
        try db.exec("CREATE TRIGGER fail_receipt BEFORE UPDATE ON action_attempts WHEN NEW.phase='settled' BEGIN SELECT RAISE(ABORT, 'injected receipt failure'); END;")
        do {
            _ = try await session.confirm(attemptID: event.attemptID, edits: [], expectedRevision: event.revision)
            XCTFail("Expected receipt storage failure")
        } catch { XCTAssertTrue(error is SQLiteError) }
        XCTAssertEqual(effects.performCount, 1)
        XCTAssertEqual(try session.ledger.load(event.attemptID)?.phase, .claimed)
        XCTAssertFalse(try card(XCTUnwrap(session.refreshPlan(requestID: request)), 1).canConfirm)
        _ = try session.ledger.recover(now: now)
        _ = try await session.confirm(attemptID: event.attemptID, edits: [], expectedRevision: event.revision)
        XCTAssertEqual(effects.performCount, 1)
    }

    func testAtomicStageRollsBackWhenSecondInsertFails() async throws {
        let (db, session, effects) = try fixture()
        try db.exec("CREATE TRIGGER fail_second BEFORE INSERT ON action_attempts WHEN NEW.step_index=1 BEGIN SELECT RAISE(ABORT, 'injected second insert failure'); END;")
        do { _ = try await session.stagePlan(requestID: UserRequestID(), steps: inputs()); XCTFail("Expected storage failure") }
        catch { XCTAssertTrue(error is SQLiteError) }
        XCTAssertTrue(try db.query("SELECT attempt_id FROM action_attempts").isEmpty)
        XCTAssertEqual(effects.performCount, 0)
    }

    func testCapacityAndInvalidDependencyRefuseWithoutEviction() async throws {
        let (_, session, effects) = try fixture()
        let request = UserRequestID()
        let original = try await session.stagePlan(requestID: request, steps: inputs())
        for _ in 0..<3 { _ = try await session.stagePlan(requestID: UserRequestID(), steps: inputs()) }
        do { _ = try await session.stagePlan(requestID: UserRequestID(), steps: inputs()); XCTFail("Expected capacity refusal") }
        catch { XCTAssertEqual(error as? ActionPlanError, .capacity) }
        XCTAssertEqual(try session.plan(requestID: request)?.steps.map(\.attemptID), original.steps.map(\.attemptID))
        let invalid = [PlanStepInput(capabilityID: "imessage_send", arguments: ["contact": "Dana"],
            messageFrom: PlanDependency(stepIndex: 0, field: .time)), inputs()[0]]
        do { _ = try await session.stagePlan(requestID: UserRequestID(), steps: invalid); XCTFail("Expected cycle refusal") }
        catch { XCTAssertEqual(error as? ActionPlanError, .invalidDependency) }
        XCTAssertEqual(effects.performCount, 0)
    }

    func testRestartAndCancelPreserveClaimedStep() async throws {
        let path = tempDBPath("plan-reopen")
        let request = UserRequestID()
        var attemptIDs: [AttemptID] = []
        do {
            let (_, session, effects) = try fixture(path: path)
            let plan = try await session.stagePlan(requestID: request, steps: inputs())
            attemptIDs = plan.steps.map(\.attemptID)
            let event = try card(plan, 0)
            _ = try session.ledger.claim(attemptID: event.attemptID, expectedRevision: event.revision, action: nil)
            XCTAssertEqual(effects.performCount, 0)
        }
        let (_, session, effects) = try fixture(path: path)
        let recovery = try session.ledger.recover(now: now)
        XCTAssertEqual(recovery.unresolved.first?.attemptID, attemptIDs[0])
        XCTAssertFalse(try card(XCTUnwrap(session.plan(requestID: request)), 1).canConfirm)
        _ = try session.cancelPlan(requestID: request)
        XCTAssertEqual(try session.ledger.load(attemptIDs[0])?.phase, .claimed)
        XCTAssertEqual(try session.ledger.load(attemptIDs[1])?.phase, .settled(.cancelled(.userCard)))
        XCTAssertEqual(effects.performCount, 0)
    }

    func testCorruptMetadataCannotBecomeAnIndependentClaim() async throws {
        let (db, session, effects) = try fixture()
        let plan = try await session.stagePlan(requestID: UserRequestID(), steps: inputs(dependent: false))
        let message = try card(plan, 1)
        try db.run("UPDATE action_attempts SET plan_json='{}' WHERE attempt_id=?", [.text(message.attemptID.raw.uuidString)])
        XCTAssertThrowsError(try session.ledger.claim(attemptID: message.attemptID, expectedRevision: message.revision, action: nil))
        XCTAssertTrue(try session.ledger.recover(now: now).unresolved.contains { $0.attemptID == message.attemptID })
        XCTAssertEqual(effects.performCount, 0)
    }

    func testLegacyDuplicateRequestRowsSurviveMigration() async throws {
        let (db, session, _) = try fixture()
        let request = UserRequestID()
        for _ in 0..<2 {
            _ = try await session.evaluate(requestID: request, capability: .compiled(reminderContract()),
                raw: PlannedAction(tool: "create_reminder", args: ["title": "Pack", "when": "tomorrow at noon"]),
                modelAskedConfirm: true, explicitDraft: false)
        }
        try db.exec("DROP INDEX action_plan_step; ALTER TABLE action_attempts DROP COLUMN plan_json; ALTER TABLE action_attempts DROP COLUMN plan_size;")
        let reopened = try EffectLedger(db: db, now: { self.now })
        XCTAssertEqual(try reopened.recover(now: now).showAgain.count, 2)
        let next = EffectSession(ledger: reopened, effects: session.effects)
        _ = try await next.stagePlan(requestID: UserRequestID(), steps: inputs())
        do { _ = try await next.stagePlan(requestID: request, steps: inputs()); XCTFail("Existing single request must not gain plan steps") }
        catch { XCTAssertEqual(error as? ActionPlanError, .requestAlreadyUsed) }
    }

    func testCancelledPredecessorDoesNotBlockIndependentThirdStep() async throws {
        let (_, session, effects) = try fixture()
        let request = UserRequestID()
        let third = PlanStepInput(capabilityID: "reminder_create", arguments: ["title": "Pack", "when": "tomorrow at noon"])
        let plan = try await session.stagePlan(requestID: request, steps: inputs() + [third])
        _ = try session.cancel(attemptID: plan.steps[0].attemptID)
        let refreshed = try XCTUnwrap(session.refreshPlan(requestID: request))
        XCTAssertFalse(try card(refreshed, 1).canConfirm)
        let reminder = try card(refreshed, 2)
        XCTAssertTrue(reminder.canConfirm)
        _ = try await session.confirm(attemptID: reminder.attemptID, edits: [], expectedRevision: reminder.revision)
        XCTAssertEqual(effects.performCount, 1)
        XCTAssertEqual(effects.performed.first?.action.capabilityID, "reminder_create")
    }

    func testBoundsAndConflictingBodyRejectTheWholePlan() async throws {
        let (db, session, effects) = try fixture()
        let oversized = PlanStepInput(capabilityID: "calendar_create", arguments: ["title": String(repeating: "x", count: 17_000)])
        let conflicting = PlanStepInput(capabilityID: "imessage_send", arguments: ["contact": "Dana", "body": "do not replace this"],
            messageFrom: PlanDependency(stepIndex: 0, field: .time))
        let cases: [([PlanStepInput], ActionPlanError)] = [(inputs() + inputs(), .stepCount),
            ([oversized, inputs()[1]], .tooLarge), ([inputs()[0], conflicting], .invalidDependency)]
        for (steps, expected) in cases {
            do { _ = try await session.stagePlan(requestID: UserRequestID(), steps: steps); XCTFail("Expected \(expected)") }
            catch { XCTAssertEqual(error as? ActionPlanError, expected) }
        }
        XCTAssertTrue(try db.query("SELECT attempt_id FROM action_attempts").isEmpty)
        XCTAssertEqual(effects.performCount, 0)
    }
}
