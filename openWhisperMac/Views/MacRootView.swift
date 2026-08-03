import AppKit
import SwiftUI
import OpenWhisperShared

struct MacRootView: View {

    enum Section: String, CaseIterable, Identifiable {
        case history
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .history: return "History"
            case .settings: return "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .history: return "clock.arrow.circlepath"
            case .settings: return "gearshape"
            }
        }
    }

    @Environment(MainWindowState.self) private var windowState

    var body: some View {
        @Bindable var windowState = windowState
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    if let appIcon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath) as NSImage? {
                        Image(nsImage: appIcon)
                            .resizable()
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    } else {
                        Image(systemName: "waveform.badge.mic")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("OpenWhisper")
                            .font(.headline)
                        Text("Dictation")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)

                Divider()

                List(Section.allCases, selection: $windowState.selectedSection) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
                .listStyle(.sidebar)

                Divider()

                VStack(alignment: .leading, spacing: 3) {
                    Text("Type faster.")
                        .font(.footnote.weight(.medium))
                    Text("Dictate anywhere, private by default.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            switch windowState.selectedSection {
            case .history: HistoryView()
            case .settings: SettingsView()
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard let window = notification.object as? NSWindow else { return }
            if window.title == "OpenWhisper" {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
