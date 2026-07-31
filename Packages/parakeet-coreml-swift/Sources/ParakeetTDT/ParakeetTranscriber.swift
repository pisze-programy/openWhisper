import CoreML
import Foundation
import os

private let perfLog = Logger(
    subsystem: "com.parakeet-tdt",
    category: "performance"
)

/// End-to-end Parakeet TDT transcriber.
///
/// Expects a directory laid out like this (matching the HuggingFace repo):
///
/// ```
/// modelsRoot/
///   encoder.mlpackage/    (or encoder.mlmodelc, if already compiled)
///   decoder.mlpackage/
///   joint.mlpackage/
///   tokenizer.json
/// ```
///
/// The first call compiles each ``.mlpackage`` into a cached ``.mlmodelc``.
/// Subsequent launches find the cached compiled bundle and skip the compile
/// step.
///
/// Three convenience entry points, in order of "how little work do I want
/// to do":
///
/// ```swift
/// // 1. Zero-setup: fetch the default model from HuggingFace + transcribe.
/// let t = try await ParakeetTranscriber.fromHuggingFace()
/// let result = try t.transcribe(audioURL: audio)
///
/// // 2. Specify a HF repo (useful for pinning / private mirrors).
/// let t = try await ParakeetTranscriber.fromHuggingFace(
///     repoId: "mweinbach1/parakeet-tdt-0.6b-v3-coreml",
///     computeUnits: .gpu
/// )
///
/// // 3. Fully local: point at a directory you staged yourself.
/// let t = try ParakeetTranscriber(modelsRoot: localURL)
/// ```
public final class ParakeetTranscriber {

    /// Default HuggingFace repo used by ``fromHuggingFace()`` when no
    /// `repoId` is supplied.
    public static let defaultRepoId = "mweinbach1/parakeet-tdt-0.6b-v3-coreml"
    public let computeUnits: ParakeetComputeUnits
    public let chunkMelFrames: Int    // must match the encoder's traced shape
    public let sampleRate: Int

    private let runner: ModelRunner
    private let tokenizer: Tokenizer
    private let featureExtractor: MelFeatureExtractor
    private let cacheURL: URL

    /// Load the transcriber. Compiles any `.mlpackage`s that aren't already
    /// in the cache. Use `deleteSourceAfterCompile: true` to drop the raw
    /// `.mlpackage` from disk once compilation succeeds (halves peak disk
    /// usage on space-constrained devices).
    ///
    /// ``decoderWorkers`` controls how many parallel decode-loop threads
    /// the pipeline uses. ``nil`` (the default) picks 2 for ANE / GPU / all
    /// and 1 for CPU-only (because on CPU the encoder contends with the
    /// decode workers on the same cores). Higher values can help GPU
    /// further if decode is the bottleneck.
    public init(
        modelsRoot: URL,
        computeUnits: ParakeetComputeUnits = .ane,
        chunkMelFrames: Int = 3000,
        sampleRate: Int = 16_000,
        deleteSourceAfterCompile: Bool = false,
        cacheDirectory: URL? = nil,
        decoderWorkers: Int? = nil
    ) throws {
        self.computeUnits = computeUnits
        self.chunkMelFrames = chunkMelFrames
        self.sampleRate = sampleRate

        var phase = Date()
        func elapsed(_ label: String) {
            let ms = Date().timeIntervalSince(phase) * 1000
            perfLog.info("load.\(label, privacy: .public): \(String(format: "%.0f", ms)) ms")
            phase = Date()
        }

        let cache = ModelCache(
            cacheDirectory: cacheDirectory,
            deleteSourceAfterCompile: deleteSourceAfterCompile
        )
        self.cacheURL = cache.cacheDirectory

        let tokenizerURL = modelsRoot.appendingPathComponent("tokenizer.json")

        // Prefer the source `.mlpackage` (compile-or-use-cache). If the
        // sources were deleted after compiling (`deleteSourceAfterCompile`),
        // fall back to the compiled bundle already in the cache.
        let encCompiled = try Self.resolveOrCached(
            modelsRoot: modelsRoot, cache: cache, named: "encoder"
        )
        let decCompiled = try Self.resolveOrCached(
            modelsRoot: modelsRoot, cache: cache, named: "decoder"
        )
        let joiCompiled = try Self.resolveOrCached(
            modelsRoot: modelsRoot, cache: cache, named: "joint"
        )
        elapsed("resolve+compile")

        let config = MLModelConfiguration()
        config.computeUnits = computeUnits.mlComputeUnits

        let encoder = try MLModel(contentsOf: encCompiled, configuration: config)
        elapsed("encoder.mlmodel")
        let decoder = try MLModel(contentsOf: decCompiled, configuration: config)
        elapsed("decoder.mlmodel")
        let joint = try MLModel(contentsOf: joiCompiled, configuration: config)
        elapsed("joint.mlmodel")

        // Decoder stateful sizes are encoded in the spec's hidden / cell
        // input shapes: [num_layers, 1, hidden].
        let (decLayers, decHidden) = ParakeetTranscriber.readDecoderStateShape(
            from: decoder
        )

        // Per-target worker defaults tuned on M-class silicon. Measured
        // scaling on `test_audio.mp3` (see README):
        //   - CPU:  1 worker  (2+ contends with the on-CPU encoder)
        //   - ANE:  2 workers (encoder-bound; more doesn't help)
        //   - GPU:  4 workers (diminishing returns past 4)
        //   - all:  4 workers (assume GPU involved)
        let workerCount: Int = {
            if let override = decoderWorkers { return max(1, override) }
            switch computeUnits {
            case .cpu: return 1
            case .ane: return 2
            case .gpu, .all: return 4
            }
        }()

        self.runner = try ModelRunner(
            encoder: encoder,
            decoder: decoder,
            joint: joint,
            encoderShapes: ModelRunner.EncoderShapes(
                batch: 1, maxTime: chunkMelFrames, numMelBins: 128
            ),
            decoderHiddenLayers: decLayers,
            decoderHiddenSize: decHidden,
            blankTokenId: 8192,
            durations: [0, 1, 2, 3, 4],
            vocabSize: 8193,
            maxSymbolsPerStep: 10,
            numDecoderWorkers: workerCount
        )
        elapsed("runner")
        self.tokenizer = try Tokenizer(tokenizerJSONURL: tokenizerURL)
        elapsed("tokenizer")
        self.featureExtractor = try MelFeatureExtractor(
            sampleRate: sampleRate,
            hopLength: 160,
            winLength: 400,
            nFFT: 512,
            numMelFilters: 128,
            preemphasis: 0.97
        )
        elapsed("featureExtractor")
    }

