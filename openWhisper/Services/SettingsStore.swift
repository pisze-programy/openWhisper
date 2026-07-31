import Foundation
import ParakeetTDT

/// App settings, persisted to `UserDefaults` and observable so the UI
/// updates live. All stored properties persist themselves on change.
@MainActor @Observable
final class SettingsStore {
    /// Core ML compute units used for transcription (`.ane` default).
    var computeUnits: ParakeetComputeUnits {
        didSet {
            UserDefaults.standard.set(computeUnits.rawValue, forKey: "settings.computeUnits")
        }
    }

    /// Whether to copy the transcript to the clipboard automatically.
    var autoCopy: Bool {
        didSet {
            UserDefaults.standard.set(autoCopy, forKey: "settings.autoCopy")
        }
    }

    /// Whether to persist transcripts to the history list.
    var saveToHistory: Bool {
        didSet {
            UserDefaults.standard.set(saveToHistory, forKey: "settings.saveToHistory")
        }
    }

    /// Longest allowed recording, in seconds.
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
    }
}
