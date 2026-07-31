import Foundation

public struct TranscriptionResult: Sendable {
    let text: String
    let audioDuration: TimeInterval
}

enum TranscriptionError: LocalizedError {
    case busy
    case modelUnavailable
    case failed(String)

    var errorDescription: String? {
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
