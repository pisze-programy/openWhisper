import Foundation
import ParakeetTDT
import OpenWhisperShared

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
            UserDefaults.standard.set(languageCode, forKey: AppGroup.languageCodeKey)
            UserDefaults(suiteName: AppGroup.identifier)?.set(languageCode, forKey: AppGroup.languageCodeKey)
        }
    }

    var onboardingCompleted: Bool {
        didSet {
            UserDefaults.standard.set(onboardingCompleted, forKey: "settings.onboardingCompleted")
        }
    }

    static let maxRecordingDuration: TimeInterval = 600

    init() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: "settings.computeUnits"),
           let units = ParakeetComputeUnits(rawValue: raw) {
            // .ane and .all are supported by the engine but not offered in the
            // UI — map them to the fast default so the picker always has a
            // valid selection.
            computeUnits = (units == .ane || units == .all) ? .gpu : units
        } else {
            computeUnits = .gpu
        }
        autoCopy = defaults.object(forKey: "settings.autoCopy") as? Bool ?? true
        saveToHistory = defaults.object(forKey: "settings.saveToHistory") as? Bool ?? true
        let code = defaults.string(forKey: AppGroup.languageCodeKey)
        languageCode = code
        // Mirror the existing value into the shared App Group suite (didSet does
        // not fire during init) so the keyboard sees it without a re-pick.
        UserDefaults(suiteName: AppGroup.identifier)?.set(code, forKey: AppGroup.languageCodeKey)
        onboardingCompleted = defaults.object(forKey: "settings.onboardingCompleted") as? Bool ?? false
    }
}
