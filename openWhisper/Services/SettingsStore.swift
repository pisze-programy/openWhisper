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
            UserDefaults(suiteName: AppGroup.identifier)?.set(autoCopy, forKey: "settings.autoCopy")
        }
    }

    var saveToHistory: Bool {
        didSet {
            UserDefaults.standard.set(saveToHistory, forKey: "settings.saveToHistory")
            UserDefaults(suiteName: AppGroup.identifier)?.set(saveToHistory, forKey: "settings.saveToHistory")
        }
    }

    var languageCode: String? {
        didSet {
            UserDefaults.standard.set(languageCode, forKey: AppGroup.languageCodeKey)
            UserDefaults(suiteName: AppGroup.identifier)?.set(languageCode, forKey: AppGroup.languageCodeKey)
        }
    }

    /// Auto-stop recording when the mic stays silent this long (seconds).
    /// Fixed at 5 s for now but stored like every other setting so it can
    /// become user-configurable later. Mirrored to the App Group so the
    /// keyboard extension can honor it too.
    var autoStopSilenceSeconds: Double {
        didSet {
            UserDefaults.standard.set(autoStopSilenceSeconds, forKey: AppGroup.autoStopSilenceSecondsKey)
            UserDefaults(suiteName: AppGroup.identifier)?.set(autoStopSilenceSeconds, forKey: AppGroup.autoStopSilenceSecondsKey)
        }
    }

    var autoStopOnSilence: Bool {
        didSet {
            UserDefaults.standard.set(autoStopOnSilence, forKey: AppGroup.autoStopOnSilenceKey)
            UserDefaults(suiteName: AppGroup.identifier)?.set(autoStopOnSilence, forKey: AppGroup.autoStopOnSilenceKey)
        }
    }

    /// Microphone gain applied to recordings (1...10). The `.measurement` audio
    /// mode has no auto-gain, so quiet microphones need a boost for the STT to
    /// hear normal speech. Default 5.0 ("Optimal").
    var micGain: Double {
        didSet {
            UserDefaults.standard.set(micGain, forKey: "settings.micGain")
        }
    }

    /// Whether finished transcripts are rewritten by the AI formatting step.
    var formattingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(formattingEnabled, forKey: "settings.formattingEnabled")
        }
    }

    /// Style applied to new transcriptions. Chosen at recording time; persisted
    /// here so the picker remembers the last selection.
    var formattingStyle: TranscriptionStyle {
        didSet {
            UserDefaults.standard.set(formattingStyle.rawValue, forKey: "settings.formattingStyle")
        }
    }

    var onboardingCompleted: Bool {
        didSet {
            UserDefaults.standard.set(onboardingCompleted, forKey: "settings.onboardingCompleted")
        }
    }

    static let maxRecordingDuration: TimeInterval = 600

    /// App-side read of the silence auto-stop toggle (default on).
    static var silenceAutoStopEnabled: Bool {
        UserDefaults.standard.object(forKey: AppGroup.autoStopOnSilenceKey) as? Bool ?? true
    }

    /// App-side read of the silence timeout in seconds (default 5).
    static var silenceAutoStopSeconds: Double {
        UserDefaults.standard.object(forKey: AppGroup.autoStopSilenceSecondsKey) as? Double ?? 5.0
    }

    /// App-side read of the microphone gain (1...10, default 5 = "Optimal").
    static var sharedMicGain: Double {
        UserDefaults.standard.object(forKey: "settings.micGain") as? Double ?? 5.0
    }

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
        let copy = defaults.object(forKey: "settings.autoCopy") as? Bool ?? true
        autoCopy = copy
        UserDefaults(suiteName: AppGroup.identifier)?.set(copy, forKey: "settings.autoCopy")
        let history = defaults.object(forKey: "settings.saveToHistory") as? Bool ?? true
        saveToHistory = history
        UserDefaults(suiteName: AppGroup.identifier)?.set(history, forKey: "settings.saveToHistory")
        let code = defaults.string(forKey: AppGroup.languageCodeKey)
        languageCode = code
        // Mirror the existing value into the shared App Group suite (didSet does
        // not fire during init) so the keyboard sees it without a re-pick.
        UserDefaults(suiteName: AppGroup.identifier)?.set(code, forKey: AppGroup.languageCodeKey)
        onboardingCompleted = defaults.object(forKey: "settings.onboardingCompleted") as? Bool ?? false
        autoStopOnSilence = defaults.object(forKey: AppGroup.autoStopOnSilenceKey) as? Bool ?? true
        autoStopSilenceSeconds = defaults.object(forKey: AppGroup.autoStopSilenceSecondsKey) as? Double ?? 5.0
        micGain = defaults.object(forKey: "settings.micGain") as? Double ?? 5.0
        formattingEnabled = defaults.object(forKey: "settings.formattingEnabled") as? Bool ?? true
        let styleRaw = defaults.string(forKey: "settings.formattingStyle")
        formattingStyle = styleRaw.flatMap(TranscriptionStyle.init(rawValue:)) ?? .casual
    }
}
