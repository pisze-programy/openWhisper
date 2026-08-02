import Foundation
import os
import ParakeetTDT
import OpenWhisperShared
import UIKit

@MainActor @Observable
final class TranscriptionService {
    private(set) var isTranscribing: Bool = false
    private(set) var isWarmingUp: Bool = false
    private(set) var isModelReady: Bool = false

    private let settings: SettingsStore
    private let modelDownload: ModelDownloadManager
    private let engine: TranscriptionEngine
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "piszeprogramy.openWhisper", category: "transcription")

    init(settings: SettingsStore, modelDownload: ModelDownloadManager) {
        self.settings = settings
        self.modelDownload = modelDownload
        self.engine = TranscriptionEngine()
    }

    func warmUp() async {
        guard modelDownload.isReady, !isWarmingUp, !isTranscribing, !isModelReady else { return }
        isWarmingUp = true
        isModelReady = false
        defer { isWarmingUp = false }
        let units = settings.computeUnits
        let outcome = await Task.detached(priority: .utility) { [engine] in
            Result { try engine.prepare(computeUnits: units) }
        }.value
        switch outcome {
        case .success:
            isModelReady = true
            await warmGPUShaders(units: units)
        case .failure:
            isModelReady = false
        }
    }

    private func warmGPUShaders(units: ParakeetComputeUnits) async {
        switch units {
        case .gpu, .all: break
        case .ane, .cpu: return
        }
        // GPU/Metal work is forbidden while the app is in the background — skip
        // the shader warmup then (it's an optimization, never required).
        guard UIApplication.shared.applicationState == .active else { return }
        let silence = [Float](repeating: 0, count: 16_000)
        await Task.detached(priority: .utility) { [engine] in
            _ = try? engine.transcribe(samples: silence, computeUnits: units)
        }.value
    }

    func enterBackground() {
        guard !isWarmingUp, !isTranscribing else { return }
        engine.release()
        isModelReady = false
    }

    func transcribe(audioURL: URL) async throws -> TranscriptionResult {
        guard !isTranscribing else { throw TranscriptionError.busy }
        isTranscribing = true
        defer { isTranscribing = false }

        let engine = self.engine

        // Core ML's default compute path is GPU, and iOS forbids GPU/Metal work
        // while the app is in the background ("Insufficient Permission to submit
        // GPU work from background"). Claim a short background task so the model
        // load + inference can finish even if the user switches apps right after
        // releasing the mic, and pick the compute units accordingly: the user's
        // choice in the foreground, CPU in the background (CPU is not subject to
        // the GPU restriction). A GPU failure mid-flight falls back to CPU.
        let backgroundTask = TranscriptionBackgroundTask(name: "openwhisper.transcribe")
        defer { backgroundTask.end() }

        let preferred = settings.computeUnits
        let isActive = UIApplication.shared.applicationState == .active
        // The user's compute-units choice is always honoured in the foreground.
        // The only exception is iOS itself: GPU/Metal work is forbidden while the
        // app is in the background, so when the app is already backgrounded we
        // start directly on CPU (avoids a guaranteed GPU failure + re-load), and
        // if the app backgrounds mid-transcription the GPU failure is retried
        // once on CPU. CPU is never used to rescue a real foreground failure.
        let initialUnits = isActive ? preferred : ParakeetComputeUnits.cpu
        do {
            return try await runTranscription(audioURL: audioURL, computeUnits: initialUnits, engine: engine)
        } catch {
            // Re-check the CURRENT state: `isActive` above was captured before
            // the call, so if the app backgrounds mid-flight we must still fall
            // back to CPU (otherwise the GPU error surfaces and the dictation
            // is lost).
            let stillActive = UIApplication.shared.applicationState == .active
            guard preferred != .cpu, !stillActive else { throw error }
            logger.error("GPU transcription failed in background (\(error.localizedDescription, privacy: .public)) — retrying on CPU")
            return try await runTranscription(audioURL: audioURL, computeUnits: .cpu, engine: engine)
        }
    }

    private func runTranscription(
        audioURL: URL,
        computeUnits: ParakeetComputeUnits,
        engine: TranscriptionEngine
    ) async throws -> TranscriptionResult {
        let transcription = try await Task.detached(priority: .userInitiated) {
            try engine.transcribe(audioURL: audioURL, computeUnits: computeUnits)
        }.value
        return TranscriptionResult(
            text: transcription.text,
            audioDuration: transcription.audioDurationSeconds,
            confidence: transcription.confidence
        )
    }
}

/// Small wrapper around `UIBackgroundTaskIdentifier` so the expiration handler
/// can safely end the task without Swift concurrency capture issues.
private final class TranscriptionBackgroundTask {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            guard let self, self.identifier != .invalid else { return }
            UIApplication.shared.endBackgroundTask(self.identifier)
            self.identifier = .invalid
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }

    deinit {
        end()
    }
}
