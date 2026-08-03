import Foundation
import Observation

@MainActor
@Observable
final class MainWindowState {
    var selectedSection: MacRootView.Section = .history
}
