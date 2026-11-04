import XCTest
@testable import PocketCore

final class MemoryProfileTests: XCTestCase {
    var now = Date(timeIntervalSince1970: 1_793_000_000)   // 2026-10-26
    func store(budget: Int? = nil, db: SQLiteDB? = nil) throws -> MemoryStore {
        try MemoryStore(db: db ?? SQLiteDB(path: ":memory:"), clock: { [unowned self] in self.now }, budget: budget)
    }
    func day(_ d: Date) -> String { MemoryStore.day(d) }

    func testOnePagerSectionsCorrectionsEntitiesAndBound() async throws {
        let m = try store()
        try await m.upsert(.init(subject: "user", attribute: "lives_in", value: "Boston", text: "User lives in Boston"))
        try await m.upsert(.init(subject: "user", attribute: "works_at", value: "Hunter College", text: "User works at Hunter College"))
        try await m.upsert(.init(subject: "user", attribute: "likes", value: "bouldering", text: "User likes bouldering"))
        try await m.upsert(.init(subject: "user", attribute: "communication_style", value: "short replies", text: "User prefers short replies"))
        try await m.upsert(.init(subject: "user", attribute: "todo", value: "submit CSCI 335 project", text: "To do: submit CSCI 335 project", ttl: 3 * 86_400))
        for f in RuleFactExtractor.extract("My mom's name is Linda") { try await m.upsert(f) }
        try await m.upsert(.init(subject: "linda", attribute: "birthday", value: "March 3", text: "Linda's birthday is March 3"))
        try await m.recordCorrection(type: .confirmBeforeAct, context: "Planned action: create_event dinner", wrongID: "act", correctID: "confirm")
        now += 86_400
        try await m.upsert(.init(subject: "user", attribute: "lives_in", value: "the Bronx", text: "User lives in the Bronx"))

        let p = try m.profileOnePager(maxChars: 2000)
        XCTAssertTrue(p.hasPrefix("Profile (as of \(day(now))):"), p)
        XCTAssertTrue(p.contains("Life context: works at Hunter College; lives in the Bronx"), p)
        XCTAssertFalse(p.contains("lives in Boston;"), p)
        XCTAssertTrue(p.contains("Autonomy: confirmBeforeAct: confirm not act (1x, last \(day(now - 86_400)))"), p)
        XCTAssertTrue(p.contains("Style: communication style short replies"), p)
        XCTAssertTrue(p.contains("Preferences: likes bouldering"), p)
        XCTAssertTrue(p.contains("Corrected by you: \(day(now)) lives in Boston -> the Bronx"), p)
        XCTAssertTrue(p.contains("Linda (aka mom, my mom): relation mom, birthday March 3"), p)
        XCTAssertTrue(p.contains("Open tasks: submit CSCI 335 project"), p)

        for cap in [60, 150, 300] {
            let short = try m.profileOnePager(maxChars: cap)
            XCTAssertLessThanOrEqual(short.count, cap); XCTAssertTrue(short.hasPrefix("Profile"))
        }
        XCTAssertEqual(try store().profileOnePager(), "")
    }

