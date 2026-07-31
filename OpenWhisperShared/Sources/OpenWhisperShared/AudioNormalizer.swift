import Foundation

public enum AudioNormalizer {
    public static let targetRMS: Float = 0.1
    public static let maximumGain: Float = 20
    public static let minimumGain: Float = 1
    public static let minimumInputRMS: Float = 0.0001

    public static func process(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return samples }
        let inputRMS = rms(samples)
        guard inputRMS > minimumInputRMS else { return samples }
        let gain = min(max(targetRMS / inputRMS, minimumGain), maximumGain)
        guard gain > 1 else { return samples }
        return samples.map { max(-1, min(1, $0 * gain)) }
    }

    private static func rms(_ samples: [Float]) -> Float {
        var sum: Double = 0
        for sample in samples {
            sum += Double(sample) * Double(sample)
        }
        return Float(sqrt(sum / Double(samples.count)))
    }
}
