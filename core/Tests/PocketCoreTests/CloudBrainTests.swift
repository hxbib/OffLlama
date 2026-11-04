import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import PocketCore

final class CloudBrainTests: XCTestCase {
    private actor CallCounter {
        private(set) var calls = 0
        func increment() { calls += 1 }
    }

    func testCancellationNeverTriesAnotherProvider() async throws {
        for error in [CancellationError() as Error, URLError(.cancelled) as Error] {
            let counter = CallCounter()
            var first = CloudPresets.metaModelAPI(model: "test", apiKey: "k")
            first.transport = { _ in throw error }
            var next = CloudPresets.metaModelAPI(model: "test", apiKey: "k")
            next.transport = { _ in await counter.increment(); return (Data(), 200) }
            do {
                _ = try await CloudBrainChain([first, next]).complete([])
                XCTFail("cancelled request returned")
            } catch { XCTAssertTrue(CloudBrainChain.isCancellation(error)) }
            let calls = await counter.calls
            XCTAssertEqual(calls, 0)
        }
    }

    func testMalformedSettingsCannotReachTransport() async throws {
        let cases = [("", "https://example.com/v1", "k"), ("model", "relative", "k"),
                     ("model", "file:///tmp/api", "k"), ("model", "https://example.com/v1", "  ")]
        for (model, url, key) in cases {
            var brain = OpenAICompatibleBrain(providerName: "test", model: model, baseURL: URL(string: url)!, apiKey: key)
            brain.transport = { _ in XCTFail("invalid settings made a network call"); return (Data(), 200) }
            do { _ = try await brain.complete([]); XCTFail("expected invalid configuration") }
            catch { XCTAssertEqual(error as? CloudError, .notConfigured) }
        }
    }

    func testContributorModeIsRefusedBeforeTransport() async throws {
        let counter = CallCounter()
        var brain = CloudPresets.metaModelAPI(model: "muse-spark-1.3-contributor", apiKey: "k")
        brain.transport = { _ in
            await counter.increment()
            return (Data(), 200)
        }

        do {
            _ = try await brain.complete([ChatMessage(role: "user", content: "hello")])
            XCTFail("a contributor-mode id must not reach the network")
        } catch {
            XCTAssertEqual(error as? MultimodalError, .contributorModeRefused("muse-spark-1.3-contributor"))
        }
        let calls = await counter.calls
        XCTAssertEqual(calls, 0, "refused while building the request, before transport")
        XCTAssertThrowsError(try brain.makeRequest([ChatMessage(role: "user", content: "hello")], maxTokens: 5))
    }
}
