import Accelerate
import CoreML
import Foundation

/// Greedy TDT (Token-and-Duration Transducer) decoder.
///
/// Ports the Python ``greedy_tdt_decode`` loop line-for-line:
///   - Maintain two LSTM state tensors (``hidden``, ``cell``) plus the last
///     emitted token in a single persistent set of ``MLMultiArray``s owned
///     by the runner.
///   - For each encoder frame ``t``:
///     - Call decoder once (or reuse cached ``decoder_hidden`` if we just
///       emitted blank).
///     - Call joint(encoder[t], decoder_state).
///     - Argmax over token logits; argmax over duration logits.
///     - If token is blank: advance ``t`` by ``max(duration, 1)``.
///     - Otherwise: emit token, advance ``t`` by ``duration`` if > 0, else
///       keep ``t`` and try again (capped by ``maxSymbolsPerStep``).
public enum GreedyTDTDecoder {

    public struct Output {
        public let tokenIds: [Int]
        public let frameIndices: [Int]
        public let durations: [Int]
        /// Wall-clock time spent inside ``runner.runDecoderStep()`` +
        /// ``runner.runJoint()`` plus the argmax + state copies.
        public let elapsedSeconds: Double
    }

    public static func decode(
        encoderHidden: MLMultiArray,
        encoderMask: MLMultiArray,
        worker: DecoderWorker,
        blankTokenId: Int,
        durations: [Int],
        maxSymbolsPerStep: Int
    ) throws -> Output {
        guard encoderHidden.shape.count == 3 else {
            throw ParakeetError.unexpectedOutputShape(
                name: "encoder_hidden",
                got: encoderHidden.shape.map(\.intValue),
                expected: "[1, T, hidden]"
            )
        }
        let hiddenSize = encoderHidden.shape[2].intValue
        let tMax = encoderHidden.shape[1].intValue

        let maskPtr = encoderMask.dataPointer.bindMemory(
            to: Int32.self, capacity: encoderMask.count
        )
        var validFrames = 0
        for i in 0..<encoderMask.shape.last!.intValue {
            validFrames += Int(maskPtr[i])
        }
        validFrames = min(validFrames, tMax)

        let blank = blankTokenId
        let maxSym = maxSymbolsPerStep

        // Persistent buffers owned by the worker. Zero hidden/cell for a
        // fresh utterance; input_ids starts at blank.
        let hidden = worker.hidden
        let cell = worker.cell
        let inputIds = worker.inputIds
        let jointEncFrame = worker.encoderFrame
        let jointDecState = worker.decoderState
        zero(hidden)
        zero(cell)
        let idsPtr = inputIds.dataPointer
            .bindMemory(to: Int32.self, capacity: 1)
        idsPtr[0] = Int32(blank)

        let encFramePtr = jointEncFrame.dataPointer
            .bindMemory(to: Float32.self, capacity: hiddenSize)
        let decStatePtr = jointDecState.dataPointer
            .bindMemory(to: Float32.self, capacity: hiddenSize)
        let encHiddenPtr = encoderHidden.dataPointer
            .bindMemory(to: Float32.self, capacity: encoderHidden.count)

        var tokens = [Int]()
        var frameIdx = [Int]()
        var durationOut = [Int]()

        /// True once we've written a valid ``decoder_hidden[:, -1, :]``
        /// slice into the joint's persistent ``decoder_state`` buffer. If
        /// the last emitted token was blank, we can skip rerunning the
        /// decoder since the state hasn't changed.
        var decoderStateValid = false

        let start = Date()
        var t = 0
        while t < validFrames {
            // Copy encoder_hidden[0, t, :] into the joint's encoder_frame.
            memcpy(
                encFramePtr,
                encHiddenPtr.advanced(by: t * hiddenSize),
                hiddenSize * MemoryLayout<Float32>.size
            )

            var symbols = 0
            var advanced = false
            while symbols < maxSym {
                if !decoderStateValid || idsPtr[0] != Int32(blank) {
                    // Scoped so the prediction output (IOSurface-backed on
                    // ANE / GPU) is released before the next iteration.
                    try autoreleasepool {
                        let out = try worker.runDecoderStep()
                        let decShape = out.decoderHidden.shape.map(\.intValue)
                        let decU = decShape.count >= 3
                            ? decShape[decShape.count - 2] : 1
                        let lastT = decU - 1
                        let outPtr = out.decoderHidden.dataPointer.bindMemory(
                            to: Float32.self, capacity: out.decoderHidden.count
                        )
                        memcpy(
                            decStatePtr,
                            outPtr.advanced(by: lastT * hiddenSize),
                            hiddenSize * MemoryLayout<Float32>.size
                        )
                        copyMultiArray(from: out.nextHidden, to: hidden)
                        copyMultiArray(from: out.nextCell, to: cell)
                    }
                    decoderStateValid = true
                }

                // Joint: also autoreleasepool'd so the IOSurface output is
                // returned to the pool before we loop.
                let (tokenId, durIdx): (Int, Int) = try autoreleasepool {
                    let jointOut = try worker.runJoint()
                    return (
                        argmax(jointOut.tokenLogits),
                        argmax(jointOut.durationLogits)
                    )
                }
                let duration = durations[durIdx]

                if tokenId == blank {
                    t += max(duration, 1)
                    advanced = true
                    break
                }

                tokens.append(tokenId)
                frameIdx.append(t)
                durationOut.append(duration)
                idsPtr[0] = Int32(tokenId)
                symbols += 1
                if duration > 0 {
                    t += duration
                    advanced = true
                    break
                }
            }
            if !advanced { t += 1 }
        }
        let elapsed = Date().timeIntervalSince(start)

        return Output(
            tokenIds: tokens,
            frameIndices: frameIdx,
            durations: durationOut,
            elapsedSeconds: elapsed
        )
    }

    // MARK: - helpers

    @inline(__always)
    static func zero(_ arr: MLMultiArray) {
        let count = arr.count
        memset(arr.dataPointer, 0, count * MemoryLayout<Float32>.size)
    }

    @inline(__always)
    static func copyMultiArray(from src: MLMultiArray, to dst: MLMultiArray) {
        let bytes = min(src.count, dst.count) * MemoryLayout<Float32>.size
        memcpy(dst.dataPointer, src.dataPointer, bytes)
    }

    @inline(__always)
    static func argmax(_ array: MLMultiArray) -> Int {
        let n = vDSP_Length(array.count)
        let ptr = UnsafePointer<Float32>(OpaquePointer(array.dataPointer))
        var maxVal: Float = 0
        var idx: vDSP_Length = 0
        vDSP_maxvi(ptr, 1, &maxVal, &idx, n)
        return Int(idx)
    }
}
