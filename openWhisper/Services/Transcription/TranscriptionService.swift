import Foundation
import ParakeetTDT
import OpenWhisperShared

@MainActor @Observable
final class TranscriptionService {
    private(set) var isTranscribing: Bool = false
    private(set) var isWarmingUp: Bool = false
    private(set) var isModelReady: Bool = false

    private let settings: SettingsStore
    private let modelDownload: ModelDownloadManager
    private let engine: TranscriptionEngine

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

        let computeUnits = settings.computeUnits
        let engine = self.engine

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
