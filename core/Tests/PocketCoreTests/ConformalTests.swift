import XCTest
@testable import PocketCore

final class ConformalTests: XCTestCase {
    func testBinomCDF() {
        XCTAssertEqual(ConformalRisk.binomCDF(0, 10, 0.5), pow(0.5, 10), accuracy: 1e-12)
        XCTAssertEqual(ConformalRisk.binomCDF(10, 10, 0.3), 1)
        XCTAssertEqual(ConformalRisk.binomCDF(2, 5, 0.5), 0.5, accuracy: 1e-12)
    }
    func testClopperPearsonZeroErrors() {
        // k=0: upper = 1 - delta^(1/n)
        XCTAssertEqual(ConformalRisk.clopperPearsonUpper(0, 100, delta: 0.1), 1 - pow(0.1, 0.01), accuracy: 1e-6)
    }
    func testMinRows() { XCTAssertEqual(ConformalRisk.minRowsForZeroErrors(alpha: 0.05, delta: 0.1), 45); XCTAssertEqual(ConformalRisk.minRowsForZeroErrors(alpha: 0.05, delta: 0.1, k: 99), 135) }
    func testTooFewRowsEscalatesAll() {
        let r = ConformalRisk.calibrate(confidences: Array(repeating: 0.99, count: 20), correct: Array(repeating: true, count: 20))
        XCTAssertNil(r.tau); XCTAssertEqual(r.handledShare, 0)
    }
    func testPicksThresholdAboveNoise() {
        // 200 perfect high-confidence rows, 200 low-confidence rows that are 50% wrong.
        var c: [Double] = [], ok: [Bool] = []
        for i in 0..<200 { c.append(0.9 + Double(i) * 1e-4); ok.append(true) }
        for i in 0..<200 { c.append(0.3 + Double(i) * 1e-3); ok.append(i % 2 == 0) }
        let r = ConformalRisk.calibrate(confidences: c, correct: ok, alpha: 0.05, delta: 0.1)
        XCTAssertNotNil(r.tau)
        XCTAssertGreaterThanOrEqual(r.handled, 200)
        XCTAssertLessThanOrEqual(r.errorUpperBound!, 0.05 + 1e-6)
        XCTAssertLessThan(r.handled, 400)
    }
    func testGuaranteeHoldsInSimulation() {
        // Monte Carlo: test-set selective risk at returned tau exceeds alpha in <= ~delta of trials.
        var rng = SystemRandomNumberGenerator(); var viol = 0; let trials = 200
        func draw(_ n: Int) -> ([Double], [Bool]) {
            var c: [Double] = [], ok: [Bool] = []
            for _ in 0..<n { let x = Double.random(in: 0...1, using: &rng); c.append(x); ok.append(Double.random(in: 0...1, using: &rng) < 0.5 + 0.5 * x) }
            return (c, ok)
        }
        for _ in 0..<trials {
            let (c, ok) = draw(500)
            let r = ConformalRisk.calibrate(confidences: c, correct: ok, alpha: 0.1, delta: 0.1)
            guard let tau = r.tau else { continue }
            // true risk for x~U[tau,1]: P(wrong)=0.5-0.5*mean(x) = 0.5 - 0.25(1+tau)
            if 0.5 - 0.25 * (1 + tau) > 0.1 { viol += 1 }
        }
        XCTAssertLessThanOrEqual(viol, Int(Double(trials) * 0.1) + 10)
    }
    func testSystemOneConfidence() {
        XCTAssertEqual(Calibration.systemOneConfidence([0.25, 0.25, 0.25, 0.25]), 0, accuracy: 1e-12)
        XCTAssertEqual(Calibration.systemOneConfidence([1, 0]), 1, accuracy: 1e-12)
        XCTAssertEqual(Calibration.systemOneConfidence([0.7, 0.2, 0.1]), (0.7 - 1.0/3) / (2.0/3), accuracy: 1e-12)
        XCTAssertEqual(Calibration.systemOneBucket(optionCount: 4), "3_5")
    }
    func testTightestBoundAndMinRows() {
        XCTAssertEqual(ConformalRisk.minRowsNeeded(alpha: 0.05), 135)
        XCTAssertNil(ConformalRisk.minRowsNeeded(alpha: 0.05, observedError: 0.06))
        XCTAssertGreaterThan(ConformalRisk.minRowsNeeded(alpha: 0.05, observedError: 0.02)!, 135)
        let b = ConformalRisk.tightestBound(confidences: Array(repeating: 0.95, count: 36), correct: Array(repeating: true, count: 36))!
        XCTAssertEqual(b.handled, 36)
        XCTAssertEqual(b.errorUpperBound, 1 - pow(0.1 / 99, 1.0 / 36), accuracy: 1e-6)
    }
}
