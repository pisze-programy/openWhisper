import Foundation
import ParakeetTDT

/// The outcome of a transcription: recognized text plus the audio's duration.
public struct TranscriptionResult: Sendable {
    let text: String
    let audioDuration: TimeInterval
}

/// Errors surfaced by `TranscriptionService`.
enum TranscriptionError: LocalizedError {
    case busy
    case modelUnavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .busy:
            return "A transcription is already in progress."
        case .modelUnavailable:
            return "The speech model isn't downloaded yet."
        case .failed(let message):
            return message
        }
    }
}

/// Transcribes recordings on a background queue and reports status to the UI.
@MainActor @Observable
final class TranscriptionService {
    private(set) var isTranscribing: Bool = false

    private let settings: SettingsStore
    /// Reserved for future pre-checks; the engine validates the model on its
    /// own queue before transcribing.
    private let modelDownload: ModelDownloadManager
    private let engine: Engine

    init(settings: SettingsStore, modelDownload: ModelDownloadManager) {
        self.settings = settings
        self.modelDownload = modelDownload
        self.engine = Engine()
    }

    /// Transcribes `audioURL` and returns the recognized text and duration.
    ///
    /// Single-flight: only one transcription runs at a time. `isTranscribing`
    /// is set before the first `await` and cleared in a `defer` around the
    /// whole method body. The Core ML work — including the first-time model
    /// compile — runs on a dedicated serial queue via `Task.detached`, never
    /// blocking the main actor.
    func transcribe(audioURL: URL) async throws -> TranscriptionResult {
        guard !isTranscribing else { throw TranscriptionError.busy }
        isTranscribing = true
        defer { isTranscribing = false }

        // Capture MainActor-isolated values before leaving the actor.
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

/// Owns the `ParakeetTranscriber` instance. `nonisolated` because all work is
/// serialized on a background queue: the transcriber's `init` compiles the
/// model on first use (seconds) and `transcribe` can run for minutes.
nonisolated final class Engine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.openwhisper.transcribe")
    private var transcriber: ParakeetTranscriber?
    private var currentComputeUnits: ParakeetComputeUnits?

    func transcribe(audioURL: URL, computeUnits: ParakeetComputeUnits) throws -> Transcription {
        try queue.sync {
            let transcriber = try makeTranscriber(computeUnits: computeUnits)
            do {
                return try transcriber.transcribe(audioURL: audioURL)
            } catch {
                throw Self.map(error)
            }
        }
    }

    /// Lazily builds the transcriber once and keeps it alive for the process
    /// lifetime. `deleteSourceAfterCompile: false` is REQUIRED: the package's
    /// `resolveModel` only looks inside `modelsRoot`, so deleting the
    /// `.mlpackage` sources after the first compile would make every later
    /// launch fail with "model not found" (the compiled `.mlmodelc`s live in
    /// a separate cache directory the package never re-inspects).
    private func makeTranscriber(computeUnits: ParakeetComputeUnits) throws -> ParakeetTranscriber {
        if let transcriber, currentComputeUnits == computeUnits {
            return transcriber
        }
        // The cached transcriber was built with a different
        // `ParakeetComputeUnits`, so its `MLModelConfiguration` is stale.
        // Rebuild it — this reloads the model once after a settings change,
        // which is acceptable and correct.
        transcriber = nil
        currentComputeUnits = computeUnits
        let new = try buildTranscriber(computeUnits: computeUnits)
        transcriber = new
        return new
    }

    private func buildTranscriber(computeUnits: ParakeetComputeUnits) throws -> ParakeetTranscriber {
        guard ModelLocations.isDownloaded else {
            throw TranscriptionError.modelUnavailable
        }
        return try ParakeetTranscriber(
            modelsRoot: ModelLocations.repoDirectory,
            computeUnits: computeUnits,
            deleteSourceAfterCompile: false,
            cacheDirectory: ModelLocations.compiledModelsDirectory
        )
    }

    /// Maps any error thrown by the pipeline to `TranscriptionError`.
    private static func map(_ error: Error) -> TranscriptionError {
        if let parakeet = error as? ParakeetError {
            return map(parakeet)
        }
        return .failed(error.localizedDescription)
    }

    /// Maps every `ParakeetError` case to a user-facing message.
    private static func map(_ error: ParakeetError) -> TranscriptionError {
        switch error {
        case .modelNotFound(let url):
            return .failed("Model files not found at \(url.path). Download the model again.")
        case .modelCompileFailed(let url, let underlying):
            return .failed("Failed to compile the model at \(url.lastPathComponent): \(underlying.localizedDescription)")
        case .tokenizerLoadFailed(let url, let underlying):
            return .failed("Failed to load the tokenizer at \(url.lastPathComponent): \(underlying.localizedDescription)")
        case .audioLoadFailed(let url, let underlying):
            return .failed("Couldn't read the audio file \(url.lastPathComponent): \(underlying.localizedDescription)")
        case .audioEmpty:
            return .failed("The recording contains no audio.")
        case .unexpectedOutputShape(let name, let got, let expected):
            return .failed("Unexpected model output shape for '\(name)' (got \(got), expected \(expected)).")
        case .missingOutput(let name):
            return .failed("Missing model output '\(name)'.")
        case .fftSetupFailed:
            return .failed("Failed to set up audio processing.")
        case .downloadFailed(let repoId, let reason):
            return .failed("Model download failed for \(repoId): \(reason)")
        }
    }
}
