import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ChatMessage: Codable, Sendable, Equatable {
    public var role: String; public var content: String
    public init(role: String, content: String) { self.role = role; self.content = content }
}

public struct CloudAnswer: Sendable { public let text: String; public let provider: String; public let model: String; public let latencyMs: Double }

/// System 2 (hard reasoning). Provider-agnostic; Meta models first.
public protocol CloudBrain: Sendable {
    var providerName: String { get }
    var model: String { get }
    func complete(_ messages: [ChatMessage], maxTokens: Int) async throws -> CloudAnswer
}

public enum CloudError: Error, Equatable { case offline, http(Int, String), decode(String), notConfigured }

/// Any OpenAI-compatible /chat/completions endpoint. Covers the Meta Model API's compat endpoint and the hosted
/// open-weights providers (Fireworks, Baseten, Modal vLLM) serving Muse Spark Open / Muse Glimmer.
public struct OpenAICompatibleBrain: CloudBrain {
    public let providerName: String
    public let model: String
    public let baseURL: URL           // ends before /chat/completions
    let apiKey: String
    public var extraHeaders: [String: String] = [:]
    public var transport: @Sendable (URLRequest) async throws -> (Data, Int) = { req in
        let (d, r) = try await URLSession.shared.data(for: req)
        return (d, (r as? HTTPURLResponse)?.statusCode ?? 0)
    }

    public init(providerName: String, model: String, baseURL: URL, apiKey: String) {
        self.providerName = providerName; self.model = model; self.baseURL = baseURL; self.apiKey = apiKey
    }

    struct Resp: Decodable { struct C: Decodable { struct M: Decodable { let content: String? }; let message: M }; let choices: [C] }

    public func makeRequest(_ messages: [ChatMessage], maxTokens: Int) throws -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        for (k, v) in extraHeaders { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "max_tokens": maxTokens,
            "messages": messages.map { ["role": $0.role, "content": $0.content] }] as [String: Any])
        req.timeoutInterval = 60
        return req
    }

    public func complete(_ messages: [ChatMessage], maxTokens: Int = 800) async throws -> CloudAnswer {
        let start = Date()
        let (data, status) = try await transport(try makeRequest(messages, maxTokens: maxTokens))
        guard (200..<300).contains(status) else { throw CloudError.http(status, String(decoding: data.prefix(300), as: UTF8.self)) }
        guard let r = try? JSONDecoder().decode(Resp.self, from: data), let t = r.choices.first?.message.content else {
            throw CloudError.decode(String(decoding: data.prefix(300), as: UTF8.self))
        }
        return CloudAnswer(text: t, provider: providerName, model: model, latencyMs: Date().timeIntervalSince(start) * 1000)
    }
}

/// Provider presets. Model ids / base URLs are configuration (check each provider's dashboard); nothing is hardcoded
/// into the app's logic. Keys live in the iOS Keychain, never in the repo.
public enum CloudPresets {
    /// Meta Model API, OpenAI-compatible. Verified 2026-10-31 at dev.meta.ai/docs/quickstart + /docs/models:
    /// base https://api.meta.ai/v1, `Authorization: Bearer $MODEL_API_KEY`. Model ids: muse-spark-1.3,
    /// muse-spark-1.3-contributor (cheaper, content may train Meta models), muse-wonder-1.0. Glimmer / Spark Open are
    /// NOT hosted here (open weights: self-host or partners).
    public static let metaModels = ["muse-spark-1.3", "muse-wonder-1.0", "muse-spark-1.3-contributor"]
    public static func metaModelAPI(model: String = "muse-spark-1.3", apiKey: String,
                                    baseURL: URL = URL(string: "https://api.meta.ai/v1/")!) -> OpenAICompatibleBrain {
        OpenAICompatibleBrain(providerName: "Meta Model API", model: model, baseURL: baseURL, apiKey: apiKey)
    }
    /// Fireworks: "accounts/fireworks/models/muse-spark-open" (serverless) or "accounts/fireworks/models/muse-glimmer-30b"
    /// (on-demand deployment only; serverless deprecated 2026-09-25). Verified at fireworks.ai/models, 2026-10-31.
    public static func fireworks(model: String, apiKey: String) -> OpenAICompatibleBrain {
        OpenAICompatibleBrain(providerName: "Fireworks", model: model, baseURL: URL(string: "https://api.fireworks.ai/inference/v1/")!, apiKey: apiKey)
    }
    /// Baseten Model APIs (OpenAI-compatible). Spark Open slug "meta-models/muse-spark-open" (baseten.co/library/muse-spark-open).
    public static func baseten(model: String, apiKey: String) -> OpenAICompatibleBrain {
        OpenAICompatibleBrain(providerName: "Baseten", model: model, baseURL: URL(string: "https://inference.baseten.co/v1/")!, apiKey: apiKey)
    }
    /// Self-deployed vLLM on Modal (Dedicated Endpoint): pass the printed URL + "/v1/", served model name "muse-glimmer".
    public static func modal(model: String, baseURL: URL, apiKey: String) -> OpenAICompatibleBrain {
        OpenAICompatibleBrain(providerName: "Modal", model: model, baseURL: baseURL, apiKey: apiKey)
    }
    /// BYOK escape hatch: any OpenAI-compatible endpoint.
    public static func custom(name: String, model: String, baseURL: URL, apiKey: String) -> OpenAICompatibleBrain {
        OpenAICompatibleBrain(providerName: name, model: model, baseURL: baseURL, apiKey: apiKey)
    }
}

/// Tries providers in order (Meta first); reports `offline` if none configured or all unreachable.
public struct CloudBrainChain: Sendable {
    public var brains: [CloudBrain]
    public init(_ brains: [CloudBrain]) { self.brains = brains }
    public func complete(_ m: [ChatMessage], maxTokens: Int = 800) async throws -> CloudAnswer {
        guard !brains.isEmpty else { throw CloudError.notConfigured }
        var last: Error = CloudError.offline
        for b in brains { do { return try await b.complete(m, maxTokens: maxTokens) } catch { last = error } }
        throw last
    }
}
