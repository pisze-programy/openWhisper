import AppKit
import Foundation

/// Global hotkey handling via `NSEvent` monitors. Hold right ⌘+⌥ to start
/// recording, release to stop; ESC cancels (optionally requiring a second press).
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    var requireSecondEscapeToCancel = false

    var onRecordStart: (() -> Void)?
    var onRecordStop: (() -> Void)?
    var onCancel: (() -> Void)?

    private var rightCmdDown = false
    private var rightOptDown = false
    private var isRecordingActive = false
    private var lastEscapePress: Date?

    private init() {}

    func start() {
        NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handle(event)
        }
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    private func handle(_ event: NSEvent) {
        if event.type == .keyDown && event.keyCode == 53 {
            handleEscape()
            return
        }

        guard event.type == .flagsChanged else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch event.keyCode {
        case 54: // right command
            rightCmdDown = flags.contains(.command)
        case 61: // right option
            rightOptDown = flags.contains(.option)
        default:
            break
        }

        if rightCmdDown && rightOptDown {
            if !isRecordingActive {
                isRecordingActive = true
                onRecordStart?()
            }
        } else if isRecordingActive {
            isRecordingActive = false
            rightCmdDown = false
            rightOptDown = false
            onRecordStop?()
        }
    }

    private func handleEscape() {
        guard isRecordingActive else { return }
        if requireSecondEscapeToCancel {
            let now = Date()
            if let last = lastEscapePress, now.timeIntervalSince(last) < 1.5 {
                lastEscapePress = nil
                onCancel?()
            } else {
                lastEscapePress = now
            }
        } else {
            onCancel?()
        }
    }

    func reset() {
        isRecordingActive = false
        rightCmdDown = false
        rightOptDown = false
    }
}
