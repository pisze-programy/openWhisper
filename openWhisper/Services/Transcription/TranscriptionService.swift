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
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "transcription")

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

        let backgroundTask = TranscriptionBackgroundTask(name: "openwhisper.transcribe")
        defer { backgroundTask.end() }

        let preferred = settings.computeUnits
        let isActive = UIApplication.shared.applicationState == .active

        let initialUnits = isActive ? preferred : ParakeetComputeUnits.cpu
        do {
            return try await runTranscription(audioURL: audioURL, computeUnits: initialUnits, engine: engine)
        } catch {

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
