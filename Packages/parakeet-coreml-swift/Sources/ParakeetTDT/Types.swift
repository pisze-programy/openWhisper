import CoreML
import Foundation

/// Which Core ML compute units the scheduler is allowed to target.
public enum ParakeetComputeUnits: String, Sendable {
    /// Apple Neural Engine + CPU fallback. Default; best power / latency balance
    /// on iOS and most Macs for this model.
    case ane
    /// CPU + GPU (excludes Neural Engine). Fastest for the 4-bit palettized
    /// encoder on Apple silicon, ~1.7x faster than ANE in our benchmarks.
    case gpu
    /// CPU only. Portable fallback; ~half the throughput of ANE.
    case cpu
    /// Let Core ML's scheduler pick from CPU + GPU + ANE.
    case all

    public var mlComputeUnits: MLComputeUnits {
        switch self {
        case .ane: return .cpuAndNeuralEngine
        case .gpu: return .cpuAndGPU
        case .cpu: return .cpuOnly
        case .all: return .all
        }
    }
}

/// Breakdown of where inference time went, in seconds.
public struct TranscriptionTiming: Sendable {
    public var melExtract: Double
    public var encoder: Double
    public var decoderLoop: Double   // decoder + joint + argmax combined
    public var detokenize: Double

    public init(
        melExtract: Double = 0,
        encoder: Double = 0,
        decoderLoop: Double = 0,
        detokenize: Double = 0
    ) {
        self.melExtract = melExtract
        self.encoder = encoder
        self.decoderLoop = decoderLoop
        self.detokenize = detokenize
    }

    public var total: Double { melExtract + encoder + decoderLoop + detokenize }
}

/// Result of a successful transcription.
public struct Transcription: Sendable {
    /// Final detokenized text.
    public let text: String
    /// Token IDs emitted by the TDT greedy decoder (blank + duration tokens
    /// already stripped).
    public let tokenIds: [Int]
    /// Per-token encoder-frame indices. Lets callers reconstruct approximate
    /// word-level timings when combined with `durations` and the encoder's
    /// `hopLength * subsamplingFactor` stride.
    public let frameIndices: [Int]
    /// Per-token duration value (in encoder frames) predicted by the joint.
    public let durations: [Int]
    /// Wall-clock audio duration (seconds).
    public let audioDurationSeconds: Double
    /// Wall-clock inference duration (seconds). Excludes model load time.
    public let inferenceDurationSeconds: Double
    /// Per-phase timing breakdown (sums to ``inferenceDurationSeconds``).
    public let timing: TranscriptionTiming
    /// `audioDurationSeconds / inferenceDurationSeconds`. Higher is better;
    /// >1 means faster than real time.
    public var rtfx: Double {
        inferenceDurationSeconds > 0
            ? audioDurationSeconds / inferenceDurationSeconds
            : 0
    }
}

/// Errors surfaced by the ParakeetTDT pipeline.
public enum ParakeetError: Error, CustomStringConvertible, Sendable {
    case modelNotFound(url: URL)
    case modelCompileFailed(url: URL, underlying: Error)
    case tokenizerLoadFailed(url: URL, underlying: Error)
    case audioLoadFailed(url: URL, underlying: Error)
    case audioEmpty(url: URL)
    case unexpectedOutputShape(name: String, got: [Int], expected: String)
    case missingOutput(name: String)
    case fftSetupFailed
    case downloadFailed(repoId: String, reason: String)

    public var description: String {
        switch self {
        case .modelNotFound(let url):
            return "Model not found at \(url.path)"
        case .modelCompileFailed(let url, let underlying):
            return "Failed to compile model at \(url.path): \(underlying)"
        case .tokenizerLoadFailed(let url, let underlying):
            return "Failed to load tokenizer at \(url.path): \(underlying)"
        case .audioLoadFailed(let url, let underlying):
            return "Failed to load audio at \(url.path): \(underlying)"
        case .audioEmpty(let url):
            return "Audio file at \(url.path) contains no samples"
        case .unexpectedOutputShape(let name, let got, let expected):
            return "Output \"\(name)\" has unexpected shape \(got); expected \(expected)"
        case .missingOutput(let name):
            return "Missing expected output \"\(name)\" from Core ML prediction"
        case .fftSetupFailed:
            return "Failed to create vDSP FFT setup"
        case .downloadFailed(let repoId, let reason):
            return "Failed to download models from \(repoId): \(reason)"
        }
    }
}