    func testAliasRetrievalHitAndMigration() async throws {
        let m = try store()
        for f in RuleFactExtractor.extract("My mom's name is Linda") { try await m.upsert(f) }
        try await m.upsert(.init(subject: "linda", attribute: "birthday", value: "March 3", text: "Linda's birthday is March 3"))
        try await m.upsert(.init(subject: "user", attribute: "allergy", value: "peanuts", text: "User is allergic to peanuts"))
        try await m.upsert(.init(subject: "user", attribute: "likes", value: "bouldering", text: "User likes bouldering at the climbing gym"))
        XCTAssertEqual(try m.aliases(forSubject: "Linda"), ["mom", "my mom"])
        XCTAssertEqual(try m.active().first { $0.attribute == "birthday" }?.aliases, ["mom", "my mom"])   // inherited by the entity's new rows

        let hits = try await m.retrieve("get Mom flowers", k: 2)
        XCTAssertEqual(Set(hits.map(\.fact.subject)), ["linda"])
        XCTAssertTrue(hits.allSatisfy { $0.score >= 0.6 })
        XCTAssertEqual(try m.addAliases(["Mother"], to: "linda"), ["mom", "my mom", "mother"])
        let h2 = try await m.retrieve("what does my mother want", k: 1)
        XCTAssertEqual(h2.first?.fact.subject, "linda")
        XCTAssertEqual(try m.addAliases(["x"], to: "nobody"), [])
        // Dense path unchanged for non-alias queries.
        let h3 = try await m.retrieve("can I eat this peanut butter cookie?", k: 1)
        XCTAssertEqual(h3.first?.fact.value, "peanuts")

        // Pre-alias database (has provenance, no aliases column) migrates.
        let db = try SQLiteDB(path: ":memory:")
        try db.exec("CREATE TABLE facts(id INTEGER PRIMARY KEY AUTOINCREMENT, subject TEXT NOT NULL, attribute TEXT NOT NULL, value TEXT NOT NULL, text TEXT NOT NULL, created REAL NOT NULL, updated REAL NOT NULL, expires REAL, superseded_by INTEGER, embedding BLOB NOT NULL, embedder TEXT NOT NULL, provenance TEXT NOT NULL DEFAULT 'user_stated')")
        try db.run("INSERT INTO facts(subject,attribute,value,text,created,updated,embedding,embedder) VALUES('sam','relation','roommate','Sam is the user''s roommate',0,0,x'00000000','h')")
        let old = try store(db: db)
        XCTAssertEqual(try old.active().first?.aliases, [])
        try old.addAliases(["roomie"], to: "sam")
        let h4 = try await old.retrieve("ask my roomie", k: 1)
        XCTAssertEqual(h4.first?.fact.subject, "sam")
    }

    func testConsolidateDedupesSupersedesPurgesAndBudgets() async throws {
        let m = try store()
        try await m.upsert(.init(subject: "user", attribute: "allergy", value: "peanuts", text: "User is allergic to peanuts", aliases: ["nuts"]))
        now += 10
        try await m.upsert(.init(subject: "user", attribute: "allergy", value: "Peanut.", text: "User is allergic to peanut", provenance: MemoryProvenance.userCorrection))
        try await m.upsert(.init(subject: "user", attribute: "allergy", value: "shellfish", text: "User is allergic to shellfish"))
        now += 10
        try await m.upsert(.init(subject: "user", attribute: "lives_in", value: "Boston", text: "User lives in Boston"))
        now += 86_400
        try await m.upsert(.init(subject: "user", attribute: "lives_in", value: "Bronx", text: "User lives in Bronx")) { _, _ in .keepBoth }
        try await m.upsert(.init(subject: "user", attribute: "needs_to_buy", value: "milk", text: "User needs milk", ttl: 60))
        XCTAssertEqual(try m.profile()["lives_in"]?.count, 2)
        XCTAssertEqual(try m.profile()["allergy"]?.count, 3)
        now += 120

        let r = try m.consolidate()
        XCTAssertEqual(r, ConsolidationReport(purgedExpired: 1, deduplicated: 1, superseded: 1, evicted: 0))
        let allergy = try m.active().filter { $0.attribute == "allergy" }
        XCTAssertEqual(Set(allergy.map(\.value)), ["Peanut.", "shellfish"])            // most trusted duplicate kept
        XCTAssertEqual(allergy.first { $0.value == "Peanut." }?.aliases, ["nuts"])      // aliases merged
        XCTAssertEqual(try m.profile()["lives_in"], ["Bronx"])
        let h = try m.history(subject: "user", attribute: "lives_in")
        XCTAssertEqual(h.count, 2); XCTAssertEqual(h[0].supersededBy, h[1].id)        // versioned, dated history
        XCTAssertEqual(try m.corrections().first.map { "\($0.old.value)->\($0.new.value)" }, "Boston->Bronx")
        XCTAssertEqual(try m.consolidate(), ConsolidationReport())                      // idempotent

        // Daily schedule + budget enforcement.
        XCTAssertNil(try m.consolidateIfDue())
        m.budget = 2
        now += 86_401
        let r2 = try XCTUnwrap(try m.consolidateIfDue())
        XCTAssertEqual(r2.evicted, 1); XCTAssertEqual(try m.active().count, 2)
        XCTAssertEqual(m.lastConsolidated, now)

        // A restated older value (duplicate merged) beats an intermediate one.
        let m2 = try store()
        try await m2.upsert(.init(subject: "user", attribute: "gym_time", value: "7am", text: "User goes to the gym at 7am")) { _, _ in .keepBoth }
        now += 10
        try await m2.upsert(.init(subject: "user", attribute: "gym_time", value: "6pm", text: "User goes to the gym at 6pm")) { _, _ in .keepBoth }
        now += 10
        try await m2.upsert(.init(subject: "user", attribute: "gym_time", value: "7AM.", text: "User goes to the gym at 7AM")) { _, _ in .keepBoth }
        let r3 = try m2.consolidate()
        XCTAssertEqual(r3.deduplicated, 1); XCTAssertEqual(r3.superseded, 1)
        XCTAssertEqual(try m2.profile()["gym_time"].map { $0.map { MemoryStore.normalizedValue($0) } }, ["7am"])
    }

