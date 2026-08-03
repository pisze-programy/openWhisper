import AppKit
import Foundation
import ServiceManagement

/// Registers the app as a login item using the modern SMAppService API
/// (macOS 13+). Falls back gracefully when running in a debug/adhoc context.
@MainActor
enum LaunchAtLoginService {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func apply(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("LaunchAtLogin: \(error.localizedDescription)")
        }
    }
}