    // MARK: - High-level transcription

    /// Transcribe a full audio file. Long files are chunked into
    /// non-overlapping ``chunkMelFrames * hopLength / sampleRate``-second
    /// windows (30 s with the default 3000 mel frames). Token streams from
    /// every chunk are concatenated, then detokenized in one pass.
    public func transcribe(audioURL: URL) throws -> Transcription {
        let t0 = Date()
        let audio = try AudioLoader.loadMono16k(at: audioURL)
        let parseMS = Date().timeIntervalSince(t0) * 1000
        let audioSeconds = Double(audio.count) / Double(self.sampleRate)
        perfLog.info(
            "parse.audioURL: \(String(format: "%.0f", parseMS)) ms | samples \(audio.count) | \(String(format: "%.2f", audioSeconds)) s audio"
        )
        return try transcribe(samples: audio)
    }

    /// Transcribe an already-loaded mono `Float` buffer at ``sampleRate``.
    ///
    /// Pipelined across chunks: mel extraction (CPU), encoder (ANE / GPU /
    /// CPU depending on ``computeUnits``), and the greedy decode loop (CPU)
    /// each run on their own pthread, connected by two semaphore-gated
    /// ring buffers. The pipeline stall is bounded by the slowest stage,
    /// not the sum of stages, so on ANE it cuts wall time by ~37% and on
    /// GPU by ~50%.
    ///
    /// Call sites don't have to care: it's still a plain synchronous
    /// throwing method.
    public func transcribe(samples: [Float]) throws -> Transcription {
        let audioDuration = Double(samples.count) / Double(sampleRate)

        // Parakeet's encoder needs a minimum audio context; below ~5 s it can
        // return empty text or hallucinate a tail (upstream issue #1). Pad
        // with trailing silence so the shortest dictations still transcribe.
        // The reported audio duration stays the real one.
        let padded = Self.padToMinDuration(
            samples, minSeconds: Self.minAudioSeconds, sampleRate: sampleRate
        )

        let chunkSamples = chunkMelFrames * featureExtractor.hopLength

        // --- Slice audio into fixed-length chunks up front ---
        var chunks: [[Float]] = []
        do {
            var cursor = 0
            while cursor < padded.count {
                let end = min(cursor + chunkSamples, padded.count)
                var chunk = Array(padded[cursor..<end])
                if chunk.count < chunkSamples {
                    chunk.append(
                        contentsOf: [Float](repeating: 0, count: chunkSamples - chunk.count)
                    )
                }
                chunks.append(chunk)
                cursor += chunkSamples
            }
        }

        let start = Date()
        let result = try Pipeline.run(
            chunks: chunks,
            featureExtractor: featureExtractor,
            runner: runner
        )
        let elapsed = Date().timeIntervalSince(start)

        let tDetok = Date()
        let text = tokenizer.decode(result.tokens, skipSpecial: true)
        let detokElapsed = Date().timeIntervalSince(tDetok)

        return Transcription(
            text: text,
            tokenIds: result.tokens,
            frameIndices: result.frames,
            durations: result.durations,
            audioDurationSeconds: audioDuration,
            inferenceDurationSeconds: elapsed,
            timing: TranscriptionTiming(
                melExtract: result.melElapsed,
                encoder: result.encoderElapsed,
                decoderLoop: result.decodeElapsed,
                detokenize: detokElapsed
            )
        )
    }

