import UIKit

/// Copies text to the system pasteboard.
enum ClipboardService {
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}
