import AppKit
import Foundation

@MainActor
enum CriticalErrorAlert {
    private static weak var registeredWindow: NSWindow?

    static func register(_ window: NSWindow) {
        registeredWindow = window
    }

    static func show(title: String, message: String, quitAfter: Bool = false) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: quitAfter ? "Quit" : "OK")
        if let window = registeredWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
        if quitAfter {
            NSApplication.shared.terminate(nil)
        }
    }
}
