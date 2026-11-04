import Foundation
import XCTest
@testable import PocketCore

final class SharedReadRecoveryTests: XCTestCase {
    private actor Capture {
        var bodies: [Data] = []
        func append(_ body: Data) { bodies.append(body) }
        func all() -> [Data] { bodies }
    }

    private func make(_ engine: ScriptedEngine, cloud: [CloudBrain] = [], online: Bool = false) throws -> Assistant {
        let db = try SQLiteDB(path: ":memory:")
        let assistant = Assistant(reflex: Reflex(engine: engine), memory: try MemoryStore(db: db),
                                  actions: RecordingActions(), ledger: try EffectLedger(db: db),
                                  effects: FakePhoneEffects(), cloud: CloudBrainChain(cloud), isOnline: { online })
        assistant.skills = SkillRegistry()
        return assistant
    }

    private func engine(route: String = "A", sensitive: Bool = false) -> ScriptedEngine {
        let engine = ScriptedEngine()
        engine.generated = "Local document summary"
        engine.script(whenPromptContains: "long-term memory", logits: ["A": -5, "B": -5, "C": 5])
        var routeLogits = ["A": -5.0, "B": -5.0, "C": -5.0, "D": -5.0]
        routeLogits[route] = 5
        engine.script(whenPromptContains: "How should", logits: routeLogits)
        engine.script(whenPromptContains: "acceptable to send this request",
                      logits: sensitive ? ["A": -5, "B": 5] : ["A": 5, "B": -5])
        return engine
    }

    private func brain(_ capture: Capture, status: Int = 200) -> OpenAICompatibleBrain {
        var brain = OpenAICompatibleBrain(providerName: "Test", model: "test-model",
                                          baseURL: URL(string: "https://example.invalid/v1/")!, apiKey: "test")
        brain.transport = { request in
            await capture.append(request.httpBody ?? Data())
            return (Data(#"{"choices":[{"message":{"content":"Cloud document summary"}}]}"#.utf8), status)
        }
        return brain
    }

    func testDefaultShareUsesItsDocumentOnEveryNonToolRoute() async throws {
        for route in ["A", "C", "D"] {
            let engine = engine(route: route)
            let assistant = try make(engine)
            let marker = "Document owned by this request"
            let turn = try await assistant.handle("Summarize this", sharedText: marker)
            XCTAssertEqual(turn.reply, .local("Local document summary"))
            XCTAssertTrue(engine.generatePrompts.contains { $0.contains(marker) })
            XCTAssertNil(turn.cloudPromptSent)
        }
    }

    func testLongDefaultShareSendsItsDocumentEvenWhenRouteSaysLocal() async throws {
        let capture = Capture()
        let assistant = try make(engine(), cloud: [brain(capture)], online: true)
        let shared = "Unique document marker. " + String(repeating: "The project deadline is Friday. ", count: 120)
        let turn = try await assistant.handle("Summarize this", sharedText: shared)
        XCTAssertEqual(turn.reply, .cloud("Cloud document summary", provider: "Test · test-model"))
        let bodies = await capture.all()
        let body = try XCTUnwrap(bodies.first)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(object["messages"] as? [[String: String]])
        XCTAssertEqual(messages.last?["content"], turn.cloudPromptSent)
        XCTAssertTrue(try XCTUnwrap(turn.cloudPromptSent).contains("Unique document marker"))
        XCTAssertTrue(turn.decisions.contains { $0.type == .sensitivity })
    }

    func testFailedSharedReadKeepsTheOutboundPayloadWithLocalFallback() async throws {
        let capture = Capture()
        let assistant = try make(engine(), cloud: [brain(capture, status: 503)], online: true)
        let shared = "Unique fallback document. " + String(repeating: "A longer project document. ", count: 120)
        let turn = try await assistant.handle("Summarize this", sharedText: shared)
        guard case .local = turn.reply else { return XCTFail("Expected local fallback, got \(turn.reply)") }
        XCTAssertTrue(try XCTUnwrap(turn.cloudPromptSent).contains("Unique fallback document"))
        XCTAssertFalse(turn.cloudWithheldForSensitivity)
        let bodies = await capture.all()
        XCTAssertFalse(bodies.isEmpty)
    }

    func testSensitiveSharedDocumentIsWithheldFromCloud() async throws {
        let capture = Capture()
        let assistant = try make(engine(sensitive: true), cloud: [brain(capture)], online: true)
        let shared = String(repeating: "A private document paragraph. ", count: 120)
        let turn = try await assistant.handle("Summarize this", sharedText: shared)
        XCTAssertTrue(turn.cloudWithheldForSensitivity)
        XCTAssertNil(turn.cloudPromptSent)
        let bodies = await capture.all()
        XCTAssertTrue(bodies.isEmpty)
    }

    func testCancelledConfirmedReadStaysUncertainAndCannotReplay() async throws {
        let ledger = try EffectLedger(db: SQLiteDB(path: ":memory:"))
        let session = EffectSession(ledger: ledger, effects: FakePhoneEffects())
        let contract = try XCTUnwrap(CapabilityCatalog.current(id: "email_digest"))
        let card = try session.stageRead(requestID: UserRequestID(), contract: contract,
                                        raw: PlannedAction(tool: "skill:email_digest", args: [:]), sharedText: "Original document")
        do {
            _ = try await session.confirmRead(attemptID: card.attemptID, expectedRevision: card.revision) { _ in
                throw CancellationError()
            }
            XCTFail("Cancellation must propagate")
        } catch is CancellationError {
        }
        let row = try XCTUnwrap(ledger.load(card.attemptID))
        XCTAssertEqual(row.phase, .ambiguous(.claimedWithoutReceipt))
        let repeated = try await session.confirmRead(attemptID: card.attemptID) { _ in
            XCTFail("An interrupted read must not replay")
            return ReadResult(text: "Unexpected replay")
        }
        guard case .ignoredTerminal(let result) = repeated else { return XCTFail("\(repeated)") }
        XCTAssertTrue(result.summary.contains("may already have been sent"))
        XCTAssertFalse(result.summary.contains("Nothing was sent"))
    }

    func testFailedConfirmedReadDoesNotClaimNothingWasSent() async throws {
        let ledger = try EffectLedger(db: SQLiteDB(path: ":memory:"))
        let session = EffectSession(ledger: ledger, effects: FakePhoneEffects())
        let contract = try XCTUnwrap(CapabilityCatalog.current(id: "email_digest"))
        let card = try session.stageRead(requestID: UserRequestID(), contract: contract,
                                        raw: PlannedAction(tool: "skill:email_digest", args: [:]), sharedText: "Original document")
        let failed = try await session.confirmRead(attemptID: card.attemptID) { _ in
            throw URLError(.networkConnectionLost)
        }
        guard case .finished(let result) = failed else { return XCTFail("\(failed)") }
        XCTAssertEqual(result.phase, .ambiguous(.claimedWithoutReceipt))
        XCTAssertTrue(result.summary.contains("may already have been sent"))
        XCTAssertFalse(result.summary.contains("Nothing was sent"))
    }
}
