import AppKit
import OpenWhisperShared
import SwiftData
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var current: AppDelegate?

    private(set) var orchestrator: DictationOrchestrator?
    var appOpenWindow: OpenWindowAction?
    var sharedContainer: ModelContainer?

    private let recorder = MacRecorder()
    private let transcription = MacTranscriptionService.shared
    private let modelDownload = ModelDownloadManager.shared
    private var sleepObserver: SystemSleepObserver?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.current = self
        PermissionUpgradeGuard.resetAccessibilityIfUpgraded()
        PermissionManager.shared.refresh()

        let settings = SettingsStore.shared
        // One-time move of legacy data (history + model + settings + key) into
        // the stable App Group locations so an update never resets the user.
        Self.migrateLegacyData(settings: settings)
        let pipeline = PostProcessingPipeline()
        let corrections = CorrectionsStore.shared

        LaunchAtLoginService.apply(settings.launchAtLogin)

        guard let container = sharedContainer else {
            CriticalErrorAlert.show(
                title: "Database not ready",
                message: "The local database could not be initialized. Please restart OpenWhisper.",
                quitAfter: true
            )
            return
        }

        let orchestrator = DictationOrchestrator(
            recorder: recorder,
            transcription: transcription,
            pipeline: pipeline,
            settings: settings,
            clipboard: MacClipboardService.shared,
            insertion: TextInsertionService.shared,
            corrections: corrections,
            ducking: AudioDuckingService.shared,
            mediaPlayback: MediaPlaybackPauser.shared,
            sounds: FeedbackSoundService.shared,
            modelContext: container.mainContext
        )
        self.orchestrator = orchestrator

        // Seed "Copy Last Translation" from persisted history so the menu bar
        // action works right after launch, before any new dictation this session.
        var recentDescriptor = FetchDescriptor<TranscriptionItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        recentDescriptor.fetchLimit = 1
        if let lastText = try? container.mainContext.fetch(recentDescriptor).first?.text {
            RecentsStore.shared.set(lastText)
        }

        let sleepObserver = SystemSleepObserver(recorder: recorder, orchestrator: orchestrator)
        sleepObserver.start()
        self.sleepObserver = sleepObserver

        StatusOverlayPanel.shared.getSamples = { [weak recorder] in
            recorder?.liveSamples ?? []
        }

        orchestrator.onPhaseChange = { phase in
            switch phase {
            case .idle:
                StatusOverlayPanel.shared.hide()
            default:
                StatusOverlayPanel.shared.show(phase: phase)
            }
        }

        HotkeyManager.shared.requireSecondEscapeToCancel = settings.requireSecondEscapeToCancel
        HotkeyManager.shared.onRecordStart = { orchestrator.startRecording() }
        HotkeyManager.shared.onRecordStop = { orchestrator.stopAndTranscribe() }
        HotkeyManager.shared.onCancel = { orchestrator.cancel() }
        HotkeyManager.shared.onCycleStyle = {
            // Without an API key the only usable style is NONE — keep the style
            // hotkey locked there instead of cycling into AI styles that would
            // fail. The orchestrators guard their own state.
            if TextFormattingService.hasApiKey {
                settings.cycleFormattingStyle(preview: true)
            } else {
                settings.formattingStyle = .none
            }
            StatusOverlayPanel.shared.showStyleSwitch(style: settings.formattingStyle) {
                FeedbackSoundService.shared.play(.styleChanged)
            }
        }
        HotkeyManager.shared.onStyleCycleEnd = {
            settings.persistFormattingStyle()
            StatusOverlayPanel.shared.confirmSelectorSelection()
        }
        HotkeyManager.shared.onCycleTranslation = {
            // Without an API key no target can be applied — keep the translation
            // hotkey locked on NONE instead of cycling into languages that would
            // fail. The orchestrator guards its own state.
            if TextFormattingService.hasApiKey {
                settings.cycleTranslationTarget(preview: true)
            } else {
                settings.translationTargetCode = nil
            }
            StatusOverlayPanel.shared.showTranslationSwitch(target: settings.translationTargetCode) {
                FeedbackSoundService.shared.play(.styleChanged)
            }
        }
        HotkeyManager.shared.onTranslationCycleEnd = {
            settings.persistTranslationTarget()
            StatusOverlayPanel.shared.confirmSelectorSelection()
        }
        HotkeyManager.shared.start()

        // Model warm-up is independent of onboarding: load from cache if the
        // model is already on disk (returning user → STT works immediately),
        // never auto-download. The model card exposes the explicit download.
        Task {
            await transcription.migrateLegacyModelIfNeeded()
            await transcription.warmUpFromCache()
            await recorder.prewarm()
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !settings.onboardingCompleted, let open = self.appOpenWindow {
                open(id: "setup")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        sleepObserver?.stop()
        orchestrator?.cancel()
        AudioDuckingService.shared.restore()
    }

    // MARK: - Legacy data migration

    /// Copies data created by older builds (sandbox-container Application
    /// Support, keyed by the previous bundle identifier) into the stable App
    /// Group locations. Every step is best-effort and leaves the source in
    /// place, so the old files act as a backup and nothing is ever overwritten.
    private static func migrateLegacyData(settings: SettingsStore) {
        // 1. Settings + onboarding flag: standard defaults → App Group suite.
        SettingsStore.migrateFromLegacyDefaultsIfNeeded()

        // 2. OpenRouter key: KeychainStore already migrates legacy services on
        //    first read (see KeychainStore.migrateLegacy).

        // 3. History database: copy the old store into the App Group container.
        migrateHistoryIfNeeded()
    }

    private static func migrateHistoryIfNeeded() {
        let legacy = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenWhisper", isDirectory: true)
        let target = ModelLocations.historyStoreURL

        let legacyStore = legacy.appendingPathComponent("History.store")
        let targetStore = target.deletingLastPathComponent()
            .appendingPathComponent("History.store")
        guard FileManager.default.fileExists(atPath: legacyStore.path),
              !FileManager.default.fileExists(atPath: targetStore.path) else { return }

        try? FileManager.default.createDirectory(
            at: targetStore.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Copy main store + sqlite sidecars so nothing is lost; the original is
        // kept as the backup.
        for name in ["History.store", "History.store-shm", "History.store-wal"] {
            let src = legacy.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: src.path) else { continue }
            try? FileManager.default.copyItem(at: src, to: targetStore.deletingLastPathComponent().appendingPathComponent(name))
        }
    }
}
