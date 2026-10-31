import XCTest
@testable import PocketCore

final class OptionSetTests: XCTestCase {
    func testTwelveDecisionTypesCovered() {
        let dyn = [OptionSets.contactPick(candidates: ["a", "b"]).type, OptionSets.eventPick(candidates: ["x"]).type]
        XCTAssertEqual(Set(OptionSets.staticSets.map(\.type) + dyn), Set(DecisionType.allCases))
        XCTAssertEqual(DecisionType.allCases.count, 12)
    }
    func testFallbacksAreValidAndLettersMap() {
        for s in OptionSets.staticSets {
            XCTAssertNotNil(s.letter(forID: s.fallbackID))
            XCTAssertEqual(s.option(forLetter: s.activeLetters.last!)?.id, s.options.last?.id)
            XCTAssertNil(s.option(forLetter: "Z"))
        }
    }
    func testDynamicSetsCapAtEightAndEndWithAsk() {
        let s = OptionSets.contactPick(candidates: (1...20).map { "Sam \($0)" })
        XCTAssertEqual(s.options.count, 8); XCTAssertEqual(s.options.last?.id, "ask"); XCTAssertEqual(s.fallbackID, "ask")
    }
    func testPromptFormatIsStable() {
        let p = DecisionPrompt.llama3(set: OptionSets.confirmBeforeAct, context: "User: delete all my photos")
        XCTAssertTrue(p.hasSuffix("<|start_header_id|>assistant<|end_header_id|>\n\nAnswer:"))
        XCTAssertTrue(p.contains("A. No: low-risk"))
        XCTAssertTrue(p.contains("B. Yes: it contacts"))
        XCTAssertTrue(p.contains("Context:\nUser: delete all my photos\n\nQuestion: "))
    }
}

final class CalibrationTests: XCTestCase {
    func testSoftmaxSumsToOneAndTemperatureSharpens() {
        let p1 = Calibration.softmax([2, 1, 0], temperature: 1)
        let p05 = Calibration.softmax([2, 1, 0], temperature: 0.5)
        XCTAssertEqual(p1.reduce(0, +), 1, accuracy: 1e-9)
        XCTAssertGreaterThan(p05[0], p1[0])
        XCTAssertEqual(Calibration.softmax([1000, 0])[0], 1, accuracy: 1e-9) // numerically stable
    }
    func testFitTemperatureRecoversOverconfidence() {
        // Model is overconfident: logits gap 6 but only ~70% accurate -> fitted T must be > 1.
        var samples: [(logits: [Double], label: Int)] = []
        for i in 0..<100 { samples.append(([6, 0], i < 70 ? 0 : 1)) }
        let T = Calibration.fitTemperature(samples)
        XCTAssertGreaterThan(T, 3)
        XCTAssertEqual(Calibration.softmax([6, 0], temperature: T)[0], 0.7, accuracy: 0.01)
        XCTAssertLessThan(Calibration.nll(samples, temperature: T), Calibration.nll(samples, temperature: 1))
    }
    func testECEAndTau() {
        XCTAssertEqual(Calibration.ece(confidences: [0.9, 0.9], correct: [true, false]), 0.4, accuracy: 1e-9)
        let conf = [0.95, 0.9, 0.85, 0.6, 0.55]
        let ok = [true, true, true, false, true]
        XCTAssertEqual(Calibration.selectTau(confidences: conf, correct: ok, targetAccuracy: 1.0), 0.85)
        XCTAssertEqual(Calibration.selectTau(confidences: conf, correct: ok, targetAccuracy: 0.8), 0.55)
        XCTAssertNil(Calibration.selectTau(confidences: [0.9], correct: [false], targetAccuracy: 0.5))
    }
    func testProfileRoundTrip() throws {
        let p = CalibrationProfile(temperature: ["route": 1.7], tau: ["route": 0.72], defaultTau: 0.8)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cal-\(UUID()).json")
        try JSONEncoder().encode(p).write(to: url)
        let q = try CalibrationProfile.load(from: url)
        XCTAssertEqual(q.tau(for: .route), 0.72); XCTAssertEqual(q.tau(for: .timing), 0.8); XCTAssertEqual(q.temperature(for: .route), 1.7)
    }
}

