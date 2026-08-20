import Foundation

public enum AppGroup {
    /// Bare app group identifier (iOS form; the system prepends the team id).
    public static let identifier = "group.pl.piszeprogramy.openwhisper"

    /// Team-prefixed identifier required on macOS — `containerURL(...)` and
    /// `UserDefaults(suiteName:)` must use this exact form on macOS, otherwise
    /// the sandbox resolves a path the app has no write access to (which made
    /// SwiftData fail to open the history store with error 1).
    public static let macContainerIdentifier = "3UKH2QRFKZ.group.pl.piszeprogramy.openwhisper"

    public static let cloudApiKeyKey = "settings.cloudApiKey"
    public static let languageCodeKey = "settings.languageCode"
    public static let autoStopOnSilenceKey = "settings.autoStopOnSilence"
    public static let autoStopSilenceSecondsKey = "settings.autoStopSilenceSeconds"
    public static let usageAnalyticsEnabledKey = "settings.usageAnalyticsEnabled"

    public static var containerURL: URL {
        // App Group container is team-scoped and stable across app updates and
        // bundle-id changes — unlike the sandbox container or plain
        // Application Support, which reset when the bundle identifier changes.
        #if os(macOS)
        let groupID = macContainerIdentifier
        #else
        let groupID = identifier
        #endif
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("OpenWhisper", isDirectory: true)
    }
}
