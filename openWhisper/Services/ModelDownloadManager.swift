import Foundation
import ParakeetTDT

/// Drives the HuggingFace model download and exposes its state to the UI.
///
/// Downloads are resumable: `ModelDownloader` writes a `.complete` marker
/// only when every file is present, and skips already-downloaded files by
/// size, so a re-run after an app kill picks up where it left off.
@MainActor @Observable
final class ModelDownloadManager {
    static let shared = ModelDownloadManager()

    private(set) var status: ModelStatus = .notDownloaded

    var isReady: Bool { status == .ready }

    /// Re-reads disk state. Call at app launch.
    ///
    /// Never clobbers an in-flight download or a failed state: only a
    /// terminal / clean state is recomputed from disk.
    func refreshStatus() {
        guard status == .notDownloaded || status == .ready else { return }
        status = ModelLocations.isDownloaded ? .ready : .notDownloaded
    }

    /// Downloads (or resumes) the model, updating `status` through the flow.
    ///
    /// Single-flight: a second call while a download is already running is a
    /// no-op (two concurrent `ModelDownloader` loops would corrupt the same
    /// files). Pass `force: true` to refresh an already-downloaded model: the
    /// `.complete` marker is deleted and every file is re-fetched.
    func startDownload(force: Bool = false) async {
        // Never run two concurrent downloader loops against the same files.
        if case .downloading = status { return }
        if status == .ready && !force { return }

        if force, status == .ready {
            // Drop the marker so the downloader doesn't short-circuit; the
            // files themselves are then refreshed via `skipIfPresent: false`.
            try? FileManager.default.removeItem(at: ModelLocations.completionMarker)
        }
        status = .downloading(progress: 0)

        let downloader = ModelDownloader(cacheDirectory: ModelLocations.hfModelsDirectory)
        do {
            _ = try await downloader.download(
                repoId: ParakeetTranscriber.defaultRepoId,
                skipIfPresent: !force,
                progress: { [weak self] done, total, _ in
                    // Progress handler is @Sendable and runs off the main
                    // actor; hop back to update `status`.
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
