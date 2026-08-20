import Foundation
import FluidAudio
import OpenWhisperShared
import os
import Observation

/// macOS speech-to-text backend built on FluidAudio (Parakeet TDT v3, proven
/// fast on Apple Silicon). Owns the model lifecycle and exposes the shared
/// `TranscriptionProviding` surface; nothing above this type knows about the
/// underlying engine.
@MainActor @Observable
final class MacTranscriptionService: TranscriptionProviding {
    static let shared = MacTranscriptionService()

    private(set) var isModelReady = false
    private(set) var isWarmingUp = false
    private(set) var isTranscribing = false
    /// Last model-loading failure, shown in the model card. Cleared on retry.
    private(set) var modelError: String?

    private var asrManager: AsrManager?
    private var state: ModelState = .idle

    private enum ModelState {
        case idle
        case loading
        case ready
        case failed(String)
    }

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "transcription-mac"
    )

    init() {}

    // MARK: - Lifecycle

    /// Loads the speech model from disk if it is already downloaded. Never
    /// triggers a download — used at app launch so a returning user gets STT
    /// immediately and a new user simply stays "not ready" (the dictation guard
    /// then shows the "No model yet" message).
    func warmUpFromCache() async {
        guard !isWarmingUp, !isTranscribing, !isModelReady else { return }
        let dir = Self.modelDirectory
        guard FileManager.default.fileExists(atPath: dir.path),
              AsrModels.modelsExist(at: dir, version: .v3) else {
            return
        }
        isWarmingUp = true
        isModelReady = false
        modelError = nil
        defer { isWarmingUp = false }
        do {
            try await load(from: dir)
            isModelReady = true
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
            isModelReady = false
            modelError = error.localizedDescription
            logger.error("Model warm-up failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Explicitly downloads the speech model (if needed) and loads it. Called
    /// from the model card's "Download" button — never automatically at launch.
    func downloadAndWarmUp() async {
        guard !isWarmingUp, !isTranscribing, !isModelReady else { return }
        isWarmingUp = true
        isModelReady = false
        modelError = nil
        defer { isWarmingUp = false }
        do {
            try await load(from: Self.modelDirectory, downloadIfNeeded: true)
            isModelReady = true
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
            isModelReady = false
            modelError = error.localizedDescription
            logger.error("Model download failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Legacy cache directory used before the App Group move (sandbox-container
    /// Application Support). Copied into the App Group on first launch.
    private static var legacyModelDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FluidAudio/Models/\(Repo.parakeetV3.folderName)", isDirectory: true)
    }

    /// Stable model location in the App Group container (team-scoped, survives
    /// updates and bundle-id changes).
    static var modelDirectory: URL {
        AppGroup.containerURL
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(Repo.parakeetV3.folderName, isDirectory: true)
    }

    /// Copies a previously-downloaded model from the legacy (pre-App-Group)
    /// location into the App Group container so an upgrade does not re-download.
    /// Best-effort: leaves the source in place as a backup.
    func migrateLegacyModelIfNeeded() {
        let legacy = Self.legacyModelDirectory
        let target = Self.modelDirectory
        guard FileManager.default.fileExists(atPath: legacy.path),
              !FileManager.default.fileExists(atPath: target.path),
              AsrModels.modelsExist(at: legacy, version: .v3) else { return }
        try? FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.copyItem(at: legacy, to: target)
    }

    func warmUp() async {
        await warmUpFromCache()
    }

    /// Blocks until the model is ready or the timeout elapses.
    func waitForModelReady(timeout: TimeInterval = 120) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isModelReady { return }
            if case .failed(let message) = state {
                throw TranscriptionError.failed(message)
            }
            await warmUp()
            if !isModelReady {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        throw TranscriptionError.failed("Timed out waiting for the speech model.")
    }

    func unload() async {
        await asrManager?.cleanup()
        asrManager = nil
        isModelReady = false
        state = .idle
    }

    // MARK: - Transcription

    func transcribe(samples: [Float]) async throws -> TranscriptionResult {
        guard let manager = asrManager else {
            throw TranscriptionError.modelUnavailable
        }
        guard isModelReady else {
            throw TranscriptionError.failed("Speech model is not ready.")
        }
        guard !samples.isEmpty else { throw TranscriptionError.noAudio }

        isTranscribing = true
        defer { isTranscribing = false }

        var decoderState = TdtDecoderState.make()
        do {
            let result = try await manager.transcribe(
                samples,
                decoderState: &decoderState,
                language: nil
            )
            return TranscriptionResult(
                text: result.text,
                audioDuration: result.duration,
                confidence: result.confidence
            )
        } catch {
            throw TranscriptionError.failed(error.localizedDescription)
        }
    }

    // MARK: - Model loading

    private func load(from directory: URL, downloadIfNeeded: Bool = false) async throws {
        guard asrManager == nil else { return }
        state = .loading

        let start = Date()
        let models: AsrModels
        if downloadIfNeeded {
            models = try await AsrModels.downloadAndLoad(to: directory, version: .v3)
        } else {
            models = try await AsrModels.load(from: directory, version: .v3)
        }
        let manager = AsrManager(config: .default, models: nil)
        try await manager.loadModels(models)
        asrManager = manager
        logger.info("Model loaded in \(Date().timeIntervalSince(start), privacy: .public)s")
    }
}
