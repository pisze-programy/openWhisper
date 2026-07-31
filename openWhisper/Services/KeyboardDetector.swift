import UIKit
import OpenWhisperShared

enum KeyboardStatus: Equatable {
    case enabled
    case notEnabled
}

enum KeyboardDetector {
    static var status: KeyboardStatus {
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        return defaults?.object(forKey: AppGroup.keyboardLastUsedKey) != nil ? .enabled : .notEnabled
    }

    static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
