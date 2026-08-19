import Foundation
import FluidAudio
import OpenWhisperShared
import os

/// macOS speech-to-text backend built on FluidAudio (Parakeet TDT v3, proven
/// fast on Apple Silicon). Owns the model lifecycle and exposes the shared
/// `TranscriptionProviding` surface; nothing above this type knows about the
/// underlying engine.
@MainActor
final class MacTranscriptionService: TranscriptionProviding {
    private(set) var isModelReady = false
    private(set) var isWarmingUp = false
    private(set) var isTranscribing = false

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

    func warmUp() async {
        guard !isWarmingUp, !isTranscribing, !isModelReady else { return }
        isWarmingUp = true
        isModelReady = false
        defer { isWarmingUp = false }

        do {
            try await loadIfNeeded()
            isModelReady = true
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
            isModelReady = false
            logger.error("Model warm-up failed: \(error.localizedDescription, privacy: .public)")
        }
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

    private func loadIfNeeded() async throws {
        guard asrManager == nil else { return }
        state = .loading

        let start = Date()
        let models = try await AsrModels.loadFromCache(version: .v3)
        let manager = AsrManager(config: .default, models: nil)
        try await manager.loadModels(models)
        asrManager = manager
        logger.info("Model loaded in \(Date().timeIntervalSince(start), privacy: .public)s")
    }
}
