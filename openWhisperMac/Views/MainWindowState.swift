import Foundation
import Observation

@MainActor
@Observable
final class MainWindowState {
    var selectedSection: MacRootView.SidebarSection = .history
}
