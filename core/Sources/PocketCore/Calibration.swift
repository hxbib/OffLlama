import Foundation

/// Temperature-calibrated softmax over option-letter logits.
public enum Calibration {
    public static func softmax(_ logits: [Double], temperature T: Double = 1.0) -> [Double] {
        guard !logits.isEmpty else { return [] }
        let t = max(T, 1e-6)
        let m = logits.max()!
        let e = logits.map { exp(($0 - m) / t) }
        let s = e.reduce(0, +)
        return e.map { $0 / s }
    }

    /// Negative log-likelihood of labels under temperature T (for fitting).
    public static func nll(_ samples: [(logits: [Double], label: Int)], temperature T: Double) -> Double {
        guard !samples.isEmpty else { return 0 }
        var total = 0.0
        for s in samples { total -= log(max(softmax(s.logits, temperature: T)[s.label], 1e-12)) }
        return total / Double(samples.count)
    }

    /// Fit a single temperature by golden-section search on held-out NLL (Guo et al. 2017).
    public static func fitTemperature(_ samples: [(logits: [Double], label: Int)], lo: Double = 0.05, hi: Double = 10) -> Double {
        var a = lo, b = hi
        let g = (sqrt(5.0) - 1) / 2
        var c = b - g * (b - a), d = a + g * (b - a)
        for _ in 0..<80 {
            if nll(samples, temperature: c) < nll(samples, temperature: d) { b = d } else { a = c }
            c = b - g * (b - a); d = a + g * (b - a)
        }
        return (a + b) / 2
    }

    /// Expected calibration error with equal-width bins.
    public static func ece(confidences: [Double], correct: [Bool], bins: Int = 10) -> Double {
        precondition(confidences.count == correct.count)
        guard !confidences.isEmpty else { return 0 }
        var err = 0.0
        for b in 0..<bins {
            let lo = Double(b) / Double(bins), hi = Double(b + 1) / Double(bins)
            let idx = confidences.indices.filter { confidences[$0] > lo && confidences[$0] <= hi || (b == 0 && confidences[$0] == 0) }
            guard !idx.isEmpty else { continue }
            let acc = Double(idx.filter { correct[$0] }.count) / Double(idx.count)
            let conf = idx.map { confidences[$0] }.reduce(0, +) / Double(idx.count)
            err += Double(idx.count) / Double(confidences.count) * abs(acc - conf)
        }
        return err
    }

    /// Smallest tau whose accepted (confidence >= tau) decisions reach `targetAccuracy`.
    /// Returns nil if no threshold achieves it. Lower tau = more decisions handled locally.
    public static func selectTau(confidences: [Double], correct: [Bool], targetAccuracy: Double, minCoverage: Double = 0.0) -> Double? {
        let candidates = Array(Set(confidences)).sorted()
        for tau in candidates {
            let acc = confidences.indices.filter { confidences[$0] >= tau }
            guard !acc.isEmpty, Double(acc.count) / Double(confidences.count) >= minCoverage else { continue }
            let a = Double(acc.filter { correct[$0] }.count) / Double(acc.count)
            if a >= targetAccuracy { return tau }
        }
        return nil
    }
}

/// Per-decision-type temperature + threshold. Loaded from training/out/calibration.json when available.
public struct CalibrationProfile: Codable, Sendable {
    public var temperature: [String: Double]
    public var tau: [String: Double]
    public var defaultTau: Double

    public init(temperature: [String: Double] = [:], tau: [String: Double] = [:], defaultTau: Double = 0.8) {
        self.temperature = temperature; self.tau = tau; self.defaultTau = defaultTau
    }
    public static let uncalibrated = CalibrationProfile()

    public func temperature(for t: DecisionType) -> Double { temperature[t.rawValue] ?? 1.0 }
    public func tau(for t: DecisionType) -> Double { tau[t.rawValue] ?? defaultTau }

    public static func load(from url: URL) throws -> CalibrationProfile {
        try JSONDecoder().decode(CalibrationProfile.self, from: Data(contentsOf: url))
    }
}
