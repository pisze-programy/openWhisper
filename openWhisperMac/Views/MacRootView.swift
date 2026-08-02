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

    @State private var selected = Section.history

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selected) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            switch selected {
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
