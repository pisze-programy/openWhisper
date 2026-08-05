import AppKit
import Foundation

/// Global hotkey handling via `NSEvent` monitors. Hold right ⌘+⌥ to start
/// recording, release to stop; ESC cancels (optionally requiring a second press).
/// Hold right ⌥ and tap right ⇧ to cycle the formatting style.
/// Press FN + right ⌥ to translate + reformat the copied text — fires on the
/// press (either key order), not on release.
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    var requireSecondEscapeToCancel = false

    var onRecordStart: (() -> Void)?
    var onRecordStop: (() -> Void)?
    var onCancel: (() -> Void)?
    var onCycleStyle: (() -> Void)?
    /// Fired when the style-switch chord is released after at least one cycle —
    /// the caller should persist the selection here (no autosave while cycling).
    var onStyleCycleEnd: (() -> Void)?
    /// Fired once per FN + right ⌥ press: translate + reformat the copied text.
    var onTranslateReformat: (() -> Void)?

    private var rightCmdDown = false
    private var rightOptDown = false
    private var rightShiftDown = false
    private var isRecordingActive = false
    private var lastEscapePress: Date?
    /// True when a style cycle happened during the current right-⌥ hold.
    private var styleSessionDidCycle = false
    /// True once FN + right ⌥ has fired for the current right-⌥ hold.
    private var translateTriggered = false

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

        var didCycleStyle = false
        switch event.keyCode {
        case 54: // right command
            rightCmdDown = flags.contains(.command)
        case 61: // right option
            let wasDown = rightOptDown
            rightOptDown = flags.contains(.option)
            if rightOptDown && !wasDown {
                // Option freshly pressed: begin a new style-cycling session.
                styleSessionDidCycle = false
                translateTriggered = false
            } else if !rightOptDown && wasDown && styleSessionDidCycle {
                // Option released after cycling: persist the selection once.
                styleSessionDidCycle = false
                onStyleCycleEnd?()
            }
        case 60: // right shift
            let wasDown = rightShiftDown
            rightShiftDown = flags.contains(.shift)
            // Rising edge only: hold right ⌥, tap right ⇧ to cycle one style.
            didCycleStyle = rightShiftDown && !wasDown
        default:
            break
        }

        if didCycleStyle && rightOptDown && !rightCmdDown && !isRecordingActive {
            styleSessionDidCycle = true
            onCycleStyle?()
        }

        // FN + right ⌥ → translate + reformat. Fires once per right-⌥ hold, on
        // the press (either key order), regardless of release. Right ⌘ is not
        // involved, so the STT chord (right ⌘+⌥) never intercepts it.
        if rightOptDown && !rightCmdDown && flags.contains(.function) && !isRecordingActive {
            if !translateTriggered {
                translateTriggered = true
                onTranslateReformat?()
            }
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
            // A style cycle started before the recording chord (right ⌥ was
            // held without ⌘) — persist it so it survives a restart instead of
            // being dropped by the record-stop reset above.
            if styleSessionDidCycle {
                styleSessionDidCycle = false
                onStyleCycleEnd?()
            }
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
        rightShiftDown = false
        styleSessionDidCycle = false
        translateTriggered = false
    }
}
