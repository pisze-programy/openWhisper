import Foundation
import ParakeetTDT
import OpenWhisperShared

@MainActor @Observable
final class ModelDownloadManager {
    static let shared = ModelDownloadManager()

    /// Minimum free space the model needs on disk after download + compile
    /// (`.mlpackage` sources are deleted, so ~480 MB download + compiled
    /// `.mlmodelc`).
    static let minRequiredFreeSpaceGB: Double = 1.3

    private(set) var status: ModelStatus = .notDownloaded
    private(set) var availableFreeSpaceGB: Double?

    var isReady: Bool { status == .ready }

    var isLowOnSpace: Bool {
        guard let availableFreeSpaceGB else { return false }
        return availableFreeSpaceGB < Self.minRequiredFreeSpaceGB
    }

    func refreshStatus() {
        refreshAvailableSpace()
        guard status == .notDownloaded || status == .ready else { return }
        status = ModelLocations.isDownloaded ? .ready : .notDownloaded
    }

    func refreshAvailableSpace() {
        let url = ModelLocations.hfModelsDirectory
        if let capacity = try? url.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ).volumeAvailableCapacityForImportantUsage {
            availableFreeSpaceGB = Double(capacity) / 1_073_741_824
        } else {
            availableFreeSpaceGB = nil
        }
    }

    func startDownload(force: Bool = false) async {
        if case .downloading = status { return }
        if status == .ready && !force { return }

        if force, status == .ready {
            try? FileManager.default.removeItem(at: ModelLocations.completionMarker)
        }
        status = .downloading(progress: 0)

        let downloader = ModelDownloader(cacheDirectory: ModelLocations.hfModelsDirectory)
        do {
            _ = try await downloader.download(
                repoId: ParakeetTranscriber.defaultRepoId,
                skipIfPresent: !force,
                progress: { [weak self] done, total, _ in
                    guard total > 0 else { return }
                    let value = Double(done) / Double(total)
                    Task { @MainActor [weak self] in
                        self?.status = .downloading(progress: value)
                    }
                }
            )
            status = .ready
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
