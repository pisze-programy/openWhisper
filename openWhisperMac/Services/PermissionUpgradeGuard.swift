import AppKit
import Foundation

/// macOS can silently drop the Accessibility grant for an app that is re-signed
/// or re-bundled between releases. On version change the stale grant is reset
/// and re-prompted, so the global hotkey never fails silently after an update.
@MainActor
enum PermissionUpgradeGuard {
    private static var versionFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenWhisper/last-launched-version")
    }

    static func resetAccessibilityIfUpgraded() {
        let previous = (try? String(contentsOf: versionFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"

        try? FileManager.default.createDirectory(
            at: versionFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? current.write(to: versionFile, atomically: true, encoding: .utf8)

        guard let previous, previous != current, let bundleID = Bundle.main.bundleIdentifier else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleID]
        try? process.run()
        process.waitUntilExit()

        let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
