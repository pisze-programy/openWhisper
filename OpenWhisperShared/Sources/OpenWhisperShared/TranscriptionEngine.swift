import Foundation
import ParakeetTDT

public final class TranscriptionEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.openwhisper.transcribe")
    private var transcriber: ParakeetTranscriber?
    private var currentComputeUnits: ParakeetComputeUnits?

    public init() {}

    public func prepare(computeUnits: ParakeetComputeUnits) throws {
        let start = TranscriptionMetrics.Snapshot.capture()
        try queue.sync { _ = try makeTranscriber(computeUnits: computeUnits) }
        TranscriptionMetrics.report("engine.prepare", since: start, extra: "units=\(computeUnits.rawValue)")
    }

    /// Drop the in-memory model so the OS can reclaim its memory (GPU / Metal
    /// buffers included). Call when the app backgrounds or is under pressure.
    /// The transcriber is rebuilt lazily on the next `prepare`/`transcribe`.
    public func release() {
        let start = TranscriptionMetrics.Snapshot.capture()
        queue.sync {
            transcriber = nil
            currentComputeUnits = nil
        }
        TranscriptionMetrics.report("engine.release", since: start)
    }

    public func transcribe(audioURL: URL, computeUnits: ParakeetComputeUnits) throws -> Transcription {
        let start = TranscriptionMetrics.Snapshot.capture()
        do {
            let result = try queue.sync {
                let transcriber = try makeTranscriber(computeUnits: computeUnits)
                return try transcriber.transcribe(audioURL: audioURL)
            }
            TranscriptionMetrics.report(
                "engine.transcribe.audioURL",
                since: start,
                extra: "units=\(computeUnits.rawValue) | \(TranscriptionMetrics.timingLine(result))"
            )
            return result
        } catch {
            TranscriptionMetrics.report(
                "engine.transcribe.audioURL.error",
                since: start,
                extra: "units=\(computeUnits.rawValue) | \(error.localizedDescription)"
            )
            throw Self.map(error)
        }
    }

    public func transcribe(samples: [Float], computeUnits: ParakeetComputeUnits) throws -> Transcription {
        let start = TranscriptionMetrics.Snapshot.capture()
        do {
            let result = try queue.sync {
                let transcriber = try makeTranscriber(computeUnits: computeUnits)
                return try transcriber.transcribe(samples: samples)
            }
            TranscriptionMetrics.report(
                "engine.transcribe.samples",
                since: start,
                extra: "units=\(computeUnits.rawValue) | samples=\(samples.count) | \(TranscriptionMetrics.timingLine(result))"
            )
            return result
        } catch {
            TranscriptionMetrics.report(
                "engine.transcribe.samples.error",
                since: start,
                extra: "units=\(computeUnits.rawValue) | \(error.localizedDescription)"
            )
            throw Self.map(error)
        }
    }

    private func makeTranscriber(computeUnits: ParakeetComputeUnits) throws -> ParakeetTranscriber {
        if let transcriber, currentComputeUnits == computeUnits {
            return transcriber
        }
        let start = TranscriptionMetrics.Snapshot.capture()
        transcriber = nil
        currentComputeUnits = computeUnits
        do {
            let new = try buildTranscriber(computeUnits: computeUnits)
            transcriber = new
            TranscriptionMetrics.report(
                "engine.transcriber.build",
                since: start,
                extra: "units=\(computeUnits.rawValue)"
            )
            return new
        } catch {
            TranscriptionMetrics.report(
                "engine.transcriber.build.error",
                since: start,
                extra: "units=\(computeUnits.rawValue) | \(error.localizedDescription)"
            )
            throw error
        }
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
