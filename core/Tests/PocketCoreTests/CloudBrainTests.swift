import Foundation
import XCTest
@testable import PocketCore

final class CloudBrainTests: XCTestCase {
    func testContributorModeIsRefusedBeforeTransport() async throws {
        final class Counter: @unchecked Sendable { var calls = 0 }
        let counter = Counter()
        var brain = CloudPresets.metaModelAPI(model: "muse-spark-1.3-contributor", apiKey: "k")
        brain.transport = { _ in
            counter.calls += 1
            return (Data(), 200)
        }

        do {
            _ = try await brain.complete([ChatMessage(role: "user", content: "hello")])
            XCTFail("a contributor-mode id must not reach the network")
        } catch {
            XCTAssertEqual(error as? MultimodalError, .contributorModeRefused("muse-spark-1.3-contributor"))
        }
        XCTAssertEqual(counter.calls, 0, "refused while building the request, before transport")
        XCTAssertThrowsError(try brain.makeRequest([ChatMessage(role: "user", content: "hello")], maxTokens: 5))
    }
}
