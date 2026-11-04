import XCTest
@testable import PocketCore

final class CloudConfigurationTests: XCTestCase {
    func testSettingsChangeAppliesToNextRequestWithoutChangingPendingReplyRestoration() async throws {
        let engine = ScriptedEngine()
        engine.script(whenPromptContains: "acceptable to send this request", logits: ["A": 5, "B": -5])
        let db = try SQLiteDB(path: ":memory:")
        let firstBrain = PausedBrain()
        let assistant = Assistant(reflex: Reflex(engine: engine), memory: try MemoryStore(db: db),
                                  actions: RecordingActions(), cloud: CloudBrainChain([firstBrain]), isOnline: { true })
        assistant.scrubber = PrivacyScrubber(knownNames: ["Dana"])

        let pending = Task {
            try await assistant.reason("Summarize.", text: "Dana: " + String(repeating: "project update ", count: 250))
        }
        await firstBrain.waitForRequest()
        let sent = await firstBrain.request
        XCTAssertFalse(sent.contains("Dana"))
        XCTAssertTrue(sent.contains("[PERSON_1]"))

        assistant.cloud = CloudBrainChain([ImmediateBrain()])
        assistant.scrubber = PrivacyScrubber(knownNames: ["Morgan"])
        await firstBrain.release()
        let originalReply = try await pending.value
        XCTAssertEqual(originalReply, "Dana from the original brain")

        let nextReply = try await assistant.reason("Summarize.", text: "Morgan: " + String(repeating: "project update ", count: 250))
        XCTAssertEqual(nextReply, "Morgan from the new brain")
    }
}

private actor PausedBrain: CloudBrain {
    nonisolated let providerName = "test"
    nonisolated let model = "original"
    private(set) var request = ""
    private var waitingForRequest: CheckedContinuation<Void, Never>?
    private var pendingReply: CheckedContinuation<Void, Never>?

    func complete(_ messages: [ChatMessage], maxTokens: Int) async throws -> CloudAnswer {
        request = messages.map(\.content).joined(separator: "\n")
        await withCheckedContinuation { continuation in
            pendingReply = continuation
            waitingForRequest?.resume()
            waitingForRequest = nil
        }
        return CloudAnswer(text: "[PERSON_1] from the original brain", provider: providerName, model: model, latencyMs: 0)
    }

    func waitForRequest() async {
        if pendingReply != nil { return }
        await withCheckedContinuation { waitingForRequest = $0 }
    }

    func release() {
        pendingReply?.resume()
        pendingReply = nil
    }
}

private struct ImmediateBrain: CloudBrain {
    let providerName = "test"
    let model = "new"
    func complete(_ messages: [ChatMessage], maxTokens: Int) async throws -> CloudAnswer {
        CloudAnswer(text: "[PERSON_1] from the new brain", provider: providerName, model: model, latencyMs: 0)
    }
}
