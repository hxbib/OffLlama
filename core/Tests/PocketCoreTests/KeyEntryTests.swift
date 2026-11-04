import XCTest
@testable import PocketCore

private final class FakeStore: SecretStoring {
    var items: [String: String] = [:]
    var replaceCode: Int32 = 0
    var removeCode: Int32 = 0
    var presenceOverride: SecretPresence?
    var calls: [String] = []
    func presence(_ account: String) -> SecretPresence { presenceOverride ?? (items[account] == nil ? .absent : .saved) }
    func replace(_ value: String, account: String) -> Int32 {
        calls.append("replace"); guard replaceCode == 0 else { return replaceCode }
        items[account] = value; return 0
    }
    func remove(_ account: String) -> Int32 {
        calls.append("remove"); guard removeCode == 0 else { return removeCode }
        items[account] = nil; return 0
    }
}

final class KeyEntryTests: XCTestCase {
    private let secret = "synthetic-test-key-123"

    func testSaveReplacesAndReportsReplacement() {
        let store = FakeStore(); store.items["meta_key"] = "old-synthetic"
        let outcome = KeyEntry.commit(entered: "  \(secret)\n", account: "meta_key", store: store)
        XCTAssertEqual(outcome, .saved(replacedPrevious: true))
        XCTAssertEqual(store.items["meta_key"], secret)
        XCTAssertEqual(KeyEntry.message(outcome, label: "Meta"), "Meta key replaced.")
    }

    func testFirstSaveDoesNotClaimAReplacement() {
        let store = FakeStore()
        let outcome = KeyEntry.commit(entered: secret, account: "meta_key", store: store)
        XCTAssertEqual(outcome, .saved(replacedPrevious: false))
        XCTAssertEqual(KeyEntry.message(outcome, label: "Meta"), "Meta key saved.")
    }

    func testFailedReplacementKeepsOldKeyAndNeverRemovesFirst() {
        let store = FakeStore(); store.items["meta_key"] = "old-synthetic"; store.replaceCode = -25308
        let outcome = KeyEntry.commit(entered: secret, account: "meta_key", store: store)
        XCTAssertEqual(outcome, .failed(code: -25308, previous: .saved))
        XCTAssertEqual(store.items["meta_key"], "old-synthetic")
        XCTAssertEqual(store.calls, ["replace"])
        XCTAssertTrue(KeyEntry.message(outcome, label: "Meta")!.contains("previous key is unchanged"))
    }

    func testFailureWithNoPriorKeyDoesNotClaimOneWasRetained() {
        let store = FakeStore(); store.replaceCode = -25293
        let message = KeyEntry.message(KeyEntry.commit(entered: secret, account: "byok_key", store: store), label: "endpoint")!
        XCTAssertTrue(message.contains("No key is saved."))
        XCTAssertFalse(message.lowercased().contains("retained"))
        XCTAssertFalse(message.contains("previous key"))
    }

    func testFailureWithUnreadableKeychainAdmitsUncertainty() {
        let store = FakeStore(); store.presenceOverride = .unavailable(-25308); store.replaceCode = -25308
        let message = KeyEntry.message(KeyEntry.commit(entered: secret, account: "meta_key", store: store), label: "Meta")!
        XCTAssertTrue(message.contains("could not confirm"))
    }

    func testBlankAndMalformedEntriesChangeNothing() {
        let store = FakeStore(); store.items["meta_key"] = "old-synthetic"
        XCTAssertEqual(KeyEntry.commit(entered: "  \n ", account: "meta_key", store: store), .nothingEntered)
        XCTAssertEqual(KeyEntry.commit(entered: "two words", account: "meta_key", store: store), .malformed)
        XCTAssertEqual(store.calls, [])
        XCTAssertEqual(store.items["meta_key"], "old-synthetic")
    }

