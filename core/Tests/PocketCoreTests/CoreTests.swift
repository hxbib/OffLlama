import XCTest
@testable import PocketCore

final class OptionSetTests: XCTestCase {
    func testTwelveDecisionTypesCovered() {
        let dyn = [OptionSets.contactPick(candidates: ["a", "b"]).type, OptionSets.eventPick(candidates: ["x"]).type,
                   OptionSets.skillPick(candidates: ["s"]).type]   // skillPick: dynamic, untrained, appended last
        XCTAssertEqual(Set(OptionSets.staticSets.map(\.type) + dyn), Set(DecisionType.allCases))
        XCTAssertEqual(DecisionType.allCases.count, 13)   // 12 trained + skillPick
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
    func testFewShotPromptHasExemplarsWithCorrectLetters() {
        let p = DecisionPrompt.llama3(set: OptionSets.route, context: "User: hi")
        XCTAssertEqual(p.components(separatedBy: "Answer: ").count - 1, DecisionPrompt.shots.filter { $0.type == .route }.count)
        XCTAssertTrue(p.contains("Change that one") && p.contains("Answer: D<|eot_id|>"))   // clarify exemplar -> D
        for sh in DecisionPrompt.shots { XCTAssertNotNil(DecisionPrompt.setFor(sh).letter(forID: sh.answerID), sh.context) }
        XCTAssertEqual(DecisionPrompt.priorKey(OptionSets.contactPick(candidates: ["a", "b"])), "contactPick#3")
    }
    func testPromptFormatIsStable() {
        let p = DecisionPrompt.llama3(set: OptionSets.confirmBeforeAct, context: "User: delete all my photos", style: .zeroShot)
        XCTAssertTrue(p.hasSuffix("<|start_header_id|>assistant<|end_header_id|>\n\nAnswer:"))
        XCTAssertTrue(p.contains("A. Safe and reversible"))
        XCTAssertTrue(p.contains("B. Risky:"))
        XCTAssertEqual(p.components(separatedBy: "<|start_header_id|>user").count, 2)  // zero-shot: one user turn
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
    func testContextualCalibrationRemovesLetterPrior() async throws {
        // Model always favours D ("clarify") by +2 regardless of input; prior correction cancels that bias.
        let e = ScriptedEngine(); e.script(whenPromptContains: "How should", logits: ["A": 0, "B": 1.5, "C": 0, "D": 2])
        let raw = try await Reflex(engine: e).decide(OptionSets.route, context: "x")
        XCTAssertEqual(raw.argmax.id, "clarify")
        let prior = Calibration.softmax([0, 0, 0, 2]).map { log($0) }
        let fixed = try await Reflex(engine: e, profile: .init(prior: ["route": prior])).decide(OptionSets.route, context: "x")
        XCTAssertEqual(fixed.argmax.id, "tool")
    }
    func testMeasurePriorsCoversAllSets() async throws {
        let e = ScriptedEngine()
        let pr = try await Reflex(engine: e).measurePriors()
        XCTAssertNotNil(pr["route"]); XCTAssertEqual(pr["contactPick#8"]?.count, 8); XCTAssertEqual(pr["eventPick#2"]?.count, 2)
        XCTAssertEqual(pr.count, OptionSets.staticSets.count + 14)
    }
    func testOldCalibrationJSONStillDecodes() throws {
        let p = try JSONDecoder().decode(CalibrationProfile.self, from: Data(#"{"temperature":{"route":2},"tau":{},"defaultTau":0.7}"#.utf8))
        XCTAssertEqual(p.defaultTau, 0.7); XCTAssertTrue(p.prior.isEmpty); XCTAssertEqual(p.promptStyle, .fewShot)
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
        var r2 = rec(d2, false, 5); r2.model = "round2"; try tel.log(r2)
        let byModel = try tel.shareByModel()
        XCTAssertEqual(byModel.map(\.model), ["m", "round2"]); XCTAssertEqual(byModel[0].handledLocally, 3); XCTAssertEqual(byModel[1].total, 1)
        let csv = try tel.csv().split(separator: "\n").dropLast()
        XCTAssertEqual(csv.count, 6); XCTAssertTrue(csv[0].hasPrefix("id,timestamp_iso,decision_type,chosen,confidence,escalated,latency_ms,model,agreed_with_teacher,source,"))
    }

    func testDistillationLoopRoundTripExportAndVerdicts() async throws {
        let db = try SQLiteDB(path: ":memory:"); let tel = try TelemetryLog(db: db)
        let now = Date(timeIntervalSince1970: 1_793_000_000)
        let e = ScriptedEngine()
        e.script(whenPromptContains: "How should", logits: ["A": -5, "B": 3, "C": -4, "D": -6])          // confident
        e.script(whenPromptContains: "acceptable to send", logits: ["A": 0.1, "B": 0])                    // escalates
        let r = Reflex(engine: e, telemetry: tel, source: "test", clock: { now })
        let ok = try await r.decide(OptionSets.route, context: "User: remind me, \"quoted\"")
        let esc = try await r.decide(OptionSets.sensitivity, context: "User: my LDL is 210")
        let rows = try tel.all()
        XCTAssertEqual(rows[0].context, "User: remind me, \"quoted\"")
        XCTAssertEqual(rows[0].optionIDs, ["answer_local", "tool", "escalate_cloud", "clarify"])
        XCTAssertEqual(rows[0].probabilities?["tool"] ?? 0, ok.probabilities["tool"]!, accuracy: 1e-12)
        XCTAssertEqual(rows[1].probabilities?.count, 2)

        let q = try tel.exportDistillationQueue(sinceDays: 30, now: now + 3600)
        let lines = q.split(separator: "\n")
        XCTAssertEqual(lines.count, 1)
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any])
        XCTAssertEqual(Set(o.keys), ["id", "type", "context", "option_ids", "student_probs", "confidence", "ts", "source"])
        XCTAssertEqual(o["id"] as? Int, Int(esc.telemetryID!)); XCTAssertEqual(o["type"] as? String, "sensitivity")
        XCTAssertEqual(o["context"] as? String, "User: my LDL is 210"); XCTAssertEqual(o["option_ids"] as? [String], ["ok", "sensitive"])
        XCTAssertEqual((o["student_probs"] as? [String: Double])?["ok"] ?? 0, esc.probabilities["ok"]!, accuracy: 1e-9)
        XCTAssertEqual(o["ts"] as? String, "2026-10-26T07:33:20Z"); XCTAssertEqual(o["source"] as? String, "test")
        XCTAssertEqual(try tel.exportDistillationQueue(sinceDays: 30, now: now + 31 * 86_400), "")    // window

        let n = try tel.importTeacherVerdicts(jsonl: "{\"id\": \(esc.telemetryID!), \"agreed\": false}\nnot json\n{\"id\": 999, \"agreed\": true}\n{\"id\": \(ok.telemetryID!), \"agreed\": true}")
        XCTAssertEqual(n, 2)
        XCTAssertEqual(try tel.all().map(\.agreedWithTeacher), [true, false])

        // Pre-context database migrates; old rows decode with nil context.
        let old = try SQLiteDB(path: ":memory:")
        try old.exec("CREATE TABLE decisions(id INTEGER PRIMARY KEY AUTOINCREMENT, ts REAL NOT NULL, type TEXT NOT NULL, chosen TEXT NOT NULL, confidence REAL NOT NULL, escalated INTEGER NOT NULL, latency_ms REAL NOT NULL, model TEXT NOT NULL, agreed_teacher INTEGER, source TEXT NOT NULL)")
        try old.run("INSERT INTO decisions(ts,type,chosen,confidence,escalated,latency_ms,model,source) VALUES(1793000000,'route','tool',0.5,1,3,'m','device')")
        let t2 = try TelemetryLog(db: old)
        XCTAssertNil(try t2.all()[0].context)
        XCTAssertEqual(try t2.exportDistillationQueue(sinceDays: 30, now: now), "")
        try t2.log(rows[1]); XCTAssertEqual(try t2.all()[1].optionIDs, ["ok", "sensitive"])
        XCTAssertEqual(try t2.exportDistillationQueue(sinceDays: 30, now: now).split(separator: "\n").count, 1)
    }

    func testDistillationExportSkipsMissingAndBlankContexts() throws {
        let tel = try TelemetryLog(db: SQLiteDB(path: ":memory:"))
        let now = Date(timeIntervalSince1970: 1_793_000_000)
        for context in [nil, "", " \n\t", "User: remind me"] as [String?] {
            try tel.log(.init(id: nil, timestamp: now, decisionType: .route, chosenID: "tool",
                              confidence: 0.5, escalated: true, latencyMs: 1, model: "test",
                              agreedWithTeacher: nil, source: "test", context: context))
        }
        let lines = try tel.exportDistillationQueue(now: now).split(separator: "\n")
        XCTAssertEqual(lines.count, 1)
        let row = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(XCTUnwrap(lines.last).utf8)) as? [String: Any])
        XCTAssertEqual(row["context"] as? String, "User: remind me")
        XCTAssertEqual(try tel.all().count, 4)
    }
}