    // MARK: - Helpers

    /// Minimum audio context the encoder needs to produce text instead of an
    /// empty result or a hallucinated tail on short clips.
    private static let minAudioSeconds = 5.0
    /// Short silent lead-in before the speech so the encoder is warm before
    /// the first syllable (fixes the first words being cut off).
    private static let leadInSeconds = 0.5

    /// Pads a short clip with silence so it reaches at least `minSeconds`:
    /// a short lead-in on the left (encoder warm-up) and silence on the right
    /// (avoids a hallucinated tail). Longer audio passes through untouched.
    private static func padToMinDuration(
        _ samples: [Float],
        minSeconds: Double,
        sampleRate: Int
    ) -> [Float] {
        let minSamples = Int(minSeconds * Double(sampleRate))
        guard samples.count < minSamples else { return samples }

        let leadCount = Int(leadInSeconds * Double(sampleRate))
        let lead = [Float](repeating: 0, count: leadCount)
        var padded = lead + samples
        if padded.count < minSamples {
            padded += [Float](repeating: 0, count: minSamples - padded.count)
        }
        return padded
    }

    /// Resolve the compiled `.mlmodelc` for `named`, compiling the source
    /// `.mlpackage` when present. When `deleteSourceAfterCompile` removed the
    /// sources, reuse the compiled bundle that's already in the cache.
    private static func resolveOrCached(
        modelsRoot: URL,
        cache: ModelCache,
        named: String
    ) throws -> URL {
        if let source = try? resolveModel(under: modelsRoot, named: named) {
            return try cache.compiledURL(for: source)
        }
        if let cached = cache.compiledModelURL(named: named) {
            return cached
        }
        throw ParakeetError.modelNotFound(
            url: modelsRoot.appendingPathComponent("\(named).mlpackage")
        )
    }

    /// Look for ``<name>.mlmodelc`` (preferred; already compiled) then
    /// ``<name>.mlpackage`` inside ``modelsRoot``.
    private static func resolveModel(
        under root: URL, named: String
    ) throws -> URL {
        let candidates = [
            root.appendingPathComponent("\(named).mlmodelc"),
            root.appendingPathComponent("\(named).mlpackage"),
        ]
        for url in candidates {
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        throw ParakeetError.modelNotFound(url: candidates[1])
    }

    /// Sniff the decoder's ``hidden`` input shape to figure out the LSTM's
    /// (num_layers, hidden_size). The spec records it as the symbolic
    /// shape ``[num_layers, 1, hidden]``.
    private static func readDecoderStateShape(
        from model: MLModel
    ) -> (layers: Int, hidden: Int) {
        if let desc = model.modelDescription.inputDescriptionsByName["hidden"],
           let con = desc.multiArrayConstraint
        {
            let shape = con.shape.map(\.intValue)
            if shape.count == 3 {
                return (shape[0], shape[2])
            }
        }
        return (2, 640)  // Parakeet TDT 0.6B defaults.
    }

    /// Cache directory where compiled `.mlmodelc`s live. Exposed so callers
    /// can clear it if they want to force a recompile or free disk.
    public var compiledCacheDirectory: URL { cacheURL }

    // MARK: - HuggingFace convenience

    /// Download the default model from HuggingFace (or `repoId` if
    /// supplied) on first call, then construct a fully-ready
    /// ``ParakeetTranscriber``. Subsequent calls hit the on-disk cache
    /// and skip the download.
    ///
    /// The downloaded `.mlpackage`s live under
    /// ``ModelDownloader.defaultCacheDirectory()``; the compiled
    /// `.mlmodelc`s live under ``ModelCache.defaultCacheDirectory()``.
    /// Both persist across launches.
    public static func fromHuggingFace(
        repoId: String = defaultRepoId,
        branch: String = "main",
        computeUnits: ParakeetComputeUnits = .ane,
        chunkMelFrames: Int = 3000,
        sampleRate: Int = 16_000,
        decoderWorkers: Int? = nil,
        progress: ModelDownloader.ProgressHandler? = nil
    ) async throws -> ParakeetTranscriber {
        let downloader = ModelDownloader()
        let modelsRoot = try await downloader.download(
            repoId: repoId,
            branch: branch,
            progress: progress
        )
        return try ParakeetTranscriber(
            modelsRoot: modelsRoot,
            computeUnits: computeUnits,
            chunkMelFrames: chunkMelFrames,
            sampleRate: sampleRate,
            decoderWorkers: decoderWorkers
        )
    }
}
