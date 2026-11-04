import Foundation

/// Conformal risk control for the Reflex escalation threshold tau.
///
/// Goal (Conformal Cascade, arXiv 2607.25018; CR2, arXiv 2605.12001): choose tau so that the
/// selective risk  R(tau) = P(wrong | confidence >= tau)  is <= alpha with probability >= 1 - delta
/// over the draw of the calibration set (exchangeable calibration/test data assumed).
///
/// Bound used: Learn-Then-Test (Angelopoulos, Bates, Candès, Jordan, Lei 2021, arXiv 2110.01052) with
/// Bonferroni FWER control over a FIXED grid of K candidate taus (chosen before seeing data; default 0.01..0.99).
/// For each tau we test H0: R(tau) > alpha with the exact binomial tail p-value  p = P(Bin(n_tau, alpha) <= k_tau)
/// (k_tau = errors among the n_tau accepted rows; equivalent to the one-sided Clopper-Pearson upper bound at level
/// 1 - delta/K being <= alpha). Every tau with p <= delta/K is certified; we return the smallest (max coverage).
/// FWER <= delta, so the returned tau has R(tau) <= alpha w.p. >= 1 - delta.
/// (Fixed-sequence testing high->low avoids the 1/K penalty but stalls at the top of the grid where n_tau is tiny,
/// so Bonferroni is the practical choice here.)
/// Conditioning on n_tau: the binomial test is applied conditionally on the number of accepted rows, as in LTT's
/// selective-risk (conditional) variant. If no tau passes, returns nil => escalate everything (tau = +inf).
public enum ConformalRisk {
    public struct Result: Codable, Sendable, Equatable {
        public let tau: Double?          // nil => no threshold certifiable; escalate all
        public let alpha: Double
        public let delta: Double
        public let n: Int                // calibration rows
        public let handled: Int          // rows with conf >= tau
        public let errors: Int           // wrong among handled
        public let handledShare: Double
        public let empiricalError: Double?
        public let errorUpperBound: Double? // Clopper-Pearson (1 - delta/K) upper bound on R(tau)
        public let pValue: Double?
    }

    /// log C(n,k)
    static func logChoose(_ n: Int, _ k: Int) -> Double { lgamma(Double(n + 1)) - lgamma(Double(k + 1)) - lgamma(Double(n - k + 1)) }

    /// P(Bin(n, p) <= k), exact.
    public static func binomCDF(_ k: Int, _ n: Int, _ p: Double) -> Double {
        if k < 0 { return 0 }; if k >= n { return 1 }
        if p <= 0 { return 1 }; if p >= 1 { return 0 }
        var s = 0.0
        for i in 0...k { s += exp(logChoose(n, i) + Double(i) * log(p) + Double(n - i) * log1p(-p)) }
        return min(1, s)
    }

    /// One-sided Clopper-Pearson upper confidence bound at level 1 - delta for k errors in n trials.
    public static func clopperPearsonUpper(_ k: Int, _ n: Int, delta: Double) -> Double {
        if n == 0 { return 1 }; if k >= n { return 1 }
        var lo = Double(k) / Double(n), hi = 1.0
        for _ in 0..<100 { let m = (lo + hi) / 2; if binomCDF(k, n, m) > delta { lo = m } else { hi = m } }
        return hi
    }

    public static let defaultGrid: [Double] = (1...99).map { Double($0) / 100 }

    public static func calibrate(confidences: [Double], correct: [Bool], alpha: Double = 0.05, delta: Double = 0.1,
                                 grid: [Double] = defaultGrid) -> Result {
        precondition(confidences.count == correct.count)
        let n = confidences.count
        let level = delta / Double(max(grid.count, 1))
        var best: (tau: Double, h: Int, e: Int, p: Double)? = nil
        for tau in grid.sorted() {
            let idx = confidences.indices.filter { confidences[$0] >= tau }
            guard !idx.isEmpty else { continue }
            let e = idx.filter { !correct[$0] }.count
            let p = binomCDF(e, idx.count, alpha)
            if p <= level { best = (tau, idx.count, e, p); break }
        }
        guard let b = best else {
            return Result(tau: nil, alpha: alpha, delta: delta, n: n, handled: 0, errors: 0, handledShare: 0,
                          empiricalError: nil, errorUpperBound: nil, pValue: nil)
        }
        return Result(tau: b.tau, alpha: alpha, delta: delta, n: n, handled: b.h, errors: b.e,
                      handledShare: n == 0 ? 0 : Double(b.h) / Double(n), empiricalError: Double(b.e) / Double(b.h),
                      errorUpperBound: clopperPearsonUpper(b.e, b.h, delta: level), pValue: b.p)
    }

    public struct Bound: Codable, Sendable, Equatable {
        public let tau: Double, handled: Int, errors: Int, handledShare: Double, errorUpperBound: Double, delta: Double
    }

    /// Tightest error bound the sample supports, without a target alpha: for every grid tau the Clopper-Pearson
    /// upper bound at delta/K (Bonferroni => all K bounds hold simultaneously w.p. >= 1 - delta), and the tau with the
    /// smallest one. Reads as "error among self-handled <= X at confidence 1 - delta". It tightens as more rows are
    /// handled locally. Assumes calibration and future decisions are exchangeable.
    public static func tightestBound(confidences: [Double], correct: [Bool], delta: Double = 0.1, grid: [Double] = defaultGrid) -> Bound? {
        let level = delta / Double(max(grid.count, 1)); let n = confidences.count
        var best: Bound? = nil
        for tau in grid.sorted() {
            let idx = confidences.indices.filter { confidences[$0] >= tau }
            guard !idx.isEmpty else { continue }
            let e = idx.filter { !correct[$0] }.count
            let u = clopperPearsonUpper(e, idx.count, delta: level)
            if best == nil || u < best!.errorUpperBound {
                best = Bound(tau: tau, handled: idx.count, errors: e, handledShare: Double(idx.count) / Double(n), errorUpperBound: u, delta: delta)
            }
        }
        return best
    }

    /// Minimum self-handled rows needed to certify `alpha` if the observed error rate among them is `observedError`
    /// (0 = no errors), at delta with K grid points.
    public static func minRowsNeeded(alpha: Double, delta: Double = 0.1, observedError: Double = 0, k: Int = defaultGrid.count) -> Int? {
        guard observedError < alpha else { return nil }
        let level = delta / Double(max(k, 1))
        var n = 1
        while n <= 1_000_000 {
            if binomCDF(Int((observedError * Double(n)).rounded(.down)), n, alpha) <= level { return n }
            n += n < 1000 ? 1 : 10
        }
        return nil
    }

    /// Minimum accepted rows for a tau to be certifiable with zero errors: (1-alpha)^n <= delta/K.
    /// Note: `k` defaults to 1 here (single pre-chosen tau) but to the 99-point grid in `minRowsNeeded`; pass k: 99 for
    /// the grid-corrected number the docs quote (alpha 0.05, delta 0.1 -> 135 rows; k = 1 -> 45).
    public static func minRowsForZeroErrors(alpha: Double, delta: Double, k: Int = 1) -> Int { Int(ceil(log(delta / Double(k)) / log1p(-alpha))) }
}
