import Foundation
import SwiftData

/// A persisted transcription shown in the history list.
@Model
final class TranscriptionItem {
    var id: UUID
    var text: String
    var createdAt: Date
    var duration: TimeInterval
    var source: String   // "mic" for now; later "keyboard" etc.

    init(text: String, duration: TimeInterval, source: String = "mic") {
        self.id = UUID()
        self.text = text
        self.createdAt = .now
        self.duration = duration
        self.source = source
    }
}
