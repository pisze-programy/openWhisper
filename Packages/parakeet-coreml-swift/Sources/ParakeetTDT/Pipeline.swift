import CoreML
import Dispatch
import Foundation

/// Pipelined long-form transcription.
///
/// Three stages connected by bounded blocking queues:
///
/// 1. **mel extraction** (CPU, `vDSP`).
/// 2. **encoder** (ANE / GPU / CPU depending on ``computeUnits``).
/// 3. **greedy TDT decode** (CPU, LSTM + joint) -- runs in a worker pool
///    of N :class:`DecoderWorker`s so the encoder isn't the only thing
///    waiting on a single CPU decode loop.
///
/// With default settings (2 decode workers) the GPU build is
/// encoder-bound; the ANE build is also encoder-bound; the CPU build is
/// encoder-bound by a wide margin. In all three cases, wall clock
/// collapses to roughly ``max(stage_time) * num_chunks``.
enum Pipeline {

    struct Result {
        var tokens: [Int]
        var frames: [Int]
        var durations: [Int]
        var melElapsed: Double
        var encoderElapsed: Double
        var decodeElapsed: Double
    }

    static func run(
        chunks: [[Float]],
        featureExtractor: MelFeatureExtractor,
        runner: ModelRunner
    ) throws -> Result {
        if chunks.isEmpty {
            return Result(
                tokens: [], frames: [], durations: [],
                melElapsed: 0, encoderElapsed: 0, decodeElapsed: 0
            )
        }

        let melQueue = BlockingQueue<MelItem>(capacity: 2)
        let encQueue = BlockingQueue<EncoderItem>(
            capacity: max(2, runner.decoderWorkers.count + 1)
        )

        let globalError = ErrorSlot()

        // --- Stage 1: CPU mel extraction ---
        let melQ = DispatchQueue(label: "parakeet.mel", qos: .userInitiated)
        let melTotal = AtomicDouble()
        melQ.async {
            for (i, chunk) in chunks.enumerated() {
                if globalError.hasError { break }
                let t0 = Date()
                let features = featureExtractor.extract(from: chunk)
                melTotal.add(Date().timeIntervalSince(t0))
                melQueue.put(MelItem(index: i, features: features))
            }
            melQueue.close()
        }

        // --- Stage 2: ANE / GPU / CPU encoder ---
        let encQ = DispatchQueue(label: "parakeet.encoder", qos: .userInitiated)
        let encTotal = AtomicDouble()
        encQ.async {
            while let mel = melQueue.take() {
                if globalError.hasError { break }
                do {
                    let t0 = Date()
                    let (hidden, mask) = try runner.runEncoder(
                        features: mel.features.mel,
                        mask: mel.features.attentionMask
                    )
                    encTotal.add(Date().timeIntervalSince(t0))
                    encQueue.put(
                        EncoderItem(index: mel.index, hidden: hidden, mask: mask)
                    )
                } catch {
                    globalError.set(error)
                    break
                }
            }
            encQueue.close()
        }

        // --- Stage 3: CPU decode worker pool ---
        let decodeQ = DispatchQueue(
            label: "parakeet.decode",
            qos: .userInitiated,
            attributes: .concurrent
        )
        let group = DispatchGroup()
        let decodeTotal = AtomicDouble()
        let results = ChunkResultAccumulator()

        while let item = encQueue.take() {
            if globalError.hasError { break }
            guard let worker = runner.acquireWorker() else { break }

            group.enter()
            decodeQ.async {
                defer {
                    runner.releaseWorker(worker)
                    group.leave()
                }
                do {
                    let decoded = try autoreleasepool {
                        try GreedyTDTDecoder.decode(
                            encoderHidden: item.hidden,
                            encoderMask: item.mask,
                            worker: worker,
                            blankTokenId: runner.blankTokenId,
                            durations: runner.durations,
                            maxSymbolsPerStep: runner.maxSymbolsPerStep
                        )
                    }
                    decodeTotal.add(decoded.elapsedSeconds)
                    results.set(
                        index: item.index,
                        chunk: ChunkResult(
                            tokenIds: decoded.tokenIds,
                            frameIndices: decoded.frameIndices,
                            durations: decoded.durations,
                            encoderFrames: item.hidden.shape[1].intValue
                        )
                    )
                } catch {
                    globalError.set(error)
                }
            }
        }

        group.wait()
        melQueue.close()
        encQueue.close()

        if let err = globalError.error {
            throw err
        }

        // Reassemble tokens in chunk order -- the worker pool completes
        // chunks out of order.
        var tokens = [Int]()
        var frames = [Int]()
        var durations = [Int]()
        var totalFrameOffset = 0
        for chunk in results.ordered(count: chunks.count) {
            tokens.append(contentsOf: chunk.tokenIds)
            frames.append(
                contentsOf: chunk.frameIndices.map { $0 + totalFrameOffset }
            )
            durations.append(contentsOf: chunk.durations)
            totalFrameOffset += chunk.encoderFrames
        }

        return Result(
            tokens: tokens,
            frames: frames,
            durations: durations,
            melElapsed: melTotal.value,
            encoderElapsed: encTotal.value,
            decodeElapsed: decodeTotal.value
        )
    }
}

