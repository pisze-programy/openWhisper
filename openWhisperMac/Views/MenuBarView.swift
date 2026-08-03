import SwiftUI
import OpenWhisperShared

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(SettingsStore.self) private var settings
    @Environment(MainWindowState.self) private var windowState
    @Environment(RecentsStore.self) private var recents
    @AppStorage("settings.autoCopy") private var autoCopy = true

    var body: some View {
        Group {
            if let orchestrator = AppDelegate.current?.orchestrator {
                Label(statusText(for: orchestrator.phase), systemImage: statusIcon(for: orchestrator.phase))
            } else {
                Label("OpenWhisper", systemImage: "waveform")
            }

            Divider()

            Button {
                windowState.selectedSection = .history
                showMainWindow()
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }

            Button {
                windowState.selectedSection = .settings
                showMainWindow()
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }

            Divider()

            Picker("Formatting style", selection: Binding(
                get: { settings.formattingStyle },
                set: { settings.formattingStyle = $0 }
            )) {
                ForEach(TranscriptionStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }

            Button {
                MacClipboardService.shared.copy(recents.lastText)
            } label: {
                Label("Copy Last Transcription", systemImage: "doc.on.doc")
            }
            .disabled(recents.lastText.isEmpty)

            Divider()

            Button("Show Onboarding") {
                settings.onboardingCompleted = false
                openWindow(id: "setup")
                NSApp.setActivationPolicy(.regular)
                DispatchQueue.main.async {
                    NSApp.windows.first(where: { $0.title == "OpenWhisper Setup" })?.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func showMainWindow() {
        openWindow(id: "openwhisper")
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApp.windows.first(where: { $0.title == "OpenWhisper" })?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func statusText(for phase: DictationOrchestrator.Phase) -> String {
        switch phase {
        case .idle: return "Ready"
        case .listening: return "Listening…"
        case .transcribing: return "Transcribing…"
        case .polishing: return "Polishing…"
        case .done: return "Copied"
        case .failed: return "Error"
        }
    }

    private func statusIcon(for phase: DictationOrchestrator.Phase) -> String {
        switch phase {
        case .idle: return "waveform"
        case .listening: return "mic.fill"
        case .transcribing, .polishing: return "arrow.triangle.2.circlepath"
        case .done: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
}
