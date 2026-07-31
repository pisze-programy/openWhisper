import Foundation

public enum AppGroup {
    public static let identifier = "group.piszeprogramy.openWhisper"

    public static let keyboardLastUsedKey = "keyboardLastUsedAt"

    public static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("OpenWhisper", isDirectory: true)
    }
}
