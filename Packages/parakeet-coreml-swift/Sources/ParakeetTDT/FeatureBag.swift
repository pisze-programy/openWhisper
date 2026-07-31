import CoreML
import Foundation

/// Tiny `MLFeatureProvider` with a fixed set of feature names. Built once
/// per submodule and handed to ``MLModel.prediction(from:)`` every step --
/// avoids the per-call dictionary + Swift-to-NSDictionary bridging cost of
/// using ``MLDictionaryFeatureProvider(dictionary:)`` in a tight loop.
///
/// The wrapped ``MLFeatureValue``s themselves are also cached; as long as
/// their backing ``MLMultiArray``s are reused across calls (we overwrite
/// their buffers in place), the ``MLFeatureValue`` stays valid.
final class FeatureBag: MLFeatureProvider {
    private var values: [String: MLFeatureValue]
    private let names: Set<String>

    var featureNames: Set<String> { names }

    init(_ values: [String: MLFeatureValue]) {
        self.values = values
        self.names = Set(values.keys)
    }

    /// Replace a feature value without allocating a new Swift dictionary.
    /// Callers set this once per submodule (typically during construction)
    /// and don't touch it per-step after that.
    func set(_ name: String, _ value: MLFeatureValue) {
        values[name] = value
    }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        values[featureName]
    }
}
