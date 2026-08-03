import Foundation

/// Stable identifier sent to OpenRouter as `session_id` so all requests from
/// one user can be grouped for cost and usage tracking.
///
/// The value is stored in iCloud Key-Value Store (syncs across a user's Apple
/// devices, no login required) and mirrored into the local App Group defaults.
/// When iCloud is unavailable, a per-install UUID is used as a fallback and
/// promoted to iCloud once it becomes reachable.
public enum DeviceSessionID {
    private static let storageKey = "openwhisper.deviceSessionID"

    /// The stable session identifier for this user (Apple-ID scoped when iCloud
    /// is available, per-install UUID otherwise).
    public static var value: String {
        if let synced = readSyncValue(), !synced.isEmpty {
            persistLocally(synced)
            return synced
        }
        if let local = readLocalValue(), !local.isEmpty {
            writeSyncValue(local)
            return local
        }
        let fresh = UUID().uuidString
        persistLocally(fresh)
        writeSyncValue(fresh)
        return fresh
    }

    // MARK: - Local (App Group) storage

    private static var localDefaults: UserDefaults? {
        UserDefaults(suiteName: AppGroup.identifier)
    }

    private static func readLocalValue() -> String? {
        localDefaults?.string(forKey: storageKey)
            ?? UserDefaults.standard.string(forKey: storageKey)
    }

    private static func persistLocally(_ value: String) {
        localDefaults?.set(value, forKey: storageKey)
        UserDefaults.standard.set(value, forKey: storageKey)
    }

    // MARK: - iCloud Key-Value Store

    private static func readSyncValue() -> String? {
        NSUbiquitousKeyValueStore.default.string(forKey: storageKey)
    }

    private static func writeSyncValue(_ value: String) {
        NSUbiquitousKeyValueStore.default.set(value, forKey: storageKey)
        NSUbiquitousKeyValueStore.default.synchronize()
    }
}
