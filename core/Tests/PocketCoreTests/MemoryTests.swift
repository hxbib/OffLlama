import XCTest
@testable import PocketCore

final class MemoryTests: XCTestCase {
    var now = Date(timeIntervalSince1970: 1_793_000_000)
    func store() throws -> MemoryStore { try MemoryStore(db: SQLiteDB(path: ":memory:"), clock: { [unowned self] in self.now }) }

    func testRuleExtraction() {
        let f = RuleFactExtractor.extract("I moved to Brooklyn. I'm allergic to peanuts and I love bouldering. Maya's birthday is November 3rd")
        let keys = Set(f.map { "\($0.subject)|\($0.attribute)|\($0.value)" })
        XCTAssertTrue(keys.contains("user|lives_in|Brooklyn"))
        XCTAssertTrue(keys.contains("user|allergy|peanuts"))
        XCTAssertTrue(keys.contains("user|likes|bouldering"))
        XCTAssertTrue(keys.contains("maya|birthday|November 3rd"))
        XCTAssertTrue(RuleFactExtractor.extract("what's the weather").isEmpty)
        XCTAssertEqual(RuleFactExtractor.extract("I'm out of oat milk.").first?.ttl, 7 * 86_400)
    }

    func testContradictionSupersedesSingleValued() async throws {
        let m = try store()
        try await m.upsert(.init(subject: "user", attribute: "lives_in", value: "Boston", text: "User lives in Boston"))
        now += 100
        let r = try await m.upsert(.init(subject: "user", attribute: "lives_in", value: "Brooklyn", text: "User lives in Brooklyn"))
        XCTAssertEqual(r.resolution, .update)
        XCTAssertEqual(try m.profile()["lives_in"], ["Brooklyn"])
        let h = try m.history(subject: "user", attribute: "lives_in")
        XCTAssertEqual(h.count, 2); XCTAssertEqual(h[0].supersededBy, h[1].id)
    }

    func testMultiValuedKeepsBothAndDuplicateRefreshes() async throws {
        let m = try store()
        try await m.upsert(.init(subject: "user", attribute: "likes", value: "jazz", text: "User likes jazz"))
        let r = try await m.upsert(.init(subject: "user", attribute: "likes", value: "sushi", text: "User likes sushi"))
        XCTAssertEqual(r.resolution, .keepBoth)
        let dup = try await m.upsert(.init(subject: "user", attribute: "likes", value: "Jazz", text: "User likes jazz"))
        XCTAssertEqual(dup.resolution, .ignoreNew)
        XCTAssertEqual(Set(try m.profile()["likes"]!), ["jazz", "sushi"])
    }

    func testResolverCanIgnoreNew() async throws {
        let m = try store()
        try await m.upsert(.init(subject: "user", attribute: "job", value: "designer", text: "User is a designer"))
        let r = try await m.upsert(.init(subject: "user", attribute: "job", value: "dj", text: "User is a dj (joking)")) { _, _ in .ignoreNew }
        XCTAssertNil(r.fact); XCTAssertEqual(try m.profile()["job"], ["designer"])
    }

    func testExpiry() async throws {
        let m = try store()
        try await m.upsert(.init(subject: "user", attribute: "needs_to_buy", value: "milk", text: "User needs milk", ttl: 3600))
        XCTAssertEqual(try m.active().count, 1)
        now += 7200
        XCTAssertEqual(try m.active().count, 0)
        XCTAssertEqual(try m.purgeExpired(), 1)
    }

    func testRetrievalRanksRelevantFirst() async throws {
        let m = try store()
        for (a, v, t) in [("allergy", "peanuts", "User is allergic to peanuts"), ("lives_in", "Brooklyn", "User lives in Brooklyn"),
                          ("likes", "bouldering", "User likes bouldering at the climbing gym")] {
            try await m.upsert(.init(subject: "user", attribute: a, value: v, text: t))
        }
        let hits = try await m.retrieve("can I eat this peanut butter cookie?", k: 2)
        XCTAssertEqual(hits.first?.fact.value, "peanuts")
        let hits2 = try await m.retrieve("find me a climbing gym nearby", k: 1)
        XCTAssertEqual(hits2.first?.fact.value, "bouldering")
    }

