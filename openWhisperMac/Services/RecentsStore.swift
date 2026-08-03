import Foundation
import Observation

/// Holds the most recent transcription for the menu bar "Copy Last
/// Transcription" action. Observable so the menu bar item's enabled state
/// refreshes whenever a new transcription lands.
@MainActor @Observable
final class RecentsStore {
    static let shared = RecentsStore()

    private(set) var lastText = ""

    func set(_ text: String) {
        lastText = text
    }
}
