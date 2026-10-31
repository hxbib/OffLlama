import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Talks to llama.cpp's `llama-server` (`/completion`, `n_probs`). Used on Linux/macOS for e2e tests
/// against real Meta models; never shipped in the iOS app (which embeds llama.cpp directly).
public struct LlamaServerEngine: LLMEngine {
    public let baseURL: URL
    public let modelName: String
    public var topK = 40

    public init(baseURL: URL, modelName: String = "llama-server") { self.baseURL = baseURL; self.modelName = modelName }

    struct TopProb: Decodable { let token: String; let logprob: Double }
    struct Prob: Decodable { let top_logprobs: [TopProb]? }
    struct Resp: Decodable { let content: String; let completion_probabilities: [Prob]? }

    private func post(_ body: [String: Any]) async throws -> Resp {
        var req = URLRequest(url: baseURL.appendingPathComponent("completion"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 120
        let (data, _) = try await URLSession.shared.data(for: req)
        do { return try JSONDecoder().decode(Resp.self, from: data) }
        catch { throw LLMError.badResponse(String(decoding: data.prefix(300), as: UTF8.self)) }
    }

    public func nextTokenLogits(prompt: String, candidates: [String]) async throws -> [String: Double] {
        let r = try await post(["prompt": prompt, "n_predict": 1, "n_probs": topK, "temperature": 0,
                                "post_sampling_probs": false, "cache_prompt": true])
        guard let top = r.completion_probabilities?.first?.top_logprobs else { throw LLMError.badResponse("no probs") }
        // " A" and "A" are different tokens; merge with log-sum-exp.
        var out: [String: Double] = [:]
        for t in top {
            let k = t.token.trimmingCharacters(in: .whitespaces)
            guard candidates.contains(k) else { continue }
            if let prev = out[k] { let m = max(prev, t.logprob); out[k] = m + log(exp(prev - m) + exp(t.logprob - m)) }
            else { out[k] = t.logprob }
        }
        if out.isEmpty { throw LLMError.noCandidateTokens }
        return out
    }

    public func generate(prompt: String, maxTokens: Int, temperature: Double) async throws -> String {
        try await post(["prompt": prompt, "n_predict": maxTokens, "temperature": temperature, "cache_prompt": true]).content
    }
}
