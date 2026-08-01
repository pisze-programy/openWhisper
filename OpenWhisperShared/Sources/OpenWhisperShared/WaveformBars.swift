import CoreGraphics
import Foundation

public enum WaveformBars {
    public static func bars(from samples: [Float], count: Int = 28) -> [CGFloat] {
        let minHeight: CGFloat = 4
        let maxHeight: CGFloat = 42
        guard samples.count > count * 64 else {
            return Array(repeating: minHeight, count: count)
        }
        let window = min(samples.count, 9_600)
        let start = samples.count - window
        let segmentLength = max(window / count, 1)
        var result = [CGFloat]()
        result.reserveCapacity(count)
        for i in 0..<count {
            let segmentStart = start + i * segmentLength
            var peak: Float = 0
            for j in 0..<segmentLength {
                let s = abs(samples[segmentStart + j])
                if s > peak { peak = s }
            }
            let normalized = min(CGFloat(peak) / 0.3, 1)
            let height = maxHeight * pow(normalized, 0.65)
            result.append(max(height, minHeight))
        }
        return result
    }
}
