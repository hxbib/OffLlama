import Foundation

/// The on-device model runtime. On iPhone this is llama.cpp (see app/PocketGlimmer/Engine/LlamaCppEngine.swift);
/// on Linux/macOS dev boxes it is a llama-server HTTP endpoint; in tests it is a scripted double.
public protocol LLMEngine: Sendable {
    var modelName: String { get }
    /// One forward pass on `prompt`; return the raw logit (or log-prob) of each requested next token.
    /// Tokens missing from the engine's top-k must be omitted, never invented.
    func nextTokenLogits(prompt: String, candidates: [String]) async throws -> [String: Double]
    /// Free-text generation for System 2 local answers.
    func generate(prompt: String, maxTokens: Int, temperature: Double) async throws -> String
}

public enum LLMError: Error, Equatable {
    case noCandidateTokens
    case badResponse(String)
}

/// Deterministic test double: returns scripted logits per decision type (matched by question text).
public final class ScriptedEngine: LLMEngine, @unchecked Sendable {
    public let modelName = "scripted"
    private let lock = NSLock()
    private var scripts: [(match: String, logits: [String: Double])] = []
    public var generated = "OK"
    public private(set) var calls = 0

    public init() {}
    public func script(whenPromptContains s: String, logits: [String: Double]) {
        lock.lock(); defer { lock.unlock() }; scripts.append((s, logits))
    }
    public func nextTokenLogits(prompt: String, candidates: [String]) async throws -> [String: Double] {
        lookup(prompt, candidates)
    }
    private func lookup(_ prompt: String, _ candidates: [String]) -> [String: Double] {
        lock.lock(); defer { lock.unlock() }
        calls += 1
        for s in scripts.reversed() where prompt.contains(s.match) {
            return s.logits.filter { candidates.contains($0.key) }
        }
        return Dictionary(uniqueKeysWithValues: candidates.map { ($0, 0.0) }) // uniform = low confidence
    }
    public func generate(prompt: String, maxTokens: Int, temperature: Double) async throws -> String { generated }
}
