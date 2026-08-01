import Foundation

public enum AppGroup {
    public static let identifier = "group.piszeprogramy.openWhisper"

    public static let keyboardLastUsedKey = "keyboardLastUsedAt"

    public static let cloudApiKeyKey = "settings.cloudApiKey"
    public static let keyboardDictationEnabledKey = "settings.keyboardDictationEnabled"
    public static let languageCodeKey = "settings.languageCode"

    public static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("OpenWhisper", isDirectory: true)
    }
}
