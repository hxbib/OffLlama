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
    public var promptFormat: ((OptionSet, String, PromptStyle) -> String) = { DecisionPrompt.llama3(set: $0, context: $1, style: $2) }
    let clock: () -> Date

    public init(engine: LLMEngine, profile: CalibrationProfile = .uncalibrated, telemetry: TelemetryLog? = nil,
                source: String = "device", clock: @escaping () -> Date = Date.init) {
        self.engine = engine; self.profile = profile; self.telemetry = telemetry; self.source = source; self.clock = clock
    }

    public func decide(_ set: OptionSet, context: String) async throws -> ReflexDecision {
        let letters = set.activeLetters
        let start = DispatchTime.now().uptimeNanoseconds
        let raw = try await engine.nextTokenLogits(prompt: promptFormat(set, context, profile.promptStyle), candidates: letters)
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
        guard !raw.isEmpty else { throw LLMError.noCandidateTokens }
        // Letters outside the engine's top-k get a floor below the weakest seen letter (conservative: lowers confidence
        // less than dropping them would inflate it).
        let floor = (raw.values.min() ?? 0) - 2.0
        var logits = letters.map { raw[$0] ?? floor }
        if let pr = profile.prior[DecisionPrompt.priorKey(set)], pr.count == logits.count {
            logits = zip(logits, pr).map { $0 - $1 }     // contextual calibration
        }
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
                                                   model: engine.modelName, agreedWithTeacher: nil, source: source,
                                                   context: context, optionIDs: set.options.map(\.id), probabilities: probs))
        return ReflexDecision(type: set.type, chosen: chosen, argmax: argmax, probabilities: probs, confidence: conf,
                              tau: tau, escalated: escalated, latencyMs: ms, telemetryID: id)
    }
}

extension Reflex {
    /// Measure content-free priors for every static set and dynamic sets with 2...8 options (one pass per CF input).
    public func measurePriors() async throws -> [String: [Double]] {
        var sets = OptionSets.staticSets
        for n in 1...7 {
            let names = (1...n).map { "Person \($0)" }
            sets.append(OptionSets.contactPick(candidates: names)); sets.append(OptionSets.eventPick(candidates: names))
        }
        var out: [String: [Double]] = [:]
        for set in sets {
            let L = set.activeLetters
            var acc = [Double](repeating: 0, count: L.count)
            for cf in DecisionPrompt.contentFree {
                let raw = try await engine.nextTokenLogits(prompt: promptFormat(set, cf, profile.promptStyle), candidates: L)
                let floor = (raw.values.min() ?? 0) - 2
                let p = Calibration.softmax(L.map { raw[$0] ?? floor })
                for i in acc.indices { acc[i] += p[i] / Double(DecisionPrompt.contentFree.count) }
            }
            out[DecisionPrompt.priorKey(set)] = acc.map { log(max($0, 1e-9)) }
        }
        return out
    }
}
