import Foundation
import ParakeetTDT
import OpenWhisperShared

@MainActor @Observable
public final class SettingsStore {
    public var computeUnits: ParakeetComputeUnits {
        didSet {
            UserDefaults.standard.set(computeUnits.rawValue, forKey: "settings.computeUnits")
        }
    }

    public var autoCopy: Bool {
        didSet {
            UserDefaults.standard.set(autoCopy, forKey: "settings.autoCopy")
            UserDefaults(suiteName: AppGroup.identifier)?.set(autoCopy, forKey: "settings.autoCopy")
        }
    }

    /// Whether dictation should auto-paste into the active input (macOS).
    /// Default off; requires Accessibility permission.
    public var autoPaste: Bool {
        didSet {
            UserDefaults.standard.set(autoPaste, forKey: "settings.autoPaste")
        }
    }

    /// Restores the previous clipboard contents after auto-paste. Default off,
    /// consistent with autoCopy leaving the transcript on the clipboard.
    public var preserveClipboard: Bool {
        didSet {
            UserDefaults.standard.set(preserveClipboard, forKey: "settings.preserveClipboard")
        }
    }

    public var saveToHistory: Bool {
        didSet {
            UserDefaults.standard.set(saveToHistory, forKey: "settings.saveToHistory")
            UserDefaults(suiteName: AppGroup.identifier)?.set(saveToHistory, forKey: "settings.saveToHistory")
        }
    }

    public var languageCode: String? {
        didSet {
            UserDefaults.standard.set(languageCode, forKey: AppGroup.languageCodeKey)
            UserDefaults(suiteName: AppGroup.identifier)?.set(languageCode, forKey: AppGroup.languageCodeKey)
        }
    }

    /// Auto-stop recording when the mic stays silent this long (seconds).
    /// Fixed at 5 s for now but stored like every other setting so it can
    /// become user-configurable later. Mirrored to the App Group so the
    /// keyboard extension can honor it too.
    public var autoStopSilenceSeconds: Double {
        didSet {
            UserDefaults.standard.set(autoStopSilenceSeconds, forKey: AppGroup.autoStopSilenceSecondsKey)
            UserDefaults(suiteName: AppGroup.identifier)?.set(autoStopSilenceSeconds, forKey: AppGroup.autoStopSilenceSecondsKey)
        }
    }

    public var autoStopOnSilence: Bool {
        didSet {
            UserDefaults.standard.set(autoStopOnSilence, forKey: AppGroup.autoStopOnSilenceKey)
            UserDefaults(suiteName: AppGroup.identifier)?.set(autoStopOnSilence, forKey: AppGroup.autoStopOnSilenceKey)
        }
    }

    /// Microphone gain applied to recordings (1...10). The `.measurement` audio
    /// mode has no auto-gain, so quiet microphones need a boost for the STT to
    /// hear normal speech. Default 5.0 ("Optimal").
    public var micGain: Double {
        didSet {
            UserDefaults.standard.set(micGain, forKey: "settings.micGain")
        }
    }

    /// Automatic gain control applied to the captured samples before
    /// transcription ("Whisper Mode"). Complements `micGain`: static level from
    /// the slider, adaptive boost on top when enabled.
    public var microphoneBoostEnabled: Bool {
        didSet {
            UserDefaults.standard.set(microphoneBoostEnabled, forKey: "settings.microphoneBoost")
        }
    }

    /// Keeps very short or quiet recordings instead of discarding them as "no
    /// speech". Default on.
    public var transcribeShortQuietClipsAggressively: Bool {
        didSet {
            UserDefaults.standard.set(transcribeShortQuietClipsAggressively, forKey: "settings.aggressiveShortClips")
        }
    }

    /// Require a second Esc press to confirm cancelling a recording (macOS).
    public var requireSecondEscapeToCancel: Bool {
        didSet {
            UserDefaults.standard.set(requireSecondEscapeToCancel, forKey: "settings.requireSecondEscape")
        }
    }

    /// Whether finished transcripts are rewritten by the AI formatting step.
    public var formattingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(formattingEnabled, forKey: "settings.formattingEnabled")
        }
    }

    /// Style applied to new transcriptions. Chosen at recording time; persisted
    /// here so the picker remembers the last selection.
    public var formattingStyle: TranscriptionStyle {
        didSet {
            UserDefaults.standard.set(formattingStyle.rawValue, forKey: "settings.formattingStyle")
        }
    }

    public var onboardingCompleted: Bool {
        didSet {
            UserDefaults.standard.set(onboardingCompleted, forKey: "settings.onboardingCompleted")
        }
    }

    /// Launch OpenWhisper automatically when the user logs in (macOS).
    public var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "settings.launchAtLogin")
        }
    }

    public static let maxRecordingDuration: TimeInterval = 600

    /// App-side read of the silence auto-stop toggle (default on).
    public static var silenceAutoStopEnabled: Bool {
        UserDefaults.standard.object(forKey: AppGroup.autoStopOnSilenceKey) as? Bool ?? true
    }

    /// App-side read of the silence timeout in seconds (default 5).
    public static var silenceAutoStopSeconds: Double {
        UserDefaults.standard.object(forKey: AppGroup.autoStopSilenceSecondsKey) as? Double ?? 5.0
    }

    /// App-side read of the microphone gain (1...10, default 5 = "Optimal").
    public static var sharedMicGain: Double {
        UserDefaults.standard.object(forKey: "settings.micGain") as? Double ?? 5.0
    }

    public init() {
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
        autoPaste = defaults.object(forKey: "settings.autoPaste") as? Bool ?? true
        preserveClipboard = defaults.object(forKey: "settings.preserveClipboard") as? Bool ?? false
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
        microphoneBoostEnabled = defaults.object(forKey: "settings.microphoneBoost") as? Bool ?? true
        transcribeShortQuietClipsAggressively = defaults.object(forKey: "settings.aggressiveShortClips") as? Bool ?? true
        requireSecondEscapeToCancel = defaults.object(forKey: "settings.requireSecondEscape") as? Bool ?? false
        formattingEnabled = defaults.object(forKey: "settings.formattingEnabled") as? Bool ?? true
        let styleRaw = defaults.string(forKey: "settings.formattingStyle")
        formattingStyle = styleRaw.flatMap(TranscriptionStyle.init(rawValue:)) ?? .formal
        launchAtLogin = defaults.object(forKey: "settings.launchAtLogin") as? Bool ?? true
    }
}
