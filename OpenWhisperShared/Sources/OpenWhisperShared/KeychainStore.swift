import Foundation
import Security

/// Minimal Keychain wrapper for storing small secrets (API keys, stable
/// per-install identifiers). Uses the app's default keychain access group.
///
/// Reads are cached in memory after the first successful access so the
/// keychain is touched at most once per account per process lifetime. This
/// matters on macOS: every `SecItemCopyMatching` on a secret the app cannot
/// auto-authorize (e.g. an entry created under a different signing identity)
/// pops a Keychain prompt — caching collapses N prompts into one. `set` and
/// `delete` invalidate the cache for that account.
public enum KeychainStore {
    private static let service = Bundle.main.bundleIdentifier ?? "pl.piszeprogramy.openwhisper"

    /// In-memory value cache keyed by account. Populated lazily on the first
    /// read, invalidated on every write/delete.
    private static var cache: [String: String?] = [:]
    private static let cacheLock = NSLock()

    /// Stores `value` under `account`. Returns false on failure. An empty value
    /// deletes the entry.
    @discardableResult
    public static func set(_ value: String, account: String) -> Bool {
        if value.isEmpty {
            return delete(account: account)
        }
        guard let data = value.data(using: .utf8) else { return false }
        let removed = delete(account: account)

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
        let added = SecItemAdd(query as CFDictionary, nil) == errSecSuccess
        if added {
            cacheLock.lock()
            cache[account] = value
            cacheLock.unlock()
        }
        return added || removed
    }

    /// Reads the stored value for `account`, or nil when absent. Cached after
    /// the first read; `set`/`delete` clear the cache entry.
    public static func string(forAccount account: String) -> String? {
        cacheLock.lock()
        if let cached = cache[account] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        let value: String?
        if status == errSecSuccess, let data = item as? Data {
            value = String(data: data, encoding: .utf8)
        } else {
            value = nil
        }

        cacheLock.lock()
        cache[account] = value
        cacheLock.unlock()
        return value
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
        let deleted = SecItemDelete(query as CFDictionary) == errSecSuccess

        cacheLock.lock()
        cache[account] = nil
        cacheLock.unlock()
        return deleted
    }
}
