import XCTest
@testable import PocketCore

final class CuratorMemoryTests: XCTestCase {
    var now = Date(timeIntervalSince1970: 1_793_000_000)

    func testProvenanceStoredAndMigrated() async throws {
        let db = try SQLiteDB(path: ":memory:")
        // pre-provenance schema
        try db.exec("CREATE TABLE facts(id INTEGER PRIMARY KEY AUTOINCREMENT, subject TEXT NOT NULL, attribute TEXT NOT NULL, value TEXT NOT NULL, text TEXT NOT NULL, created REAL NOT NULL, updated REAL NOT NULL, expires REAL, superseded_by INTEGER, embedding BLOB NOT NULL, embedder TEXT NOT NULL)")
        try db.run("INSERT INTO facts(subject,attribute,value,text,created,updated,embedding,embedder) VALUES('user','likes','tea','User likes tea',0,0,x'00000000','h')")
        let m = try MemoryStore(db: db, clock: { [unowned self] in self.now })
        XCTAssertEqual(try m.active().first?.provenance, MemoryProvenance.userStated)
        let r = try await m.upsert(.init(subject: "user", attribute: "likes", value: "jazz", text: "User likes jazz", provenance: MemoryProvenance.cloud))
        XCTAssertEqual(r.fact?.provenance, MemoryProvenance.cloud)
    }

    func testBudgetEvictsLeastTrustedThenOldest() async throws {
        let m = try MemoryStore(db: SQLiteDB(path: ":memory:"), clock: { [unowned self] in self.now }, budget: 2)
        try await m.upsert(.init(subject: "user", attribute: "likes", value: "a", text: "User likes a", provenance: MemoryProvenance.userStated))
        now += 1
        try await m.upsert(.init(subject: "user", attribute: "likes", value: "b", text: "User likes b", provenance: MemoryProvenance.cloud))
        now += 1
        try await m.upsert(.init(subject: "user", attribute: "likes", value: "c", text: "User likes c", provenance: MemoryProvenance.modelExtracted))
        XCTAssertEqual(Set(try m.active().map(\.value)), ["a", "c"])   // cloud row evicted first
        now += 1
        try await m.upsert(.init(subject: "user", attribute: "likes", value: "d", text: "User likes d", provenance: MemoryProvenance.userStated))
        XCTAssertEqual(Set(try m.active().map(\.value)), ["a", "d"])   // then model_extracted
    }

    func testCorrectionsRetrievedIntoReflexContext() async throws {
        let m = try MemoryStore(db: SQLiteDB(path: ":memory:"), clock: { [unowned self] in self.now }, correctionBudget: 2)
        let set = OptionSets.staticSets.first!
        try await m.recordCorrection(type: set.type, context: "User: remind me to call mom tonight", wrongID: "a", correctID: "b")
        let ctx = try await m.reflexContext(for: set, context: "User: remind me to call dad tonight")
        XCTAssertTrue(ctx.hasPrefix("Past user corrections"))
        XCTAssertTrue(ctx.contains("correct: b (not a)"))
        XCTAssertTrue(ctx.hasSuffix("User: remind me to call dad tonight"))
        let unrelated = try await m.reflexContext(for: set, context: "zzz qqq")
        XCTAssertEqual(unrelated, "zzz qqq")
        // other decision types don't leak
        let other = OptionSets.staticSets.first { $0.type != set.type }!
        let o = try await m.reflexContext(for: other, context: "User: remind me to call dad tonight")
        XCTAssertEqual(o, "User: remind me to call dad tonight")
        // correction budget
        for i in 0..<3 { try await m.recordCorrection(type: set.type, context: "ctx \(i)", wrongID: "a", correctID: "b") }
        XCTAssertEqual(try m.db.query("SELECT COUNT(*) AS n FROM corrections").first?["n"]?.int, 2)
    }
}
