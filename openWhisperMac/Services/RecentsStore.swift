import Foundation

/// In-memory holder for the most recent transcription, used by the menu bar
/// "Copy Last Translation" action.
@MainActor
enum RecentsStore {
    private(set) static var lastText = ""

    static func set(_ text: String) {
        lastText = text
    }
}
