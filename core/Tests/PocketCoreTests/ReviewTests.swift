import XCTest
@testable import PocketCore

/// Hand-computed / cross-checked values added in the Nov 4 code review (docs/CODE_REVIEW_NOV4.md).
final class ReviewStatsTests: XCTestCase {
    /// eval/results/after_floor.calibration_split.json (shipping ep1 Q4_K_M, cal180), conf rounded to 6 dp (no row sits
    /// within 1e-6 of a grid point). Python twin training/pg_train/conformal.py gives the same numbers.
    static let calConf: [Double] = "0.924087,0.712673,0.778169,0.987822,0.959202,0.864441,0.965414,0.964931,0.901299,0.449170,0.830484,0.436480,0.654875,0.722031,0.396124,0.826048,0.918036,0.477476,0.492097,0.501008,0.951094,0.936857,0.663988,0.825892,0.790990,0.629549,0.438658,0.599419,0.400418,0.960080,0.963850,0.886840,0.610161,0.645326,0.934604,0.637338,0.923581,0.979930,0.638131,0.666992,0.677592,0.992442,0.774203,0.572306,0.885825,0.937716,0.947445,0.979570,0.912358,0.427871,0.741775,0.953296,0.963032,0.987540,0.973460,0.983440,0.995196,0.342682,0.446998,0.617880,0.767026,0.811175,0.668611,0.673705,0.357600,0.963295,0.785035,0.376651,0.571785,0.429846,0.484372,0.967718,0.713459,0.726537,0.462173,0.936805,0.978748,0.867083,0.861927,0.808739,0.492724,0.677167,0.798883,0.769137,0.986248,0.477916,0.828376,0.883557,0.454522,0.731562,0.878735,0.899024,0.751842,0.974235,0.734492,0.825242,0.572061,0.897378,0.951020,0.801083,0.513465,0.449511,0.508050,0.423792,0.492495,0.539230,0.447053,0.977758,0.471501,0.505846,0.722927,0.486635,0.789801,0.943478,0.939116,0.989949,0.712129,0.970357,0.762296,0.687449,0.709944,0.643083,0.741387,0.574783,0.900472,0.907338,0.591981,0.784134,0.953723,0.928683,0.921285,0.692281,0.970899,0.897422,0.882635,0.974258,0.688020,0.978204,0.876261,0.901961,0.669913,0.623795,0.667995,0.533078,0.668571,0.756240,0.559924,0.977631,0.918450,0.738493,0.977261,0.502860,0.975719,0.678858,0.998237,0.966564,0.947919,0.316717,0.998260,0.600287,0.997647,0.603179,0.959849,0.860902,0.910833,0.897113,0.904265,0.608988,0.990443,0.701218,0.963141,0.830731,0.974610,0.505662,0.430100,0.950273,0.988523,0.995040,0.848876,0.876990".split(separator: ",").map { Double($0)! }
    static let calOK: [Bool] = "111111111011111111001101010101101111111101111111100111111001111101101101111111111100111111110111111011000011001111111111111111111111111111111100011110101011101010111011101111011101".map { $0 == "1" }

    func testShippingCal180BoundMatchesPythonAndDocs() {
        XCTAssertEqual(Self.calConf.count, 180); XCTAssertEqual(Self.calOK.filter { $0 }.count, 141)
        let b = ConformalRisk.tightestBound(confidences: Self.calConf, correct: Self.calOK, delta: 0.1)!
        XCTAssertEqual(b.tau, 0.90); XCTAssertEqual(b.handled, 64); XCTAssertEqual(b.errors, 0)
        XCTAssertEqual(b.errorUpperBound, 0.10217188684009713, accuracy: 1e-9)       // = 1 - (0.1/99)^(1/64)
        XCTAssertEqual(b.errorUpperBound, 1 - pow(0.1 / 99, 1.0 / 64), accuracy: 1e-9)
        let r = ConformalRisk.calibrate(confidences: Self.calConf, correct: Self.calOK, alpha: 0.05, delta: 0.1)
        XCTAssertNil(r.tau)                                                           // 64 < 135 rows: alpha 5% not certifiable
        XCTAssertEqual(ConformalRisk.minRowsNeeded(alpha: 0.05, delta: 0.1), 135)
        XCTAssertEqual(ConformalRisk.minRowsForZeroErrors(alpha: 0.05, delta: 0.1, k: 99), 135)
        // 135 is tight: (0.95)^134 > 0.1/99 >= (0.95)^135
        XCTAssertGreaterThan(pow(0.95, 134), 0.1 / 99); XCTAssertLessThanOrEqual(pow(0.95, 135), 0.1 / 99)
    }

