import SwiftUI
import OpenWhisperShared

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(SettingsStore.self) private var settings
    @Environment(MainWindowState.self) private var windowState
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
                MacClipboardService.shared.copy(RecentsStore.lastText)
            } label: {
                Label("Copy Last Translation", systemImage: "doc.on.doc")
            }
            .disabled(RecentsStore.lastText.isEmpty)

            Divider()

            Button("Show Onboarding") {
                settings.onboardingCompleted = false
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "setup")
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "openwhisper")
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
