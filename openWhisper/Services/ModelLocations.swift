import Foundation
import ParakeetTDT

nonisolated enum ModelLocations {
    static var hfModelsDirectory: URL {
        appSupportDirectory(named: "hf-models")
    }

    static var compiledModelsDirectory: URL {
        appSupportDirectory(named: "mlmodelc")
    }

    static var repoDirectory: URL {
        hfModelsDirectory.appendingPathComponent(
            ParakeetTranscriber.defaultRepoId.replacingOccurrences(of: "/", with: "_"),
            isDirectory: true
        )
    }

    static var completionMarker: URL {
        repoDirectory.appendingPathComponent(".complete")
    }

    static var isDownloaded: Bool {
        FileManager.default.fileExists(atPath: completionMarker.path)
    }

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

    private static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
