import Foundation
import ParakeetTDT

/// Shared filesystem locations for the downloaded and compiled model.
///
/// Declared `nonisolated` because these paths are resolved from the
/// background transcription queue; the enum holds no mutable state, so there
/// is nothing to protect with the main actor.
nonisolated enum ModelLocations {
    /// Raw `.mlpackage` files downloaded from HuggingFace.
    static var hfModelsDirectory: URL {
        appSupportDirectory(named: "hf-models")
    }

    /// Compiled `.mlmodelc` bundles produced from the packages.
    static var compiledModelsDirectory: URL {
        appSupportDirectory(named: "mlmodelc")
    }

    /// Directory for one fully-downloaded repo (`repoId` with "/" → "_").
    static var repoDirectory: URL {
        hfModelsDirectory.appendingPathComponent(
            ParakeetTranscriber.defaultRepoId.replacingOccurrences(of: "/", with: "_"),
            isDirectory: true
        )
    }

    /// Marker file written by `ModelDownloader` when a repo download completes.
    static var completionMarker: URL {
        repoDirectory.appendingPathComponent(".complete")
    }

    /// Whether the model repo is fully downloaded.
    static var isDownloaded: Bool {
        FileManager.default.fileExists(atPath: completionMarker.path)
    }

    /// Application Support/OpenWhisper/<name>, created on first access.
    /// Application Support (not Caches) so the model survives launches and
    /// is never purged by the OS.
    private static func appSupportDirectory(named name: String) -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let openWhisperDirectory = base
            .appendingPathComponent("OpenWhisper", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: openWhisperDirectory, withIntermediateDirectories: true
        )
        excludeFromBackup(openWhisperDirectory)
        let url = openWhisperDirectory
            .appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true
        )
        return url
    }

    /// Marks a directory as excluded from iCloud / iTunes backups so the
    /// ~450–650 MB model is never uploaded.
    private static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
