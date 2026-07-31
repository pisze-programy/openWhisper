import Foundation
import SwiftData

@Model
public final class TranscriptionItem {
    public var id: UUID
    public var text: String
    public var createdAt: Date
    public var duration: TimeInterval
    public var source: String

    public init(text: String, duration: TimeInterval, source: String = "mic") {
        self.id = UUID()
        self.text = text
        self.createdAt = .now
        self.duration = duration
        self.source = source
    }
}
