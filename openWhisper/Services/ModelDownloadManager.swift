import Foundation
import ParakeetTDT

@MainActor @Observable
final class ModelDownloadManager {
    static let shared = ModelDownloadManager()

    private(set) var status: ModelStatus = .notDownloaded

    var isReady: Bool { status == .ready }

    func refreshStatus() {
        guard status == .notDownloaded || status == .ready else { return }
        status = ModelLocations.isDownloaded ? .ready : .notDownloaded
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
