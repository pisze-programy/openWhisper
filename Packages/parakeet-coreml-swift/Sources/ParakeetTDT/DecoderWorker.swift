import CoreML
import Foundation

/// Self-contained decode context: the decoder + joint MLModels (shared
/// between workers, `MLModel.prediction(from:)` is thread-safe) plus a
/// private set of input buffers and pre-built ``FeatureBag``s.
///
/// We instantiate N of these behind ``ModelRunner`` so the pipeline's
/// decode stage can process multiple chunks concurrently without buffer
/// aliasing. With decoder + joint being small CPU-resident models, the
/// dominant cost per step is Core ML's per-prediction dispatch, so
/// running two workers in parallel essentially halves decode wall time
/// on GPU builds where the encoder isn't the bottleneck.
public final class DecoderWorker {
    public let decoder: MLModel
    public let joint: MLModel

    public let inputIds: MLMultiArray
    public let hidden: MLMultiArray
    public let cell: MLMultiArray
    public let encoderFrame: MLMultiArray
    public let decoderState: MLMultiArray

    let decoderInputs: FeatureBag
    let jointInputs: FeatureBag
    let predictionOptions = MLPredictionOptions()

    public let decoderHiddenLayers: Int
    public let decoderHiddenSize: Int

    public init(
        decoder: MLModel,
        joint: MLModel,
        decoderHiddenLayers: Int,
        decoderHiddenSize: Int
    ) throws {
        self.decoder = decoder
        self.joint = joint
        self.decoderHiddenLayers = decoderHiddenLayers
        self.decoderHiddenSize = decoderHiddenSize

        self.inputIds = try MLMultiArray(shape: [1, 1], dataType: .int32)
        self.hidden = try MLMultiArray(
            shape: [
                NSNumber(value: decoderHiddenLayers), 1,
                NSNumber(value: decoderHiddenSize),
            ],
            dataType: .float32
        )
        self.cell = try MLMultiArray(
            shape: [
                NSNumber(value: decoderHiddenLayers), 1,
                NSNumber(value: decoderHiddenSize),
            ],
            dataType: .float32
        )
        self.encoderFrame = try MLMultiArray(
            shape: [1, NSNumber(value: decoderHiddenSize)],
            dataType: .float32
        )
        self.decoderState = try MLMultiArray(
            shape: [1, NSNumber(value: decoderHiddenSize)],
            dataType: .float32
        )

        self.decoderInputs = FeatureBag([
            "input_ids": MLFeatureValue(multiArray: inputIds),
            "hidden": MLFeatureValue(multiArray: hidden),
            "cell": MLFeatureValue(multiArray: cell),
        ])
        self.jointInputs = FeatureBag([
            "encoder_frame": MLFeatureValue(multiArray: encoderFrame),
            "decoder_state": MLFeatureValue(multiArray: decoderState),
        ])
    }

    public func runDecoderStep() throws -> (
        decoderHidden: MLMultiArray,
        nextHidden: MLMultiArray,
        nextCell: MLMultiArray
    ) {
        let out = try decoder.prediction(
            from: decoderInputs, options: predictionOptions
        )
        guard let dh = out.featureValue(for: "decoder_hidden")?.multiArrayValue
        else { throw ParakeetError.missingOutput(name: "decoder_hidden") }
        guard let nh = out.featureValue(for: "next_hidden")?.multiArrayValue
        else { throw ParakeetError.missingOutput(name: "next_hidden") }
        guard let nc = out.featureValue(for: "next_cell")?.multiArrayValue
        else { throw ParakeetError.missingOutput(name: "next_cell") }
        return (dh, nh, nc)
    }

    public func runJoint() throws -> (
        tokenLogits: MLMultiArray,
        durationLogits: MLMultiArray
    ) {
        let out = try joint.prediction(
            from: jointInputs, options: predictionOptions
        )
        guard let tl = out.featureValue(for: "token_logits")?.multiArrayValue
        else { throw ParakeetError.missingOutput(name: "token_logits") }
        guard let dl = out.featureValue(for: "duration_logits")?.multiArrayValue
        else { throw ParakeetError.missingOutput(name: "duration_logits") }
        return (tl, dl)
    }
}
