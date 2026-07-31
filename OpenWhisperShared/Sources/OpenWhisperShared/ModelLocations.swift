import Foundation

public enum ModelLocations {
    public static var hfModelsDirectory: URL { sharedDirectory(named: "hf-models") }
    public static var compiledModelsDirectory: URL { sharedDirectory(named: "mlmodelc") }
    public static var repoDirectory: URL {
        hfModelsDirectory.appendingPathComponent("mweinbach1_parakeet-tdt-0.6b-v3-coreml", isDirectory: true)
    }
    public static var completionMarker: URL { repoDirectory.appendingPathComponent(".complete") }
    public static var isDownloaded: Bool {
        FileManager.default.fileExists(atPath: completionMarker.path)
    }
    public static var historyStoreURL: URL {
        AppGroup.containerURL.appendingPathComponent("History.store")
    }

    private static func sharedDirectory(named name: String) -> URL {
        let base = AppGroup.containerURL
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        excludeFromBackup(base)
        let url = base.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