// MARK: - Helpers

private struct MelItem {
    let index: Int
    let features: MelFeatureExtractor.Features
}

private struct EncoderItem {
    let index: Int
    let hidden: MLMultiArray
    let mask: MLMultiArray
}

private struct ChunkResult {
    let tokenIds: [Int]
    let frameIndices: [Int]
    let durations: [Int]
    let encoderFrames: Int
}

/// Capacity-bounded MPSC blocking queue.
private final class BlockingQueue<T>: @unchecked Sendable {
    private var buffer: [T] = []
    private var closed = false
    private let lock = NSLock()
    private let freeSlots: DispatchSemaphore
    private let itemsAvailable = DispatchSemaphore(value: 0)

    init(capacity: Int) {
        freeSlots = DispatchSemaphore(value: capacity)
    }

    func put(_ value: T) {
        freeSlots.wait()
        lock.lock()
        if closed {
            lock.unlock()
            freeSlots.signal()
            return
        }
        buffer.append(value)
        lock.unlock()
        itemsAvailable.signal()
    }

    func take() -> T? {
        itemsAvailable.wait()
        lock.lock()
        if buffer.isEmpty {
            lock.unlock()
            itemsAvailable.signal()
            return nil
        }
        let value = buffer.removeFirst()
        lock.unlock()
        freeSlots.signal()
        return value
    }

    func close() {
        lock.lock()
        let wasClosed = closed
        closed = true
        lock.unlock()
        if !wasClosed {
            itemsAvailable.signal()
            freeSlots.signal()
        }
    }
}

/// Chunk results land out of order because the decode worker pool runs
/// multiple chunks concurrently. This collects them into a dict keyed on
/// chunk index and hands back an ordered sequence at the end.
private final class ChunkResultAccumulator: @unchecked Sendable {
    private var map: [Int: ChunkResult] = [:]
    private let lock = NSLock()

    func set(index: Int, chunk: ChunkResult) {
        lock.lock()
        map[index] = chunk
        lock.unlock()
    }

    func ordered(count: Int) -> [ChunkResult] {
        lock.lock(); defer { lock.unlock() }
        var out = [ChunkResult]()
        out.reserveCapacity(count)
        for i in 0..<count {
            if let r = map[i] { out.append(r) }
        }
        return out
    }
}

private final class ErrorSlot: @unchecked Sendable {
    private var _error: Error?
    private let lock = NSLock()

    var error: Error? {
        lock.lock(); defer { lock.unlock() }
        return _error
    }
    var hasError: Bool {
        lock.lock(); defer { lock.unlock() }
        return _error != nil
    }
    func set(_ err: Error) {
        lock.lock(); defer { lock.unlock() }
        if _error == nil { _error = err }
    }
}

private final class AtomicDouble: @unchecked Sendable {
    private var _value: Double = 0
    private let lock = NSLock()
    var value: Double {
        lock.lock(); defer { lock.unlock() }
        return _value
    }
    func add(_ d: Double) {
        lock.lock(); defer { lock.unlock() }
        _value += d
    }
}
