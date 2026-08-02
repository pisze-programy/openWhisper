import Foundation
import Observation

@MainActor @Observable
final class SettingsRouter {

    var pendingSection: String?
}
