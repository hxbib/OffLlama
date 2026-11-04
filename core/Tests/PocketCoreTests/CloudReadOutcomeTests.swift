import Foundation
import XCTest
@testable import PocketCore

final class CloudReadOutcomeTests: XCTestCase {
    private actor Capture {
        var bodies: [Data] = []
        func append(_ body: Data) { bodies.append(body) }
        func all() -> [Data] { bodies }
    }

    private func engine() -> ScriptedEngine {
        let engine = ScriptedEngine()
        engine.generated = "Local summary"
        engine.script(whenPromptContains: "long-term memory", logits: ["A": -5, "B": -5, "C": 5])
        engine.script(whenPromptContains: "How should", logits: ["A": 5, "B": -5, "C": -5, "D": -5])
        engine.script(whenPromptContains: "acceptable to send this request", logits: ["A": 5, "B": -5])
        return engine
    }

    private func make(_ engine: LLMEngine, brains: [CloudBrain]) throws -> Assistant {
        let db = try SQLiteDB(path: ":memory:")
        let assistant = Assistant(reflex: Reflex(engine: engine), memory: try MemoryStore(db: db),
                                  actions: RecordingActions(), ledger: try EffectLedger(db: db),
                                  effects: FakePhoneEffects(), cloud: CloudBrainChain(brains), isOnline: { true })
        assistant.skills = SkillRegistry()
        return assistant
    }

    private func brain(_ capture: Capture, error: Error) -> OpenAICompatibleBrain {
        var brain = OpenAICompatibleBrain(providerName: "Test", model: "test-model",
                                          baseURL: URL(string: "https://example.invalid/v1/")!, apiKey: "synthetic-key")
        brain.transport = { request in
            await capture.append(request.httpBody ?? Data())
            throw error
        }
        return brain
    }