    func testTasksBoard() async throws {
        let m = try store()
        let ex = RuleFactExtractor.extract("Add renew my passport to my to-do list")
        XCTAssertEqual(ex.first?.attribute, "todo"); XCTAssertEqual(ex.first?.value, "renew my passport")
        for f in ex { try await m.upsert(f) }
        try await m.upsert(.init(subject: "user", attribute: "reminder", value: "call the dentist", text: "Reminder: call the dentist", ttl: 3600))
        try await m.upsert(.init(subject: "user", attribute: "needs_to_buy", value: "oat milk", text: "User needs to buy oat milk", ttl: 7 * 86_400))
        try await m.upsert(.init(subject: "user", attribute: "likes", value: "jazz", text: "User likes jazz"))
        let b = try m.tasksBoard()
        XCTAssertEqual(b.dueSoon.map(\.fact.value), ["call the dentist"])
        XCTAssertEqual(b.open.map(\.fact.value), ["renew my passport"])
        XCTAssertEqual(b.shopping.map(\.fact.value), ["oat milk"])
        XCTAssertTrue(b.text.hasPrefix("Tasks board\nDue soon:\n- [ ] call the dentist (by "), b.text)
        XCTAssertTrue(b.text.contains("Open:\n- [ ] renew my passport"))
        XCTAssertTrue(try store().tasksBoard().isEmpty)
    }

