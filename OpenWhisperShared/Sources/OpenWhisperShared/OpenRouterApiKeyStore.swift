import Foundation

/// Stores the user-supplied OpenRouter API key in the Keychain (BYOK model).
/// Migrates the legacy plaintext UserDefaults/App Group value on first read so
/// existing installs keep working after the upgrade.
public enum OpenRouterApiKeyStore {
    private static let account = "openrouter.apiKey"

    /// Current key, or "" when not set.
    public static var value: String {
        if let stored = KeychainStore.string(forAccount: account), !stored.isEmpty {
            return stored
        }
        // One-time migration of the legacy plaintext storage.
        let legacy = legacyValue()
        if !legacy.isEmpty {
            set(legacy)
            UserDefaults.standard.removeObject(forKey: AppGroup.cloudApiKeyKey)
            UserDefaults(suiteName: AppGroup.identifier)?.removeObject(forKey: AppGroup.cloudApiKeyKey)
            return legacy
        }
        return ""
    }

    public static var hasValue: Bool {
        !value.isEmpty
    }

    /// Stores a new key (empty deletes it).
    public static func set(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        KeychainStore.set(trimmed, account: account)
    }

    private static func legacyValue() -> String {
        let standard = UserDefaults.standard.string(forKey: AppGroup.cloudApiKeyKey)
            ?? ""
        let group = UserDefaults(suiteName: AppGroup.identifier)?.string(forKey: AppGroup.cloudApiKeyKey)
            ?? ""
        return (standard.isEmpty ? group : standard).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
