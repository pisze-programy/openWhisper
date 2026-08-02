import Foundation

/// Resolves the output format for auto-paste based on the target application.
/// Rich-text editors get formatted paste; code editors and terminals get plain
/// text; browsers resolve by URL host.
enum OutputFormatResolver {
    static let automatic = "auto"

    private static let browserBundleIDs: Set<String> = [
        "com.apple.Safari",
        "company.thebrowser.Browser",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi",
        "org.chromium.Chromium",
        "org.mozilla.firefox",
    ]

    private static let nativeAppFormats: [String: String] = [
        // Rich-text document apps
        "com.apple.iWork.Pages": "rtf",
        "com.microsoft.Word": "rtf",
        "com.apple.TextEdit": "rtf",
        // Markdown apps
        "md.obsidian": "markdown",
        "notion.id": "markdown",
        "com.github.marktext": "markdown",
        "com.typora.Typora": "markdown",
        "com.bear.Bear": "markdown",
        "com.ulyssesapp.mac": "markdown",
        // HTML / mail
        "com.apple.mail": "html",
        "com.microsoft.Outlook": "html",
        // Code editors and terminals
        "com.apple.dt.Xcode": "code",
        "com.microsoft.VSCode": "code",
        "com.todesktop.230313mzl4w4u92": "code",
        "dev.zed.Zed": "code",
        "com.sublimetext.4": "code",
        "com.jetbrains.intellij": "code",
        "com.googlecode.iterm2": "code",
        "com.apple.Terminal": "code",
    ]

    /// Resolves the effective format. `storedFormat` may be `.automatic`; when
    /// nil or plain, no conversion happens.
    static func resolvedFormat(storedFormat: String?, bundleIdentifier: String?, url: String? = nil) -> String? {
        guard let stored = normalized(storedFormat) else { return nil }
        if stored != automatic { return stored }
        return resolvedAutomaticFormat(bundleIdentifier: bundleIdentifier, url: url)
    }

    static func resolvedAutomaticFormat(bundleIdentifier: String?, url: String? = nil) -> String? {
        if let bundleIdentifier, let native = nativeAppFormats[bundleIdentifier] {
            return native
        }

        guard let bundleIdentifier, browserBundleIDs.contains(bundleIdentifier),
              let host = host(from: url) else { return nil }

        switch host {
        case "docs.google.com": return "rtf"
        case "mail.google.com": return "html"
        default: return nil
        }
    }

    static func normalized(_ format: String?) -> String? {
        guard let trimmed = format?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func host(from rawURL: String?) -> String? {
        guard let trimmed = rawURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        let source = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        return URLComponents(string: source)?.host?.lowercased()
    }
}
