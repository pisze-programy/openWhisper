import Foundation
import Security

/// Minimal Keychain wrapper for storing small secrets (API keys, stable
/// per-install identifiers). Uses the app's default keychain access group.
public enum KeychainStore {
    private static let service = Bundle.main.bundleIdentifier ?? "piszeprogramy.openWhisper"

    /// Stores `value` under `account`. Returns false on failure. An empty value
    /// deletes the entry.
    @discardableResult
    public static func set(_ value: String, account: String) -> Bool {
        if value.isEmpty {
            return delete(account: account)
        }
        guard let data = value.data(using: .utf8) else { return false }
        delete(account: account)

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        #if os(macOS)
        query[kSecAttrSynchronizable as String] = false
        #endif
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    /// Reads the stored value for `account`, or nil when absent.
    public static func string(forAccount account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Deletes the stored value for `account`. Returns false when nothing was
    /// removed (including when it did not exist).
    @discardableResult
    public static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}
