import AppKit
import OpenWhisperShared
import SwiftData
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var current: AppDelegate?

    private(set) var orchestrator: DictationOrchestrator?
    private(set) var reformat: ReformatOrchestrator?
    var appOpenWindow: OpenWindowAction?
    var sharedContainer: ModelContainer?

    private let recorder = MacRecorder()
    private let transcription = MacTranscriptionService()
    private let modelDownload = ModelDownloadManager.shared
    private var sleepObserver: SystemSleepObserver?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.current = self
        PermissionUpgradeGuard.resetAccessibilityIfUpgraded()
        PermissionManager.shared.refresh()
        ModelDownloadManager.shared.refreshStatus()

        let settings = SettingsStore.shared
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
            sounds: FeedbackSoundService.shared,
            modelContext: container.mainContext
        )
        self.orchestrator = orchestrator

        let reformat = ReformatOrchestrator(
            settings: settings,
            pipeline: pipeline,
            insertion: TextInsertionService.shared,
            clipboard: MacClipboardService.shared,
            corrections: corrections,
            sounds: FeedbackSoundService.shared
        )
        self.reformat = reformat

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
        HotkeyManager.shared.onRecordStart = {
            reformat.cancel()
            orchestrator.startRecording()
        }
        HotkeyManager.shared.onRecordStop = { orchestrator.stopAndTranscribe() }
        HotkeyManager.shared.onCancel = { orchestrator.cancel() }
        HotkeyManager.shared.onCycleStyle = {
            // Preview only — the final style is persisted on key release.
            settings.cycleFormattingStyle(preview: true)
            StatusOverlayPanel.shared.showStyleSwitch(style: settings.formattingStyle) {
                FeedbackSoundService.shared.play(.styleChanged)
            }
        }
        HotkeyManager.shared.onStyleCycleEnd = {
            settings.persistFormattingStyle()
            StatusOverlayPanel.shared.confirmStyleSelection()
        }
        HotkeyManager.shared.onTranslateReformat = {
            // Never run reformat while a recording is in flight.
            guard orchestrator.phase == .idle else { return }
            reformat.run()
        }
        HotkeyManager.shared.onSwapTranslateDirection = {
            guard orchestrator.phase == .idle else { return }
            settings.swapTranslateDirection()
            let fromName = settings.translateSourceCode.flatMap { Language.language(for: $0)?.name } ?? "Auto"
            let toName = settings.translateTargetCode.flatMap { Language.language(for: $0)?.name } ?? "Off"
            StatusOverlayPanel.shared.showTranslateSwap(from: fromName, to: toName) {
                FeedbackSoundService.shared.play(.styleChanged)
            }
        }
        HotkeyManager.shared.start()

        if !settings.onboardingCompleted {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            Task {
                await transcription.warmUp()
                await recorder.prewarm()
            }
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
        reformat?.cancel()
        AudioDuckingService.shared.restore()
    }
}
