import Foundation

public struct ReflexDecision: Sendable {
    public let type: DecisionType
    public let chosen: DecisionOption        // after threshold (fallback if escalated)
    public let argmax: DecisionOption        // model's raw top choice
    public let probabilities: [String: Double] // option id -> calibrated probability
    public let confidence: Double
    public let tau: Double
    public let escalated: Bool
    public let latencyMs: Double
    public let telemetryID: Int64?
}

/// System 1. One forward pass per decision; letters' logits -> temperature softmax -> confidence vs tau.
public final class Reflex: @unchecked Sendable {
    public let engine: LLMEngine
    public var profile: CalibrationProfile
    public let telemetry: TelemetryLog?
    public let source: String
    public var promptFormat: (OptionSet, String) -> String = DecisionPrompt.llama3
    let clock: () -> Date

    public init(engine: LLMEngine, profile: CalibrationProfile = .uncalibrated, telemetry: TelemetryLog? = nil,
                source: String = "device", clock: @escaping () -> Date = Date.init) {
        self.engine = engine; self.profile = profile; self.telemetry = telemetry; self.source = source; self.clock = clock
    }

    public func decide(_ set: OptionSet, context: String) async throws -> ReflexDecision {
        let letters = set.activeLetters
        let start = DispatchTime.now().uptimeNanoseconds
        let raw = try await engine.nextTokenLogits(prompt: promptFormat(set, context), candidates: letters)
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
        guard !raw.isEmpty else { throw LLMError.noCandidateTokens }
        // Letters outside the engine's top-k get a floor below the weakest seen letter (conservative: lowers confidence
        // less than dropping them would inflate it).
        let floor = (raw.values.min() ?? 0) - 2.0
        let logits = letters.map { raw[$0] ?? floor }
        let p = Calibration.softmax(logits, temperature: profile.temperature(for: set.type))
        let best = p.indices.max { p[$0] < p[$1] }!
        let conf = p[best]
        let tau = profile.tau(for: set.type)
        let escalated = conf < tau
        let argmax = set.options[best]
        let chosen = escalated ? set.options.first { $0.id == set.fallbackID }! : argmax
        var probs: [String: Double] = [:]
        for (i, o) in set.options.enumerated() { probs[o.id] = p[i] }
        let id = try telemetry?.log(DecisionRecord(id: nil, timestamp: clock(), decisionType: set.type, chosenID: argmax.id,
                                                   confidence: conf, escalated: escalated, latencyMs: ms,
                                                   model: engine.modelName, agreedWithTeacher: nil, source: source))
        return ReflexDecision(type: set.type, chosen: chosen, argmax: argmax, probabilities: probs, confidence: conf,
                              tau: tau, escalated: escalated, latencyMs: ms, telemetryID: id)
    }
}