    func testClopperPearsonOneError() {
        // P(Bin(10, u) <= 1) = 0.05 at u = 0.39416 (scipy.stats.beta.ppf(0.95, 2, 9) = 0.394163).
        XCTAssertEqual(ConformalRisk.clopperPearsonUpper(1, 10, delta: 0.05), 0.3941633, accuracy: 1e-6)
        XCTAssertEqual(ConformalRisk.binomCDF(1, 10, 0.3941633), 0.05, accuracy: 1e-6)
        XCTAssertEqual(ConformalRisk.clopperPearsonUpper(0, 0, delta: 0.1), 1)
        XCTAssertEqual(ConformalRisk.clopperPearsonUpper(5, 5, delta: 0.1), 1)
    }

    func testConformalEdgeCases() {
        let empty = ConformalRisk.calibrate(confidences: [], correct: [])
        XCTAssertNil(empty.tau); XCTAssertEqual(empty.n, 0); XCTAssertEqual(empty.handledShare, 0)
        XCTAssertNil(ConformalRisk.tightestBound(confidences: [], correct: []))
        // Below the lowest grid point: nothing is ever "handled".
        XCTAssertNil(ConformalRisk.tightestBound(confidences: [0.001, 0.005], correct: [true, true]))
        // All wrong: never certifiable, bound stays 1.
        let allWrong = ConformalRisk.calibrate(confidences: Array(repeating: 0.99, count: 500), correct: Array(repeating: false, count: 500))
        XCTAssertNil(allWrong.tau)
        XCTAssertEqual(ConformalRisk.tightestBound(confidences: Array(repeating: 0.99, count: 50), correct: Array(repeating: false, count: 50))!.errorUpperBound, 1)
        // A tau is handled with conf >= tau (inclusive), matching Reflex (escalate iff conf < tau).
        let b = ConformalRisk.tightestBound(confidences: [0.5], correct: [true], grid: [0.5])!
        XCTAssertEqual(b.handled, 1)
    }

    func testECEHandComputed() {
        // bins: (0.9,1.0] {0.95 ok, 0.95 wrong} -> |0.5-0.95|*2/5 = 0.18; (0.5,0.6] {0.55, 0.55 ok} -> |1-0.55|*2/5 = 0.18;
        // (0.1,0.2] {0.15 wrong} -> |0-0.15|/5 = 0.03. Total 0.39 (pg_train.calibrate.ece gives 0.39).
        XCTAssertEqual(Calibration.ece(confidences: [0.95, 0.95, 0.55, 0.55, 0.15], correct: [true, false, true, true, false]), 0.39, accuracy: 1e-12)
        XCTAssertEqual(Calibration.ece(confidences: [], correct: []), 0)
        XCTAssertEqual(Calibration.ece(confidences: [0, 1], correct: [false, true]), 0, accuracy: 1e-12)   // edges land in bins
    }
}

final class ReviewReflexTests: XCTestCase {
    func testTieGoesToFirstLetterAndTauIsInclusive() async throws {
        // Equal logits on a 2-option set: p = 0.5/0.5. Python max() picks the first index; so must Swift.
        let e = ScriptedEngine(); e.script(whenPromptContains: "confirmation", logits: ["A": 1, "B": 1])
        let d = try await Reflex(engine: e, profile: .init(defaultTau: 0.5)).decide(OptionSets.confirmBeforeAct, context: "x")
        XCTAssertEqual(d.argmax.id, "act"); XCTAssertEqual(d.confidence, 0.5, accuracy: 1e-12)
        XCTAssertFalse(d.escalated)                                  // conf == tau is handled (>=), as in eval score_decisions.py covered
    }

    func testFloorAndPriorHandComputed() async throws {
        // Seen: A = -0.5, C = -1.5; B missing -> floor = min(seen) - 2 = -3.5. Prior [ -1, -2, -1 ] subtracted.
        // Adjusted: [0.5, -1.5, -0.5] -> softmax = e^{0.5}, e^{-1.5}, e^{-0.5} / sum.
        let e = ScriptedEngine(); e.script(whenPromptContains: "long-term memory", logits: ["A": -0.5, "C": -1.5])
        let tel = try TelemetryLog(db: SQLiteDB(path: ":memory:"))
        let prof = CalibrationProfile(defaultTau: 0.9, prior: ["rememberOrNot": [-1, -2, -1]])
        let d = try await Reflex(engine: e, profile: prof, telemetry: tel).decide(OptionSets.rememberOrNot, context: "x")
        let z = exp(0.5) + exp(-1.5) + exp(-0.5)
        XCTAssertEqual(d.probabilities["remember_fact"]!, exp(0.5) / z, accuracy: 1e-12)
        XCTAssertEqual(d.probabilities["remember_temporary"]!, exp(-1.5) / z, accuracy: 1e-12)
        XCTAssertEqual(d.confidence, exp(0.5) / z, accuracy: 1e-12)  // 0.6652 < 0.9 -> escalates to fallback "no"
        XCTAssertTrue(d.escalated); XCTAssertEqual(d.chosen.id, "no"); XCTAssertEqual(d.argmax.id, "remember_fact")
        XCTAssertEqual(try tel.all().first?.chosenID, "remember_fact")   // telemetry logs the argmax, not the fallback
    }

