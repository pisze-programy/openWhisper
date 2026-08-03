import AppKit
import SwiftUI
import OpenWhisperShared

struct MacRootView: View {

    enum SidebarSection: String, CaseIterable, Identifiable {
        case history
        case formatting
        case dictation
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .history: return "History"
            case .formatting: return "Formatting"
            case .dictation: return "Dictation"
            case .settings: return "Settings"
            }
        }

        var subtitle: String {
            switch self {
            case .history: return "Past transcriptions"
            case .formatting: return "AI style and rewrite"
            case .dictation: return "Model, recording, API"
            case .settings: return "Audio, history, permissions"
            }
        }

        var systemImage: String {
            switch self {
            case .history: return "clock.arrow.circlepath"
            case .formatting: return "wand.and.stars"
            case .dictation: return "waveform.badge.mic"
            case .settings: return "gearshape"
            }
        }
    }

    private static var mainSections: [SidebarSection] { [.history, .formatting, .dictation] }
    private static var pinnedSections: [SidebarSection] { [.settings] }

    @Environment(MainWindowState.self) private var windowState

    private func sectionRow(_ section: SidebarSection) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(section.title, systemImage: section.systemImage)
            Text(section.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.leading, 22)
        }
        .padding(.vertical, 3)
        .tag(section)
    }

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

                List(selection: $windowState.selectedSection) {
                    Section {
                        ForEach(Self.mainSections) { section in
                            sectionRow(section)
                        }
                    }

                    Section {
                        ForEach(Self.pinnedSections) { section in
                            sectionRow(section)
                        }
                    }
                }
                .listStyle(.sidebar)
                .padding(.vertical, 4)

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
            case .formatting: FormattingView()
            case .dictation: DictationView()
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