    func testPersistsAcrossConnections() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("mem-\(UUID()).sqlite").path
        do { let m = try MemoryStore(db: SQLiteDB(path: path)); try await m.upsert(.init(subject: "user", attribute: "diet", value: "vegan", text: "User is vegan")) }
        let m2 = try MemoryStore(db: SQLiteDB(path: path))
        XCTAssertEqual(try m2.profile()["diet"], ["vegan"])
    }

    func testForgetRemovesSupersededChainAcrossReopen() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("forget-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("memory.sqlite").path
        var deleted: [Int64] = []
        do {
            let m = try MemoryStore(db: SQLiteDB(path: path))
            for city in ["Boston", "Brooklyn", "Queens"] {
                let result = try await m.upsert(.init(subject: "user", attribute: "lives_in", value: city, text: "User lives in \(city)"))
                deleted.append(try XCTUnwrap(result.fact).id)
            }
            try await m.upsert(.init(subject: "user", attribute: "likes", value: "jazz", text: "User likes jazz"))
            try m.forget(id: XCTUnwrap(deleted.last))
            try m.forget(id: XCTUnwrap(deleted.last))
        }
        let m = try MemoryStore(db: SQLiteDB(path: path))
        for id in deleted { XCTAssertNil(try m.fact(id: id)) }
        XCTAssertTrue(try m.history(subject: "user", attribute: "lives_in").isEmpty)
        XCTAssertTrue(try m.corrections().isEmpty)
        XCTAssertEqual(try m.active().map(\.value), ["jazz"])
    }

    func testBudgetEvictionAlsoRemovesHistoryWithoutNestedTransaction() async throws {
        let m = try store()
        for city in ["Boston", "Brooklyn"] {
            try await m.upsert(.init(subject: "user", attribute: "lives_in", value: city, text: "User lives in \(city)"))
            now += 100
        }
        m.budget = 1
        try await m.upsert(.init(subject: "user", attribute: "likes", value: "jazz", text: "User likes jazz"))
        XCTAssertEqual(try m.active().map(\.value), ["jazz"])
        XCTAssertTrue(try m.history(subject: "user", attribute: "lives_in").isEmpty)
    }
}

final class ProactiveTests: XCTestCase {
    func testArriveAtStoreNudgesViaReflex() async throws {
        let m = try MemoryStore(db: SQLiteDB(path: ":memory:"))
        try await m.upsert(.init(subject: "user", attribute: "needs_to_buy", value: "oat milk", text: "User needs to buy oat milk", ttl: 86_400))
        let e = ScriptedEngine(); e.script(whenPromptContains: "nudge the user now", logits: ["A": 4, "B": 0, "C": -2])
        let p = ProactiveEngine(memory: m, reflex: Reflex(engine: e))
        let n = try await p.handle(Trigger(kind: .arrive, date: Date(), place: "Trader Joe's grocery"))
        XCTAssertEqual(n.count, 1); XCTAssertTrue(n[0].body.contains("oat milk"))
        let none = try await p.handle(Trigger(kind: .arrive, date: Date(), place: "Office"))
        XCTAssertTrue(none.isEmpty)
    }
    func testReflexCanVetoNudge() async throws {
        let m = try MemoryStore(db: SQLiteDB(path: ":memory:"))
        try await m.upsert(.init(subject: "sam", attribute: "promise", value: "$20", text: "User owes Sam $20"))
        let e = ScriptedEngine(); e.script(whenPromptContains: "nudge the user now", logits: ["A": -2, "B": 0, "C": 4])
        let vetoed = try await ProactiveEngine(memory: m, reflex: Reflex(engine: e)).handle(Trigger(kind: .message, date: Date(), sender: "Sam Lee", text: "hey"))
        XCTAssertTrue(vetoed.isEmpty)
        let ok = try await ProactiveEngine(memory: m, reflex: nil).handle(Trigger(kind: .message, date: Date(), sender: "Sam Lee"))
        XCTAssertEqual(ok.count, 1)
    }
    func testBirthdayWindow() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/New_York")!
        let oct31 = cal.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 12))!
        XCTAssertTrue(ProactiveRules.isWithin(days: 3, of: "November 2nd", from: oct31, calendar: cal))
        XCTAssertFalse(ProactiveRules.isWithin(days: 3, of: "Nov 9", from: oct31, calendar: cal))
        XCTAssertFalse(ProactiveRules.isWithin(days: 3, of: "someday", from: oct31, calendar: cal))
    }
}
