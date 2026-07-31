import Foundation

public struct TranscriptionResult: Sendable {
    public let text: String
    public let audioDuration: TimeInterval
    public let confidence: Float

    public init(text: String, audioDuration: TimeInterval, confidence: Float = 0) {
        self.text = text
        self.audioDuration = audioDuration
        self.confidence = confidence
    }
}

public enum TranscriptionError: LocalizedError {
    case busy
    case modelUnavailable
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .busy:
            return "A transcription is already in progress."
        case .modelUnavailable:
            return "The speech model isn't downloaded yet."
        case .failed(let message):
            return message
        }
    }
}
