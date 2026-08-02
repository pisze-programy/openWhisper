import AppKit
import Foundation
import Observation
import OpenWhisperShared

/// NSPasteboard-backed clipboard conforming to the shared `ClipboardProviding`.
@MainActor @Observable
final class MacClipboardService: ClipboardProviding {
    static let shared = MacClipboardService()

    init() {}

    func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
