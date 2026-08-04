import Foundation
import ParakeetTDT
import OpenWhisperShared

@MainActor @Observable
public final class SettingsStore {
    /// Single shared instance. macOS wires the SwiftUI app and the
    /// AppDelegate/orchestrator to the same object so settings changed in the
    /// UI (menu bar, Formatting, Settings) take effect immediately for
    /// dictation instead of living on a second, stale instance.
    public static let shared = SettingsStore()

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
    /// Derived from the selected style: `.none` skips the LLM request entirely,
    /// so a separate disable toggle is no longer needed.
    public var formattingEnabled: Bool {
        formattingStyle != .none
    }

    /// Style applied to new transcriptions. Chosen at recording time; persisted
    /// here so the picker remembers the last selection. `.none` runs the
    /// transcript through local cleanup only — no API request.
    public var formattingStyle: TranscriptionStyle {
        didSet {
            guard !suppressFormattingStyleSave else { return }
            UserDefaults.standard.set(formattingStyle.rawValue, forKey: "settings.formattingStyle")
        }
    }

    /// Set while cycling styles with the hotkey so intermediate previews are not
    /// persisted; the final selection is saved on key release.
    private var suppressFormattingStyleSave = false

    /// Advances to the next style in `TranscriptionStyle.allCases` (wrapping).
    /// Used by the macOS style-switch hotkey so NONE can be reached without
    /// opening the app. Pass `preview: true` while the user is still holding the
    /// hotkey — nothing is written to UserDefaults until `persistFormattingStyle`.
    public func cycleFormattingStyle(preview: Bool = false) {
        suppressFormattingStyleSave = preview
        defer { suppressFormattingStyleSave = false }
        let all = TranscriptionStyle.allCases
        guard let index = all.firstIndex(of: formattingStyle) else { return }
        formattingStyle = all[(index + 1) % all.count]
    }

    /// Persists the currently selected style. Called when the style-switch
    /// hotkey is released.
    public func persistFormattingStyle() {
        UserDefaults.standard.set(formattingStyle.rawValue, forKey: "settings.formattingStyle")
    }

    /// Source language for the translate hotkey (left ⌘+⌥). nil = auto-detect.
    public var translateSourceCode: String? {
        didSet {
            UserDefaults.standard.set(translateSourceCode, forKey: "settings.translateSourceCode")
        }
    }

    /// Target language for the translate hotkey. nil = translation disabled
    /// (the hotkey reformats only).
    public var translateTargetCode: String? {
        didSet {
            UserDefaults.standard.set(translateTargetCode, forKey: "settings.translateTargetCode")
        }
    }

    /// Whether the translate hotkey performs an actual translation (both
    /// languages set and different). When false, the hotkey reformats only.
    public var isTranslationActive: Bool {
        guard let source = translateSourceCode, let target = translateTargetCode else { return false }
        return source != target
    }

    /// Swaps the FROM/TO translation pair. No-op when either side is unset.
    public func swapTranslateDirection() {
        guard let source = translateSourceCode, let target = translateTargetCode else { return }
        translateSourceCode = target
        translateTargetCode = source
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
        var style = defaults.string(forKey: "settings.formattingStyle").flatMap(TranscriptionStyle.init(rawValue:)) ?? .formal
        // Legacy installs that had the AI rewrite toggle off map to NONE.
        if defaults.object(forKey: "settings.formattingEnabled") as? Bool == false {
            style = .none
        }
        formattingStyle = style
        launchAtLogin = defaults.object(forKey: "settings.launchAtLogin") as? Bool ?? true
        translateSourceCode = defaults.string(forKey: "settings.translateSourceCode") ?? "pl"
        translateTargetCode = defaults.string(forKey: "settings.translateTargetCode") ?? "en"
    }
}
