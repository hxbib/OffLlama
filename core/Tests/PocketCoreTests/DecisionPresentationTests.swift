import XCTest
@testable import PocketCore

final class DecisionPresentationTests: XCTestCase {
    func testPrimaryLabelsHaveNoRawIdentifiers() {
        for set in OptionSets.staticSets {
            XCTAssertFalse(DecisionPresentation.title(set.type).contains("_"))
            for o in set.options {
                let label = DecisionPresentation.choice(set.type, id: o.id)
                XCTAssertFalse(label.contains("_"), "\(set.type) \(o.id) -> \(label)")
                XCTAssertNotEqual(label, o.id, "\(set.type) \(o.id) is unlabeled")
            }
        }
    }

    func testCertaintyDoesNotClaimSuccessAndStatesTheBar() {
        XCTAssertEqual(DecisionPresentation.certainty(confidence: 0.97, tau: 0.9), "Model certainty 97% (needs 90%)")
        XCTAssertEqual(DecisionPresentation.certainty(confidence: 0.62, tau: 0.9), "Model certainty 62%, below the 90% needed")
        for text in [0.97, 0.62].map({ DecisionPresentation.certainty(confidence: $0, tau: 0.9) }) {
            XCTAssertFalse(text.lowercased().contains("success"))
            XCTAssertFalse(text.lowercased().contains("deliver"))
        }
    }

    func testChosenVersusTopOnlyWhenTheyDiffer() {
        XCTAssertNil(DecisionPresentation.chosenVersusTop(chosen: "a", top: "a", escalated: false))
        XCTAssertNotNil(DecisionPresentation.chosenVersusTop(chosen: "escalate_cloud", top: "tool", escalated: true))
    }

    func testDynamicCandidatesAndSkillTitles() {
        XCTAssertEqual(DecisionPresentation.choice(.contactPick, id: "c1"), "Option 2")
        XCTAssertEqual(DecisionPresentation.choice(.contactPick, id: "ask"), "Unclear, ask you")
        XCTAssertEqual(DecisionPresentation.choice(.skillPick, id: "imessage_send", skillTitle: { $0 == "imessage_send" ? "iMessage" : nil }), "iMessage")
        XCTAssertEqual(DecisionPresentation.choice(.skillPick, id: "some_skill"), "Some Skill")
    }

    func testStatusLabelsNeverImplyDeliveryWithoutProof() {
        XCTAssertFalse(ActionStatusLabel.label(for: .settled(.sheet(.messagesQueuedOrSent))).lowercased().contains("delivered"))
        XCTAssertTrue(ActionStatusLabel.label(for: .settled(.sheet(.messagesQueuedOrSent))).contains("not confirmed"))
        XCTAssertEqual(ActionStatusLabel.label(for: .ambiguous(.saveUnverified)), ActionStatusLabel.unverified)
        XCTAssertEqual(ActionStatusLabel.label(for: .awaitingUser(nil)), ActionStatusLabel.awaitingReview)
    }
}

final class MetaModelPresetTests: XCTestCase {
    func testPresetsAreStandardModeAndAcceptedByTheValidator() {
        XCTAssertEqual(MetaModelPresets.all.map(\.id), ["muse-spark-1.3", "muse-spark-1.2", "muse-spark-1.1", "muse-wonder-1.0"])
        for p in MetaModelPresets.all {
            XCTAssertNoThrow(try MetaAPI.requireStandardMode(p.id))
            XCTAssertTrue(CloudSettingsCheck.meta(model: p.id, keySaved: true).isEnabled, p.id)
        }
    }

    func testUnknownAndContributorValuesAreNotPresetsAndStayOnTheValidator() {
        XCTAssertFalse(MetaModelPresets.isPreset("muse-spark-1.3-contributor"))
        XCTAssertFalse(MetaModelPresets.isPreset("muse-future-9"))
        XCTAssertFalse(CloudSettingsCheck.meta(model: "muse-spark-1.3-contributor", keySaved: true).isEnabled)
        XCTAssertTrue(CloudSettingsCheck.meta(model: "muse-future-9", keySaved: true).isEnabled)
    }
}
