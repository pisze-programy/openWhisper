import AppKit
import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class PermissionManager {
    static let shared = PermissionManager()

    enum PermissionStatus {
        case granted
        case denied
        case notDetermined

        var isGranted: Bool { self == .granted }
    }

    private(set) var microphoneStatus: PermissionStatus = .notDetermined
    private(set) var accessibilityStatus: PermissionStatus = .notDetermined

    var allRequiredGranted: Bool {
        microphoneStatus.isGranted && accessibilityStatus.isGranted
    }

    private init() {
        refresh()
    }

    func refresh() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: microphoneStatus = .granted
        case .denied, .restricted: microphoneStatus = .denied
        case .notDetermined: microphoneStatus = .notDetermined
        @unknown default: microphoneStatus = .notDetermined
        }
        accessibilityStatus = AXIsProcessTrusted() ? .granted : .denied
    }

    func requestMicrophone() async {
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        refresh()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