    func testProfileReachesLocalPromptAndScrubbedCloudPrompt() async throws {
        let db = try SQLiteDB(path: ":memory:")
        let mem = try MemoryStore(db: db)
        for f in RuleFactExtractor.extract("My mom's name is Linda") { try await mem.upsert(f) }
        try await mem.upsert(.init(subject: "user", attribute: "lives_in", value: "the Bronx", text: "User lives in the Bronx"))
        try await mem.upsert(.init(subject: "user", attribute: "allergy", value: "peanuts", text: "User is allergic to peanuts"))
        try await mem.upsert(.init(subject: "user", attribute: "todo", value: "pay rent", text: "To do: pay rent"))
        XCTAssertTrue(try mem.profileOnePager(maxChars: 2000).contains("allergy peanuts"))
        let red = try mem.profileOnePager(maxChars: 2000, redactSensitive: true)
        XCTAssertFalse(red.contains("peanuts"), red); XCTAssertFalse(red.contains("pay rent"), red); XCTAssertTrue(red.contains("lives in the Bronx"), red)

        let e = ScriptedEngine(); e.generated = "Hi!"
        e.script(whenPromptContains: "How should", logits: ["A": 5, "B": -3, "C": -3, "D": -3])
        let local = Assistant(reflex: Reflex(engine: e), memory: mem, actions: RecordingActions())
        _ = try await local.handle("Good morning!")
        let lp = try XCTUnwrap(e.generatePrompts.last)
        XCTAssertTrue(lp.contains("Profile (as of "), lp); XCTAssertTrue(lp.contains("lives in the Bronx"), lp)
        local.profileMaxChars = 0
        _ = try await local.handle("Good morning!")
        XCTAssertFalse(e.generatePrompts.last!.contains("Profile (as of"))

        let e2 = ScriptedEngine()
        e2.script(whenPromptContains: "acceptable to send this request", logits: ["A": 5, "B": -5])
        final class Box: @unchecked Sendable { var sent = "" }
        let box = Box()
        var brain = OpenAICompatibleBrain(providerName: "Meta Model API", model: "muse-spark-1.3", baseURL: URL(string: "https://example.invalid/v1/")!, apiKey: "k")
        brain.transport = { req in
            box.sent = String(decoding: req.httpBody!, as: UTF8.self)
            return (Data(#"{"choices":[{"message":{"content":"Ask [PERSON_1]."}}]}"#.utf8), 200)
        }
        let cloud = Assistant(reflex: Reflex(engine: e2), memory: mem, actions: RecordingActions(), cloud: CloudBrainChain([brain]), isOnline: { true })
        let t = try await cloud.handle("Plan a weekend trip for me and Linda")
        XCTAssertEqual(t.reply, .cloud("Ask Linda.", provider: "Meta Model API · muse-spark-1.3"))
        let sent = try XCTUnwrap(t.cloudPromptSent)
        XCTAssertTrue(sent.hasPrefix("Profile (as of "), sent)
        XCTAssertFalse(sent.contains("Linda"), sent); XCTAssertFalse(box.sent.contains("Linda"))
        XCTAssertTrue(sent.contains("[PERSON_1]"), sent)
        XCTAssertFalse(sent.components(separatedBy: "Known about the user").first!.contains("peanuts"), sent)   // profile part is redacted
        XCTAssertLessThanOrEqual(sent.components(separatedBy: "\n").first!.count, 40)
    }
}

final class MorningBriefTests: XCTestCase {
    func testMorningBriefAssemblesBoardAndEventsGatedOncePerDay() async throws {
        var now = Date(timeIntervalSince1970: 1_793_000_000)
        let m = try MemoryStore(db: SQLiteDB(path: ":memory:"), clock: { now })
        try await m.upsert(.init(subject: "user", attribute: "todo", value: "submit CSCI 335 project", text: "To do: submit CSCI 335 project", ttl: 86_400))
        try await m.upsert(.init(subject: "user", attribute: "todo", value: "renew passport", text: "To do: renew passport", ttl: 20 * 86_400))
        try await m.upsert(.init(subject: "user", attribute: "needs_to_buy", value: "oat milk", text: "User needs to buy oat milk", ttl: 7 * 86_400))
        let e = ScriptedEngine(); e.script(whenPromptContains: "nudge the user now", logits: ["A": -2, "B": 4, "C": -2])   // "later"
        let p = ProactiveEngine(memory: m, reflex: Reflex(engine: e))
        p.todayEvents = { _ in ["Standup 9:00 AM", "Dentist 2:30 PM"] }
        let t = Trigger(kind: .morning, date: now)
        let vetoed = try await p.handle(t)
        XCTAssertTrue(vetoed.isEmpty)                                       // Reflex said later: nothing, and retry allowed
        e.script(whenPromptContains: "nudge the user now", logits: ["A": 4, "B": -2, "C": -2])
        let n = try await p.handle(t)
        XCTAssertEqual(n.count, 1)
        XCTAssertEqual(n[0].title, "Good morning")
        XCTAssertEqual(n[0].body, "Today: Standup 9:00 AM; Dentist 2:30 PM\nDue soon: submit CSCI 335 project\nTo do: renew passport\nBuy: oat milk")
        XCTAssertEqual(n[0].factIDs.count, 3); XCTAssertGreaterThan(n[0].confidence, 0.9)
        let again = try await p.handle(Trigger(kind: .morning, date: now + 3600))
        XCTAssertTrue(again.isEmpty)                                        // once per day
        now += 86_400
        let tomorrow = try await p.handle(Trigger(kind: .morning, date: now))
        XCTAssertEqual(tomorrow.count, 1)
        // Nothing to say => no brief, no Reflex call.
        let empty = ProactiveEngine(memory: try MemoryStore(db: SQLiteDB(path: ":memory:")), reflex: Reflex(engine: e))
        let calls = e.calls
        let none = try await empty.handle(Trigger(kind: .morning, date: now))
        XCTAssertTrue(none.isEmpty); XCTAssertEqual(e.calls, calls)
        // Other trigger kinds never produce a brief.
        let arrive = try await p.handle(Trigger(kind: .arrive, date: now + 86_400, place: "Office"))
        XCTAssertTrue(arrive.isEmpty)
    }
}
