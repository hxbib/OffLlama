import Foundation
import Security
import PocketCore

/// Generic-password items keyed by account. Callers get statuses, never a reason to log the value.
enum Keychain {
    /// Replaces the stored value. An existing item is only ever updated in place, so a failed write leaves the old key.
    @discardableResult
    static func set(_ value: String, for key: String) -> OSStatus {
        guard !value.isEmpty else { return errSecParam }
        let query = baseQuery(key)
        let data = Data(value.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else { return status }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
        return status
    }

    @discardableResult
    static func remove(_ key: String) -> OSStatus {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }

    /// Existence check that never reads the secret.
    static func presence(_ key: String) -> SecretPresence {
        var q = baseQuery(key)
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        switch SecItemCopyMatching(q as CFDictionary, nil) {
        case errSecSuccess: return .saved
        case errSecItemNotFound: return .absent
        case let other: return .unavailable(other)
        }
    }

    static func get(_ key: String) -> String? {
        var q = baseQuery(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    private static func baseQuery(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
    }
}

struct KeychainStore: SecretStoring {
    func presence(_ account: String) -> SecretPresence { Keychain.presence(account) }
    func replace(_ value: String, account: String) -> Int32 { Keychain.set(value, for: account) }
    func remove(_ account: String) -> Int32 {
        let status = Keychain.remove(account)
        return status == errSecItemNotFound ? errSecSuccess : status
    }
}
