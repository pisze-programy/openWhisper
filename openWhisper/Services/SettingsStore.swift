import Foundation
import ParakeetTDT

@MainActor @Observable
final class SettingsStore {
    var computeUnits: ParakeetComputeUnits {
        didSet {
            UserDefaults.standard.set(computeUnits.rawValue, forKey: "settings.computeUnits")
        }
    }

    var autoCopy: Bool {
        didSet {
            UserDefaults.standard.set(autoCopy, forKey: "settings.autoCopy")
        }
    }

    var saveToHistory: Bool {
        didSet {
            UserDefaults.standard.set(saveToHistory, forKey: "settings.saveToHistory")
        }
    }

    var languageCode: String? {
        didSet {
            UserDefaults.standard.set(languageCode, forKey: "settings.languageCode")
        }
    }

    static let maxRecordingDuration: TimeInterval = 600

    init() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: "settings.computeUnits"),
           let units = ParakeetComputeUnits(rawValue: raw) {
            computeUnits = units
        } else {
            computeUnits = .ane
        }
        autoCopy = defaults.object(forKey: "settings.autoCopy") as? Bool ?? true
        saveToHistory = defaults.object(forKey: "settings.saveToHistory") as? Bool ?? true
        languageCode = defaults.string(forKey: "settings.languageCode")
    }
}
