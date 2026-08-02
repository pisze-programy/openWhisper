import Foundation
import Observation

@MainActor @Observable
public final class SettingsRouter {

    public var pendingSection: String?

    public init() {}
}
