import Foundation

/// Stable, random identifier for this app install. Kept in the Keychain so it
/// survives app updates and is not restored into plaintext backups. Used only
/// for anonymous usage analytics (install-level, not user identity).
public enum InstallID {
    private static let account = "install.id"

    public static var value: String {
        if let existing = KeychainStore.string(forAccount: account), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString
        KeychainStore.set(fresh, account: account)
        return fresh
    }
}
