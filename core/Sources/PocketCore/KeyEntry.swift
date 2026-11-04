import Foundation

public enum SecretPresence: Equatable, Sendable { case saved, absent, unavailable(Int32) }

/// Storage behind the API-key fields. `replace` must leave any existing secret untouched when it fails.
public protocol SecretStoring {
    func presence(_ account: String) -> SecretPresence
    func replace(_ value: String, account: String) -> Int32
    /// 0 when the secret is gone afterwards, including when none was saved.
    func remove(_ account: String) -> Int32
}

public enum KeyOutcome: Equatable, Sendable {
    case nothingEntered
    case malformed
    case saved(replacedPrevious: Bool)
    case failed(code: Int32, previous: SecretPresence)
}

public enum KeyRemoval: Equatable, Sendable {
    case removed(hadKey: Bool)
    case failed(code: Int32)
}

/// Replace-or-remove decisions for the Settings key fields. Messages never include the entered value or any
/// text from the system beyond a numeric status.
public enum KeyEntry {
    public static func commit(entered: String, account: String, store: SecretStoring) -> KeyOutcome {
        let key = entered.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return .nothingEntered }
        guard !key.contains(where: { $0.isWhitespace || $0.isNewline }) else { return .malformed }
        let previous = store.presence(account)
        let code = store.replace(key, account: account)
        return code == 0 ? .saved(replacedPrevious: previous == .saved) : .failed(code: code, previous: previous)
    }

    public static func remove(account: String, store: SecretStoring) -> KeyRemoval {
        let had = store.presence(account) == .saved
        let code = store.remove(account)
        return code == 0 ? .removed(hadKey: had) : .failed(code: code)
    }

    public static func message(_ outcome: KeyOutcome, label: String) -> String? {
        switch outcome {
        case .nothingEntered: return nil
        case .malformed: return "The \(label) key has spaces or line breaks inside it. Paste only the key. Nothing was changed."
        case .saved(let replaced): return replaced ? "\(label) key replaced." : "\(label) key saved."
        case .failed(let code, let previous):
            let tail: String
            switch previous {
            case .saved: tail = "The previous key is unchanged."
            case .absent: tail = "No key is saved."
            case .unavailable: tail = "OffLlama could not confirm whether a key is saved."
            }
            return "Could not save the \(label) key (Keychain status \(code)). \(tail)"
        }
    }

    public static func message(_ removal: KeyRemoval, label: String) -> String {
        switch removal {
        case .removed(let had): return had ? "\(label) key removed." : "No \(label) key was saved."
        case .failed(let code): return "Could not remove the \(label) key (Keychain status \(code)). It may still be saved."
        }
    }
}
