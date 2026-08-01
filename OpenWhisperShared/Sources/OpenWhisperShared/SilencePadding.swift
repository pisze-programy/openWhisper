import Foundation

/// Mirrors `ParakeetTranscriber.prepareAudio`: short silent lead-in, trailing
/// silence, and a minimum total length. Applied before sending a clip to the
/// cloud STT provider — the same padding measurably improved local quality.
public enum SilencePadding {
    public static let leadInSeconds: Double = 0.5
    public static let trailingPadSeconds: Double = 1.5
    public static let minAudioSeconds: Double = 5.0

    public static func pad(_ samples: [Float], sampleRate: Int) -> [Float] {
        guard sampleRate > 0 else { return samples }
        let lead = [Float](repeating: 0, count: Int(leadInSeconds * Double(sampleRate)))
        let trail = [Float](repeating: 0, count: Int(trailingPadSeconds * Double(sampleRate)))
        var padded = lead + samples + trail
        let minSamples = Int(minAudioSeconds * Double(sampleRate))
        if padded.count < minSamples {
            padded += [Float](repeating: 0, count: minSamples - padded.count)
        }
        return padded
    }
}
