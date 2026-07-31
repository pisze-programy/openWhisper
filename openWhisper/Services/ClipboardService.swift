import UIKit

enum ClipboardService {
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}
