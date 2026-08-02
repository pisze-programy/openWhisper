import Foundation

/// Classifies a finished recording as "worth transcribing" or "discard". Uses
/// duration and peak input level so accidental ultra-short taps and pure silence
/// are dropped instead of producing empty or garbage transcriptions.
public enum ShortSpeechClassifier {

    /// Verdict for a finished recording.
    public enum Decision: Equatable {
        case discardTooShort
        case discardNoSpeech
        case transcribe
    }

    /// Recordings shorter than this are always discarded.
    public static let minimumDurationSeconds: TimeInterval = 0.04

    /// Peak RMS below this for sub-second clips counts as no speech.
    public static let shortClipPeakThreshold: Float = 0.003

    /// Peak RMS below this for clips >= 1 s counts as no speech.
    public static let longClipPeakThreshold: Float = 0.006

    public static func classify(
        rawDuration: TimeInterval,
        peakLevel: Float,
        hasConfirmedText: Bool,
        transcribeShortQuietClipsAggressively: Bool = true
    ) -> Decision {
        guard rawDuration >= minimumDurationSeconds else { return .discardTooShort }
        if hasConfirmedText { return .transcribe }

        if rawDuration < 1.0 {
            if peakLevel < shortClipPeakThreshold {
                // Bias toward transcription: dropping a real utterance is worse
                // than letting the recognizer return empty text for silence.
                return transcribeShortQuietClipsAggressively ? .transcribe : .discardNoSpeech
            }
            return .transcribe
        }

        if peakLevel < longClipPeakThreshold { return .discardNoSpeech }
        return .transcribe
    }
}
