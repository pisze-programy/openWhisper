import Foundation
import ParakeetTDT

@MainActor @Observable
final class TranscriptionService {
    private(set) var isTranscribing: Bool = false

    private let settings: SettingsStore
    private let modelDownload: ModelDownloadManager
    private let engine: TranscriptionEngine

    init(settings: SettingsStore, modelDownload: ModelDownloadManager) {
        self.settings = settings
        self.modelDownload = modelDownload
        self.engine = TranscriptionEngine()
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
            audioDuration: transcription.audioDurationSeconds
        )
    }
}
