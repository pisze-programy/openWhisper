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
    private let transcription = MacTranscriptionService()
    private let modelDownload = ModelDownloadManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.current = self
        PermissionManager.shared.refresh()
        ModelDownloadManager.shared.refreshStatus()

        let settings = SettingsStore()
        let pipeline = PostProcessingPipeline()
        let corrections = CorrectionsStore()

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
        HotkeyManager.shared.start()

        if !settings.onboardingCompleted {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            Task { await transcription.warmUp() }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !settings.onboardingCompleted, let open = self.appOpenWindow {
                open(id: "setup")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        orchestrator?.cancel()
        AudioDuckingService.shared.restore()
    }
}
