import XCTest
@testable import PocketCore

final class TakeoverRegressionTests: XCTestCase {
    func testDemoMessagePreservesBodyWithoutSeparator() {
        let args = ArgumentExtractor.heuristic(tool: "send_message", utterance: "Text Mom I'll be home by 8")
        XCTAssertEqual(args["contact"], "Mom")
        XCTAssertEqual(args["body"], "I'll be home by 8")
    }

    func testAppleTVRequestReachesSkillRouting() {
        XCTAssertTrue(ActionPlanner.isExplicitRequest("open the latest episode of Severance on Apple TV"))
    }
}
