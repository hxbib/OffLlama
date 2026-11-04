import Foundation

public struct CloudRouteStatus: Equatable, Sendable {
    public enum State: Equatable, Sendable { case notConfigured, needsKey, enabled, refused }
    public let state: State
    public let detail: String
    public var isEnabled: Bool { state == .enabled }
}

/// Settings-time view of what `CloudSettings.chain()` will accept, asked of the same validators the request path uses
/// (`MetaAPI.requireStandardMode`, `OpenAICompatibleBrain.validConfiguration`). The validator only tests that a key is
/// non-empty, so a fixed stand-in is passed and the real key never leaves Keychain for a status line.
public enum CloudSettingsCheck {
    private static let keyStandIn = "saved-in-keychain"

    public static func meta(model: String, keySaved: Bool) -> CloudRouteStatus {
        let id = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return .init(state: .refused, detail: "Enter a Meta model id, such as muse-spark-1.3.") }
        do { try MetaAPI.requireStandardMode(id) } catch {
            return .init(state: .refused, detail: "Contributor-mode models are refused before any request leaves the phone. Use a Standard-mode model id.")
        }
        guard OpenAICompatibleBrain.validConfiguration(model: id, baseURL: MetaAPI.baseURL, apiKey: keyStandIn) else {
            return .init(state: .refused, detail: "That model id is not usable.")
        }
        return keySaved ? .init(state: .enabled, detail: "Meta Model API is enabled for hard requests when online.")
                        : .init(state: .needsKey, detail: "The model id is valid. Add a key to enable it.")
    }

    public static func custom(baseURL: String, model: String, keySaved: Bool) -> CloudRouteStatus {
        let urlText = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if urlText.isEmpty && id.isEmpty && !keySaved { return .init(state: .notConfigured, detail: "Not configured.") }
        guard let url = URL(string: urlText),
              OpenAICompatibleBrain.validConfiguration(model: id.isEmpty ? "-" : id, baseURL: url, apiKey: keyStandIn) else {
            return .init(state: .refused, detail: "The base URL must be a complete http or https link with a host and no username, password, query or fragment.")
        }
        guard !id.isEmpty else { return .init(state: .refused, detail: "Enter the model id this endpoint serves.") }
        do { try MetaAPI.requireStandardMode(id) } catch {
            return .init(state: .refused, detail: "Contributor-mode models are refused before any request leaves the phone.")
        }
        guard keySaved else { return .init(state: .needsKey, detail: "The endpoint is valid. Add a key to enable it.") }
        let plain = url.scheme?.lowercased() == "http" ? " This link uses http, so the key and requests are not encrypted." : ""
        return .init(state: .enabled, detail: "Custom endpoint is enabled as a fallback when online." + plain)
    }
}

/// Standard-mode chat model ids offered as presets in Settings (https://dev.meta.ai/docs/models). Anything else a
/// user types goes through the same validator as a preset; no id is ever substituted for a saved one.
public enum MetaModelPresets {
    public static let all: [(id: String, name: String)] = [
        ("muse-spark-1.3", "Muse Spark 1.3"), ("muse-spark-1.2", "Muse Spark 1.2"),
        ("muse-spark-1.1", "Muse Spark 1.1"), ("muse-wonder-1.0", "Muse Wonder 1.0"),
    ]
    public static func isPreset(_ id: String) -> Bool {
        let t = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return all.contains { $0.id == t }
    }
}