    private func sentText(_ capture: Capture) async throws -> String {
        let bodies = await capture.all()
        XCTAssertEqual(bodies.count, 1)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(bodies.first)) as? [String: Any])
        let messages = try XCTUnwrap(object["messages"] as? [[String: String]])
        return try XCTUnwrap(messages.last?["content"])
    }

    private func stage(_ session: EffectSession) throws -> DraftCard {
        try session.stageRead(requestID: UserRequestID(),
                              contract: XCTUnwrap(CapabilityCatalog.current(id: "email_digest")),
                              raw: PlannedAction(tool: "skill:email_digest", args: [:]), sharedText: "Original document")
    }

    func testCancelledImmediateShareRetainsExactAttemptedTextWithoutFallback() async throws {
        let capture = Capture()
        let engine = engine()
        let assistant = try make(engine, brains: [brain(capture, error: URLError(.cancelled))])
        let document = String(repeating: "Synthetic public project notes. ", count: 120)
        do {
            _ = try await assistant.handle("Summarize this", sharedText: document)
            XCTFail("An interrupted provider must not produce an answer")
        } catch let failure as CloudRequestFailure {
            XCTAssertTrue(failure.wasCancelled)
            XCTAssertTrue(CloudBrainChain.isCancellation(failure))
            let sent = try await sentText(capture)
            XCTAssertEqual(failure.cloudPromptSent, sent)
            XCTAssertFalse(failure.localizedDescription.contains(document))
        }
        XCTAssertTrue(engine.generatePrompts.isEmpty)
    }

    func testFailedLocalFallbackRetainsCloudAttemptAndDoesNotDisplayProviderError() async throws {
        let capture = Capture()
        let assistant = try make(GenerationFailureEngine(base: engine()),
                                 brains: [brain(capture, error: CloudError.http(503, "synthetic-private-server-body"))])
        do {
            _ = try await assistant.reason("Summarize", text: String(repeating: "Public project notes. ", count: 150))
            XCTFail("Both backends failed")
        } catch let failure as CloudRequestFailure {
            let sent = try await sentText(capture)
            XCTAssertEqual(failure.cloudPromptSent, sent)
            XCTAssertFalse(failure.wasCancelled)
            XCTAssertFalse(failure.localizedDescription.contains("synthetic-private-server-body"))
            XCTAssertFalse(String(describing: failure).contains("synthetic-private-server-body"))
        }
    }

    func testCancelledConfirmedReadRetainsPayloadAndRecoversWithoutReplay() async throws {
        let capture = Capture()
        let assistant = try make(engine(), brains: [brain(capture, error: URLError(.cancelled))])
        let ledger = try EffectLedger(db: SQLiteDB(path: ":memory:"))
        let session = EffectSession(ledger: ledger, effects: FakePhoneEffects())
        let card = try stage(session)
        do {
            _ = try await session.confirmRead(attemptID: card.attemptID) { _ in
                try await assistant.reason("Summarize", text: String(repeating: "Public notes. ", count: 250))
            }
            XCTFail("Cancellation must propagate")
        } catch let failure as CloudRequestFailure {
            XCTAssertTrue(failure.wasCancelled)
            let sent = try await sentText(capture)
            XCTAssertEqual(failure.cloudPromptSent, sent)
        }
        let recovery = try ledger.recover(now: Date())
        XCTAssertTrue(recovery.showAgain.isEmpty)
        XCTAssertEqual(recovery.unresolved.map(\.attemptID), [card.attemptID])
        XCTAssertTrue(try XCTUnwrap(recovery.unresolved.first).summary.contains("may already have been sent"))
        let repeated = try await session.confirmRead(attemptID: card.attemptID) { _ in
            XCTFail("Recovery must not permit replay")
            return ReadResult(text: "Unexpected")
        }
        guard case .ignoredTerminal = repeated else { return XCTFail("Expected terminal ambiguity") }
        let bodies = await capture.all()
        XCTAssertEqual(bodies.count, 1)
    }

    func testDirectCloudAnswerRetainsPayloadWhenLocalAnswerAlsoFails() async throws {
        let capture = Capture()
        let engine = engine()
        engine.script(whenPromptContains: "How should", logits: ["A": -5, "B": -5, "C": 5, "D": -5])
        engine.script(whenPromptContains: "Can a small on-device model", logits: ["A": 5, "B": -5])
        let assistant = try make(GenerationFailureEngine(base: engine),
                                 brains: [brain(capture, error: URLError(.networkConnectionLost))])
        do {
            _ = try await assistant.handle("What does the public project announcement mean?")
            XCTFail("Both backends failed")
        } catch let failure as CloudRequestFailure {
            let sent = try await sentText(capture)
            XCTAssertEqual(failure.cloudPromptSent, sent)
            XCTAssertFalse(failure.wasCancelled)
        }
    }

    func testReceiptWriteFailureRetainsKnownPayloadWithoutClaimingSuccess() async throws {
        let db = try SQLiteDB(path: ":memory:")
        let ledger = try EffectLedger(db: db)
        let session = EffectSession(ledger: ledger, effects: FakePhoneEffects())
        let card = try stage(session)
        try db.run("""
        CREATE TRIGGER fail_receipt BEFORE UPDATE ON action_attempts WHEN NEW.phase='settled'
        BEGIN SELECT RAISE(ABORT, 'simulated receipt storage failure'); END;
        """)
        let result = try await session.confirmRead(attemptID: card.attemptID) { _ in
            ReadResult(text: "Cloud answer", provider: "Test", cloudPromptSent: "Exact screened text")
        }
        guard case .finished(let effect) = result else { return XCTFail("Expected unverified result") }
        XCTAssertEqual(effect.phase, .ambiguous(.claimedWithoutReceipt))
        XCTAssertEqual(effect.cloudPromptSent, "Exact screened text")
        XCTAssertTrue(effect.summary.contains("may already have been sent"))
        XCTAssertEqual(try ledger.recover(now: Date()).unresolved.map(\.attemptID), [card.attemptID])
    }

    func testBothReceiptAndAmbiguityWriteFailureKeepPayloadAndClaimedRecovery() async throws {
        let db = try SQLiteDB(path: ":memory:")
        let ledger = try EffectLedger(db: db)
        let session = EffectSession(ledger: ledger, effects: FakePhoneEffects())
        let card = try stage(session)
        try db.run("""
        CREATE TRIGGER fail_receipt BEFORE UPDATE ON action_attempts WHEN NEW.phase IN ('settled','ambiguous')
        BEGIN SELECT RAISE(ABORT, 'simulated storage failure'); END;
        """)
        do {
            _ = try await session.confirmRead(attemptID: card.attemptID) { _ in
                ReadResult(text: "Cloud answer", provider: "Test", cloudPromptSent: "Exact attempted text")
            }
            XCTFail("Receipt writes failed")
        } catch let failure as CloudRequestFailure {
            XCTAssertEqual(failure.cloudPromptSent, "Exact attempted text")
        }
        XCTAssertEqual(try ledger.load(card.attemptID)?.phase, .claimed)
        let recovery = try ledger.recover(now: Date())
        XCTAssertTrue(recovery.showAgain.isEmpty)
        XCTAssertTrue(try XCTUnwrap(recovery.unresolved.first).summary.contains("may already have been sent"))
    }

    func testRepeatedSettledReadKeepsItsReceiptPayloadWithoutRunningAgain() async throws {
        let session = EffectSession(ledger: try EffectLedger(db: SQLiteDB(path: ":memory:")), effects: FakePhoneEffects())
        let card = try stage(session)
        _ = try await session.confirmRead(attemptID: card.attemptID) { _ in
            ReadResult(text: "Answer", provider: "Test", cloudPromptSent: "Exact screened request")
        }
        let repeated = try await session.confirmRead(attemptID: card.attemptID) { _ in
            XCTFail("A settled read must not replay")
            return ReadResult(text: "Unexpected")
        }
        guard case .ignoredTerminal(let effect) = repeated else { return XCTFail("Expected settled result") }
        XCTAssertEqual(effect.cloudPromptSent, "Exact screened request")
    }
}

private struct GenerationFailureEngine: LLMEngine {
    let base: ScriptedEngine
    var modelName: String { "generation-failure" }
    func nextTokenLogits(prompt: String, candidates: [String]) async throws -> [String: Double] {
        try await base.nextTokenLogits(prompt: prompt, candidates: candidates)
    }
    func generate(prompt: String, maxTokens: Int, temperature: Double) async throws -> String {
        throw LLMError.badResponse("Synthetic local generation failure")
    }
}