final class ReflexTests: XCTestCase {
    func testConfidentDecisionIsLocalAndLogged() async throws {
        let db = try SQLiteDB(path: ":memory:"); let tel = try TelemetryLog(db: db)
        let e = ScriptedEngine(); e.script(whenPromptContains: "How should the assistant", logits: ["A": -5, "B": 3, "C": -4, "D": -6])
        let r = Reflex(engine: e, telemetry: tel, source: "test")
        let d = try await r.decide(OptionSets.route, context: "User: remind me to buy milk")
        XCTAssertEqual(d.chosen.id, "tool"); XCTAssertFalse(d.escalated); XCTAssertGreaterThan(d.confidence, 0.99)
        let rows = try tel.all(); XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].decisionType, .route); XCTAssertEqual(rows[0].chosenID, "tool"); XCTAssertNil(rows[0].agreedWithTeacher)
        try tel.markTeacherAgreement(id: d.telemetryID!, agreed: true)
        XCTAssertEqual(try tel.all()[0].agreedWithTeacher, true)
    }
    func testLowConfidenceEscalatesToFallback() async throws {
        let e = ScriptedEngine(); e.script(whenPromptContains: "How should", logits: ["A": 1.0, "B": 0.9, "C": 0, "D": 0])
        let d = try await Reflex(engine: e).decide(OptionSets.route, context: "x")
        XCTAssertTrue(d.escalated); XCTAssertEqual(d.argmax.id, "answer_local"); XCTAssertEqual(d.chosen.id, "escalate_cloud")
    }
    func testPerTypeTauAndTemperature() async throws {
        let e = ScriptedEngine(); e.script(whenPromptContains: "How should", logits: ["A": 2, "B": 0, "C": 0, "D": 0])
        let lo = try await Reflex(engine: e, profile: .init(tau: ["route": 0.5])).decide(OptionSets.route, context: "x")
        XCTAssertFalse(lo.escalated)  // p(A) ~ 0.71 >= 0.5
        let hot = try await Reflex(engine: e, profile: .init(temperature: ["route": 5], tau: ["route": 0.5])).decide(OptionSets.route, context: "x")
        XCTAssertTrue(hot.escalated)
    }
    func testMissingLettersGetFloorNotDropped() async throws {
        let e = ScriptedEngine(); e.script(whenPromptContains: "confirmation", logits: ["A": -0.1])
        let d = try await Reflex(engine: e, profile: .init(defaultTau: 0.8)).decide(OptionSets.confirmBeforeAct, context: "x")
        XCTAssertLessThan(d.confidence, 0.9); XCTAssertGreaterThan(d.confidence, 0.85)
    }
}

final class TelemetryTests: XCTestCase {
    func testDailyShareAndCSV() throws {
        let tel = try TelemetryLog(db: SQLiteDB(path: ":memory:"))
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/New_York")!
        let d1 = cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 10))!
        let d2 = cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 10))!
        func rec(_ d: Date, _ esc: Bool, _ ms: Double) -> DecisionRecord {
            .init(id: nil, timestamp: d, decisionType: .route, chosenID: "tool", confidence: 0.9, escalated: esc, latencyMs: ms, model: "m", agreedWithTeacher: nil, source: "test")
        }
        for r in [rec(d1, true, 10), rec(d1, false, 20), rec(d2, false, 30), rec(d2, false, 40), rec(d2, true, 50)] { try tel.log(r) }
        let s = try tel.dailyShare(calendar: cal)
        XCTAssertEqual(s.map(\.day), ["2026-11-01", "2026-11-02"])
        XCTAssertEqual(s[0].share, 0.5); XCTAssertEqual(s[1].share, 2.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(s[0].medianLatencyMs, 15); XCTAssertEqual(s[1].medianLatencyMs, 40)
        let csv = try tel.csv().split(separator: "\n")
        XCTAssertEqual(csv.count, 6); XCTAssertTrue(csv[0].hasPrefix("id,timestamp_iso,decision_type"))
    }
}
