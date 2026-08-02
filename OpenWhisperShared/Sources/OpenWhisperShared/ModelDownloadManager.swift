import Foundation
import ParakeetTDT

@MainActor @Observable
public final class ModelDownloadManager: ModelProviding {
    public static let shared = ModelDownloadManager()

    public static let minRequiredFreeSpaceGB: Double = 1.3

    public private(set) var status: ModelStatus = .notDownloaded
    public private(set) var availableFreeSpaceGB: Double?

    public var isReady: Bool { status == .ready }

    public var isLowOnSpace: Bool {
        guard let availableFreeSpaceGB else { return false }
        return availableFreeSpaceGB < Self.minRequiredFreeSpaceGB
    }

    public init() {}

    public func refreshStatus() {
        refreshAvailableSpace()
        guard status == .notDownloaded || status == .ready else { return }
        status = ModelLocations.isDownloaded ? .ready : .notDownloaded
    }

    public func refreshAvailableSpace() {
        let url = ModelLocations.hfModelsDirectory
        if let capacity = try? url.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ).volumeAvailableCapacityForImportantUsage {
            availableFreeSpaceGB = Double(capacity) / 1_073_741_824
        } else {
            availableFreeSpaceGB = nil
        }
    }

    public func startDownload(force: Bool = false) async {
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
