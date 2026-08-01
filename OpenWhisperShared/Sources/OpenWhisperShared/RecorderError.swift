import Foundation

public enum RecorderError: LocalizedError {
    case permissionDenied
    case formatUnavailable
    case noRecording
    case alreadyRecording

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone access was denied. Enable it in Settings."
        case .formatUnavailable:
            return "Couldn't set up the recording format."
        case .noRecording:
            return "There is no recording to stop."
        case .alreadyRecording:
            return "A recording is already in progress."
        }
    }
}
