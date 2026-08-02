import Foundation
import ParakeetTDT
import OpenWhisperShared

nonisolated final class TranscriptionEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.openwhisper.transcribe")
    private var transcriber: ParakeetTranscriber?
    private var currentComputeUnits: ParakeetComputeUnits?

    init() {}

    func prepare(computeUnits: ParakeetComputeUnits) throws {
        try queue.sync { _ = try makeTranscriber(computeUnits: computeUnits) }
    }

    func release() {
        queue.sync {
            transcriber = nil
            currentComputeUnits = nil
        }
    }

    func transcribe(audioURL: URL, computeUnits: ParakeetComputeUnits) throws -> Transcription {
        let samples: [Float]
        do {
            samples = try AudioLoader.loadMono16k(at: audioURL)
        } catch {

            throw Self.map(error)
        }
        return try transcribe(samples: samples, computeUnits: computeUnits)
    }

    func transcribe(samples: [Float], computeUnits: ParakeetComputeUnits) throws -> Transcription {
        let normalized = AudioNormalizer.process(samples)
        do {
            return try queue.sync {
                let transcriber = try makeTranscriber(computeUnits: computeUnits)
                return try transcriber.transcribe(samples: normalized)
            }
        } catch {
            throw Self.map(error)
        }
    }

    private func makeTranscriber(computeUnits: ParakeetComputeUnits) throws -> ParakeetTranscriber {
        if let transcriber, currentComputeUnits == computeUnits {
            return transcriber
        }
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
            deleteSourceAfterCompile: true,
            cacheDirectory: ModelLocations.compiledModelsDirectory
        )
    }

    private static func map(_ error: Error) -> TranscriptionError {
        if let parakeet = error as? ParakeetError {
            return map(parakeet)
        }
        return .failed(error.localizedDescription)
    }

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
            return .noAudio
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