    func testReadOnlyTelemetryDoesNotDiscardTheDecision() async throws {
        let db = try SQLiteDB(path: ":memory:")
        let tel = try TelemetryLog(db: db)
        try db.exec("PRAGMA query_only=ON")
        let e = ScriptedEngine()
        e.script(whenPromptContains: "confirmation", logits: ["A": 5, "B": -5])
        let decision = try await Reflex(engine: e, telemetry: tel).decide(OptionSets.confirmBeforeAct, context: "synthetic request")
        XCTAssertEqual(decision.chosen.id, "act")
        XCTAssertFalse(decision.escalated)
        XCTAssertNil(decision.telemetryID)
        XCTAssertTrue(try tel.all().isEmpty)
    }
}

final class ReviewPrivacyTests: XCTestCase {
    func testRestoreWithTenPlusPlaceholdersDoesNotCollide() {
        let names = (1...12).map { "Name\($0)x" }
        let s = PrivacyScrubber(knownNames: names)
        let input = names.joined(separator: " and ") + " met."
        let r = s.scrub(input)
        XCTAssertTrue(r.mapping.keys.contains("[PERSON_1]")); XCTAssertTrue(r.mapping.keys.contains("[PERSON_10]"))
        for n in names { XCTAssertFalse(r.text.contains(n)) }
        XCTAssertEqual(s.restore(r.text, mapping: r.mapping), input)
    }

    func testCSVOmitsContextUnlessAsked() throws {
        let tel = try TelemetryLog(db: SQLiteDB(path: ":memory:"))
        try tel.log(DecisionRecord(id: nil, timestamp: Date(timeIntervalSince1970: 0), decisionType: .sensitivity, chosenID: "sensitive",
                                   confidence: 0.95, escalated: false, latencyMs: 3, model: "m", agreedWithTeacher: nil, source: "test",
                                   context: "User: my LDL is 210", optionIDs: ["ok", "sensitive"]))
        let plain = try tel.csv()
        XCTAssertFalse(plain.contains("LDL")); XCTAssertFalse(plain.contains(",context,"))
        XCTAssertTrue(plain.hasSuffix("\"ok|sensitive\"\n"))
        let full = try tel.csv(includeContext: true)
        XCTAssertTrue(full.contains(",context,option_ids\n")); XCTAssertTrue(full.contains("\"User: my LDL is 210\",\"ok|sensitive\""))
    }
}

final class ReviewMemoryTests: XCTestCase {
    func testPurgeExpiredAndBudgetEvictionOrder() async throws {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let m = try MemoryStore(db: SQLiteDB(path: ":memory:"), clock: { now })
        try await m.upsert(.init(subject: "user", attribute: "needs_to_buy", value: "milk", text: "User needs to buy milk", ttl: 60))
        now += 1
        try await m.upsert(.init(subject: "user", attribute: "likes", value: "tea", text: "User likes tea", provenance: MemoryProvenance.cloud))
        now += 1
        try await m.upsert(.init(subject: "user", attribute: "likes", value: "jazz", text: "User likes jazz", provenance: MemoryProvenance.cloud))
        now += 1
        try await m.upsert(.init(subject: "user", attribute: "diet", value: "vegan", text: "User is vegan"))
        now += 120                                                    // milk expired
        XCTAssertEqual(try m.purgeExpired(), 1); XCTAssertEqual(try m.purgeExpired(), 0)
        m.budget = 2
        let evicted = try m.enforceBudget()                           // least trusted (cloud) first, older first: tea
        XCTAssertEqual(evicted.count, 1)
        XCTAssertEqual(try m.active().map(\.value).sorted(), ["jazz", "vegan"])
    }
}

final class ReviewScrubberPatternTests: XCTestCase {
    func testSSNAndInternationalPhoneAreMasked() {
        let s = PrivacyScrubber()
        let input = "My SSN is 123-45-6789 and my London number is +44 20 7946 0958, US one 415-555-0134."
        let r = s.scrub(input)
        XCTAssertFalse(r.text.contains("6789")); XCTAssertFalse(r.text.contains("7946")); XCTAssertFalse(r.text.contains("0134"))
        XCTAssertTrue(r.text.contains("[SSN_1]")); XCTAssertTrue(r.text.contains("[PHONE_1]")); XCTAssertTrue(r.text.contains("[PHONE_2]"))
        XCTAssertEqual(s.restore(r.text, mapping: r.mapping), input)
        // Plain numbers in prose stay readable.
        XCTAssertEqual(s.scrub("I ran 5 km in 27 minutes in 2026").text, "I ran 5 km in 27 minutes in 2026")
    }
}
