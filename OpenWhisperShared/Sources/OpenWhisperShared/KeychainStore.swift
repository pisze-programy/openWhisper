import Foundation
import Security

/// Minimal Keychain wrapper for storing small secrets (API keys, stable
/// per-install identifiers). Uses the app's default keychain access group.
///
/// The service name is a fixed, brand-stable string (NOT the bundle
/// identifier) so that an app update or a bundle-id change does not orphan
/// existing secrets — keychain items are per-user, not per-bundle. A one-time
/// migration copies items created under older bundle-id-based services.
///
/// Reads are cached in memory after the first successful access so the
/// keychain is touched at most once per account per process lifetime. This
/// matters on macOS: every `SecItemCopyMatching` on a secret the app cannot
/// auto-authorize (e.g. an entry created under a different signing identity)
/// pops a Keychain prompt — caching collapses N prompts into one. `set` and
/// `delete` invalidate the cache for that account.
public enum KeychainStore {
    /// Stable, brand-fixed service name. Tests may override it to isolate a
    /// test bundle from the real keychain. Changing the override invalidates the
    /// in-memory cache so values never leak between isolated test services.
    static var serviceOverride: String? {
        didSet {
            if oldValue != serviceOverride {
                cacheLock.lock()
                cache.removeAll()
                cacheLock.unlock()
            }
        }
    }

    static var service: String {
        serviceOverride ?? "piszeprogramy.openwhisper.secrets"
    }

    /// Legacy service names used by earlier builds (they keyed on the bundle
    /// identifier, which changed during the `.mac` → `.macos` rename). Items
    /// created there are copied into the stable service once.
    private static let legacyServices = [
        "piszeprogramy.openWhisper.mac",
        "pl.piszeprogramy.openwhisper.mac",
        "pl.piszeprogramy.openwhisper.macos",
    ]

    /// Copies a secret from a legacy service into the stable one, leaving the
    /// original untouched (acts as a backup). Idempotent: a target that already
    /// has a value is never overwritten. Skipped when a test override is active
    /// so unit tests never read the real keychain.
    private static func migrateLegacy(account: String) {
        guard serviceOverride == nil else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var existing: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &existing) == errSecSuccess {
            return
        }
        for legacy in legacyServices where legacy != service {
            let legacyQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: legacy,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var item: CFTypeRef?
            guard SecItemCopyMatching(legacyQuery as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data else { continue }
            var copyQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
            ]
            #if os(macOS)
            copyQuery[kSecAttrSynchronizable as String] = false
            #endif
            SecItemAdd(copyQuery as CFDictionary, nil)
            return
        }
    }

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
        migrateLegacy(account: account)
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

    /// Reads the stored value for `account`, or nil when absent. Successful
    /// reads (including a legitimate "not found") are cached; failed reads
    /// (e.g. `errSecInteractionNotAllowed` while the keychain is still locked
    /// at login) are NOT cached so the next read retries instead of returning a
    /// stale nil forever.
    public static func string(forAccount account: String) -> String? {
        cacheLock.lock()
        if let cached = cache[account] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        migrateLegacy(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        // Only cache when the keychain answered authoritatively. On transient
        // errors (locked keychain, user cancels the prompt, etc.) leave the
        // cache empty so a later read can succeed.
        if status != errSecSuccess && status != errSecItemNotFound {
            return nil
        }

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