    func testMessagesNeverContainTheEnteredKey() {
        for code: Int32 in [0, -25308, -25293, -34018] {
            for existing in [true, false] {
                let store = FakeStore(); store.replaceCode = code
                if existing { store.items["k"] = "old-synthetic" }
                let outcome = KeyEntry.commit(entered: secret, account: "k", store: store)
                XCTAssertFalse((KeyEntry.message(outcome, label: "Meta") ?? "").contains(secret))
                XCTAssertFalse(String(describing: outcome).contains(secret) && code != 0)
            }
        }
    }

    func testRemovalMessagesAreTruthful() {
        let store = FakeStore(); store.items["meta_key"] = "x"
        XCTAssertEqual(KeyEntry.message(KeyEntry.remove(account: "meta_key", store: store), label: "Meta"), "Meta key removed.")
        XCTAssertEqual(KeyEntry.message(KeyEntry.remove(account: "meta_key", store: store), label: "Meta"), "No Meta key was saved.")
        store.items["meta_key"] = "x"; store.removeCode = -25308
        XCTAssertTrue(KeyEntry.message(KeyEntry.remove(account: "meta_key", store: store), label: "Meta").contains("may still be saved"))
        XCTAssertEqual(store.items["meta_key"], "x")
    }
}

final class CloudSettingsCheckTests: XCTestCase {
    func testMetaStatuses() {
        XCTAssertEqual(CloudSettingsCheck.meta(model: "muse-spark-1.3", keySaved: true).state, .enabled)
        XCTAssertEqual(CloudSettingsCheck.meta(model: "muse-spark-1.3", keySaved: false).state, .needsKey)
        XCTAssertEqual(CloudSettingsCheck.meta(model: "  ", keySaved: true).state, .refused)
        let contributor = CloudSettingsCheck.meta(model: "Muse-Spark-1.3-Contributor", keySaved: true)
        XCTAssertEqual(contributor.state, .refused)
        XCTAssertFalse(contributor.isEnabled)
    }

    func testCustomStatusesFollowTheRequestPathValidator() {
        XCTAssertEqual(CloudSettingsCheck.custom(baseURL: "", model: "", keySaved: false).state, .notConfigured)
        XCTAssertEqual(CloudSettingsCheck.custom(baseURL: "https://api.example.com/v1/", model: "m", keySaved: true).state, .enabled)
        XCTAssertEqual(CloudSettingsCheck.custom(baseURL: "https://api.example.com/v1/", model: "m", keySaved: false).state, .needsKey)
        for bad in ["api.example.com/v1", "ftp://x.example/v1", "https://u:p@x.example/v1", "https://x.example/v1?k=1", "https://x.example/v1#f", "https://"] {
            XCTAssertEqual(CloudSettingsCheck.custom(baseURL: bad, model: "m", keySaved: true).state, .refused, bad)
        }
        XCTAssertEqual(CloudSettingsCheck.custom(baseURL: "https://x.example/v1/", model: "", keySaved: true).state, .refused)
        XCTAssertEqual(CloudSettingsCheck.custom(baseURL: "https://x.example/v1/", model: "m-contributor", keySaved: true).state, .refused)
    }

    func testPlainHTTPIsEnabledButWarned() {
        let status = CloudSettingsCheck.custom(baseURL: "http://192.168.1.5:8000/v1/", model: "m", keySaved: true)
        XCTAssertTrue(status.isEnabled)
        XCTAssertTrue(status.detail.contains("not encrypted"))
    }

    func testAgreesWithValidatorForEverySampleURL() {
        for url in ["https://api.example.com/v1/", "http://localhost:8000/v1", "https://x.example/v1?a=1", "gopher://x", "https://u@x.example/"] {
            let validator = URL(string: url).map { OpenAICompatibleBrain.validConfiguration(model: "m", baseURL: $0, apiKey: "k") } ?? false
            XCTAssertEqual(CloudSettingsCheck.custom(baseURL: url, model: "m", keySaved: true).isEnabled, validator, url)
        }
    }
}
