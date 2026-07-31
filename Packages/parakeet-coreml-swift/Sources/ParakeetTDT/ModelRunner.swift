import CoreML
import Foundation

/// Top-level container for the three Parakeet submodules plus a pool of
/// :class:`DecoderWorker` instances for parallel decoding.
///
/// The encoder has a single set of reusable input buffers (we only have
/// one encoder running at a time -- it's driven by the pipeline's
/// serial stage-2 queue). The decoder + joint each have N workers, one
/// per concurrent decode thread; the pipeline's stage-3 worker pool
/// borrows / returns workers from this pool via ``acquireWorker`` /
/// ``releaseWorker``.
public final class ModelRunner {
    private let encoder: MLModel
    private let decoder: MLModel
    private let joint: MLModel

    public struct EncoderShapes {
        public let batch: Int       // 1
        public let maxTime: Int     // 3000 mel frames (traced)
        public let numMelBins: Int  // 128
    }

    public let encoderShapes: EncoderShapes
    public let decoderHiddenLayers: Int
    public let decoderHiddenSize: Int
    public let blankTokenId: Int
    public let durations: [Int]
    public let vocabSize: Int
    public let maxSymbolsPerStep: Int

    // MARK: - Encoder inputs (single-instance)

    public let encoderFeatures: MLMultiArray
    public let encoderMask: MLMultiArray
    let encoderInputs: FeatureBag
    let predictionOptions = MLPredictionOptions()

    // MARK: - Decoder worker pool

    public let decoderWorkers: [DecoderWorker]

    /// Underlying pool: consumers take a worker to run one chunk's decode
    /// loop, then return it.
    private let workerPool: BlockingWorkerPool

    public init(
        encoder: MLModel,
        decoder: MLModel,
        joint: MLModel,
        encoderShapes: EncoderShapes,
        decoderHiddenLayers: Int,
        decoderHiddenSize: Int,
        blankTokenId: Int,
        durations: [Int],
        vocabSize: Int,
        maxSymbolsPerStep: Int,
        numDecoderWorkers: Int = 2
    ) throws {
        self.encoder = encoder
        self.decoder = decoder
        self.joint = joint
        self.encoderShapes = encoderShapes
        self.decoderHiddenLayers = decoderHiddenLayers
        self.decoderHiddenSize = decoderHiddenSize
        self.blankTokenId = blankTokenId
        self.durations = durations
        self.vocabSize = vocabSize
        self.maxSymbolsPerStep = maxSymbolsPerStep

        // --- Encoder inputs ---
        self.encoderFeatures = try MLMultiArray(
            shape: [
                NSNumber(value: 1),
                NSNumber(value: encoderShapes.maxTime),
                NSNumber(value: encoderShapes.numMelBins),
            ],
            dataType: .float32
        )
        self.encoderMask = try MLMultiArray(
            shape: [NSNumber(value: 1), NSNumber(value: encoderShapes.maxTime)],
            dataType: .int32
        )
        self.encoderInputs = FeatureBag([
            "input_features": MLFeatureValue(multiArray: encoderFeatures),
            "attention_mask": MLFeatureValue(multiArray: encoderMask),
        ])

        // --- Decoder worker pool ---
        let workerCount = max(1, numDecoderWorkers)
        var workers = [DecoderWorker]()
        workers.reserveCapacity(workerCount)
        for _ in 0..<workerCount {
            workers.append(
                try DecoderWorker(
                    decoder: decoder,
                    joint: joint,
                    decoderHiddenLayers: decoderHiddenLayers,
                    decoderHiddenSize: decoderHiddenSize
                )
            )
        }
        self.decoderWorkers = workers
        self.workerPool = BlockingWorkerPool(workers: workers)
    }

    // MARK: - Encoder

    /// Write mel features + mask into the reused input buffers, run the
    /// encoder, return the output `encoder_hidden` / `encoder_mask` arrays.
    public func runEncoder(
        features: [[Float]],
        mask: [Int32]
    ) throws -> (hidden: MLMultiArray, mask: MLMultiArray) {
        let t = encoderShapes.maxTime
        let m = encoderShapes.numMelBins

        let fPtr = encoderFeatures.dataPointer
            .bindMemory(to: Float32.self, capacity: t * m)
        memset(fPtr, 0, t * m * MemoryLayout<Float32>.size)
        let copyT = min(features.count, t)
        for ti in 0..<copyT {
            let row = features[ti]
            let copyM = min(row.count, m)
            row.withUnsafeBufferPointer { src in
                memcpy(
                    fPtr.advanced(by: ti * m),
                    src.baseAddress!,
                    copyM * MemoryLayout<Float32>.size
                )
            }
        }

        let mPtr = encoderMask.dataPointer
            .bindMemory(to: Int32.self, capacity: t)
        memset(mPtr, 0, t * MemoryLayout<Int32>.size)
        for ti in 0..<min(mask.count, t) { mPtr[ti] = mask[ti] }

        let out = try encoder.prediction(
            from: encoderInputs, options: predictionOptions
        )
        guard let hidden = out.featureValue(for: "encoder_hidden")?.multiArrayValue
        else { throw ParakeetError.missingOutput(name: "encoder_hidden") }
        guard let outMask = out.featureValue(for: "encoder_mask")?.multiArrayValue
        else { throw ParakeetError.missingOutput(name: "encoder_mask") }
        return (hidden, outMask)
    }

    // MARK: - Decoder worker pool

    /// Acquire (blocking) a decoder worker. Returns nil if the pool has
    /// been shut down. Release with ``releaseWorker`` when the decode
    /// loop for a chunk finishes.
    public func acquireWorker() -> DecoderWorker? {
        workerPool.acquire()
    }

    public func releaseWorker(_ worker: DecoderWorker) {
        workerPool.release(worker)
    }
}

/// Fixed-size pool with blocking acquire semantics. Straight `NSLock` +
/// `DispatchSemaphore`, no `async` required.
final class BlockingWorkerPool: @unchecked Sendable {
    private var available: [DecoderWorker]
    private let lock = NSLock()
    private let semaphore: DispatchSemaphore
    private var closed = false

    init(workers: [DecoderWorker]) {
        available = workers
        semaphore = DispatchSemaphore(value: workers.count)
    }

    func acquire() -> DecoderWorker? {
        semaphore.wait()
        lock.lock()
        if closed || available.isEmpty {
            lock.unlock()
            semaphore.signal()
            return nil
        }
        let w = available.removeLast()
        lock.unlock()
        return w
    }

    func release(_ worker: DecoderWorker) {
        lock.lock()
        available.append(worker)
        lock.unlock()
        semaphore.signal()
    }
}
