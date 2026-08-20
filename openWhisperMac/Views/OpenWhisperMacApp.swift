import AppKit
import SwiftData
import SwiftUI
import OpenWhisperShared

@main
struct OpenWhisperMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    @State private var settings = SettingsStore.shared
    @State private var toast = ToastCenter()
    @State private var corrections = CorrectionsStore.shared
    @State private var clipboard = MacClipboardService.shared
    @State private var windowState = MainWindowState()
    @State private var container: ModelContainer?

    init() {
        // Must run before ModelContainer is created: the history store lives in
        // the App Group container, so any legacy store has to be moved first or
        // SwiftData would open (create) the target and the copy would conflict.
        AppDelegate.migrateHistoryIfNeeded()
        SettingsStore.migrateFromLegacyDefaultsIfNeeded()

        try? FileManager.default.createDirectory(
            at: ModelLocations.historyStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let config = ModelConfiguration(url: ModelLocations.historyStoreURL)
        do {
            _container = State(initialValue: try ModelContainer(for: TranscriptionItem.self, configurations: config))
        } catch {
            let alert = NSAlert()
            alert.messageText = "Database error"
            alert.informativeText = "OpenWhisper could not open its local database: \(error.localizedDescription)"
            alert.alertStyle = .critical
            alert.runModal()
            NSApplication.shared.terminate(nil)
        }
    }

    var body: some Scene {
        let _ = {
            appDelegate.appOpenWindow = openWindow
            appDelegate.sharedContainer = container
        }()
        MenuBarExtra("OpenWhisper", systemImage: menuBarIconName) {
            MenuBarView()
                .environment(settings)
                .environment(toast)
                .environment(windowState)
                .environment(RecentsStore.shared)
        }
        .menuBarExtraStyle(.menu)

        Window("OpenWhisper", id: "openwhisper") {
            MacRootView()
                .environment(settings)
                .environment(MacTranscriptionService.shared)
                .environment(toast)
                .environment(corrections)
                .environment(clipboard)
                .environment(PermissionManager.shared)
                .environment(windowState)
        }
        .modelContainer(mainContainer)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 980, height: 620)

        Window("OpenWhisper Setup", id: "setup") {
            SetupWindow()
                .environment(settings)
                .environment(MacTranscriptionService.shared)
                .environment(PermissionManager.shared)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 760, height: 540)
    }

    private var mainContainer: ModelContainer { container! }

    private var menuBarIconName: String {
        switch appDelegate.orchestrator?.phase ?? .idle {
        case .listening: return "mic.fill"
        default: return "waveform"
        }
    }
}
