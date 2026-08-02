import Foundation

/// Applies tail-silence padding before transcription so the recognizer gets a
/// stable signal edge. Short clips are padded to a minimum duration; longer
/// clips always get a short trailing tail.
public enum SilencePadder {
    /// Sample rate the recorder emits (16 kHz mono).
    public static let sampleRate: Int = 16_000

    /// Clips shorter than this are padded up to this total duration.
    public static let minimumDurationSeconds: Double = 0.75

    /// Tail silence appended to clips at or above the minimum duration.
    public static let tailPaddingSeconds: Double = 0.3

    public static func pad(_ samples: [Float], rawDuration: TimeInterval? = nil) -> [Float] {
        let duration = rawDuration ?? TimeInterval(samples.count) / Double(sampleRate)
        var padded = samples

        if duration < minimumDurationSeconds {
            let targetCount = Int(minimumDurationSeconds * Double(sampleRate))
            let padCount = max(0, targetCount - samples.count)
            padded.append(contentsOf: [Float](repeating: 0, count: padCount))
        } else {
            let tailCount = Int(tailPaddingSeconds * Double(sampleRate))
            padded.append(contentsOf: [Float](repeating: 0, count: tailCount))
        }

        return padded
    }
}
