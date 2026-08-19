import Foundation
import ParakeetTDT

@MainActor @Observable
public final class ModelDownloadManager: ModelProviding {
    public static let shared = ModelDownloadManager()

    public static let minRequiredFreeSpaceGB: Double = 1.3

    /// Total model download size reported by the Hugging Face tree API.
    public static let modelSizeMB: Double = 480

    public private(set) var status: ModelStatus = .notDownloaded
    public private(set) var availableFreeSpaceGB: Double?

    /// Live download progress in bytes (updated on each progress callback).
    public private(set) var downloadedMB: Double?
    public private(set) var totalMB: Double?

    /// Rolling download speed (MB/s) used to estimate the remaining time.
    public private(set) var speedMBPerSec: Double?

    /// Estimated seconds until the download completes, or nil when unknown.
    public private(set) var etaSeconds: TimeInterval?

    private var lastProgressTime: Date?
    private var lastDownloadedBytes: Int64 = 0

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
        resetProgress()
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
                        self?.updateProgress(done: done, total: total)
                        self?.status = .downloading(progress: value)
                    }
                }
            )
            status = .ready
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func resetProgress() {
        downloadedMB = nil
        totalMB = nil
        speedMBPerSec = nil
        etaSeconds = nil
        lastProgressTime = nil
        lastDownloadedBytes = 0
    }

    private func updateProgress(done: Int64, total: Int64) {
        totalMB = Double(total) / 1_048_576
        downloadedMB = Double(done) / 1_048_576

        let now = Date()
        let elapsed = now.timeIntervalSince(lastProgressTime ?? now)
        let bytesSinceLast = done - lastDownloadedBytes

        if elapsed > 0.5, bytesSinceLast > 0 {
            speedMBPerSec = (Double(bytesSinceLast) / 1_048_576) / elapsed
            let remainingBytes = max(0, total - done)
            if let speed = speedMBPerSec, speed > 0 {
                etaSeconds = (Double(remainingBytes) / 1_048_576) / speed
            } else {
                etaSeconds = nil
            }
        }

        lastProgressTime = now
        lastDownloadedBytes = done
    }
}
