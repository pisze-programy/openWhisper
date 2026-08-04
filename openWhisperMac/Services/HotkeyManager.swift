import AppKit
import Foundation

/// Global hotkey handling via `NSEvent` monitors. Hold right ⌘+⌥ to start
/// recording, release to stop; ESC cancels (optionally requiring a second press).
/// Hold right ⌥ and tap right ⇧ to cycle the formatting style.
/// Left side: hold left ⌘+⌥ to translate + reformat the selected text; hold left
/// ⌘ and tap left ⇧ to swap the translation FROM/TO pair.
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
    /// Fired once per left ⌘+⌥ press: translate + reformat the selected text.
    var onTranslateReformat: (() -> Void)?
    /// Fired when left ⇧ is tapped while left ⌘ is held: swap the FROM/TO pair.
    var onSwapTranslateDirection: (() -> Void)?

    // Right-side (recording + style cycling) state.
    private var rightCmdDown = false
    private var rightOptDown = false
    private var rightShiftDown = false
    private var isRecordingActive = false
    private var lastEscapePress: Date?
    /// True when a style cycle happened during the current right-⌥ hold.
    private var styleSessionDidCycle = false

    // Left-side (translate + reformat) state.
    private var leftCmdDown = false
    private var leftOptDown = false
    private var leftShiftDown = false
    private var leftReformatTriggered = false

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
        var didSwapTranslate = false
        switch event.keyCode {
        case 54: // right command
            rightCmdDown = flags.contains(.command)
        case 61: // right option
            let wasDown = rightOptDown
            rightOptDown = flags.contains(.option)
            if rightOptDown && !wasDown {
                // Option freshly pressed: begin a new style-cycling session.
                styleSessionDidCycle = false
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
        case 55: // left command
            leftCmdDown = flags.contains(.command)
        case 58: // left option
            let wasDown = leftOptDown
            leftOptDown = flags.contains(.option)
            if leftOptDown && !wasDown {
                // Option freshly pressed: a fresh ⌘+⌥ chord may trigger again.
                leftReformatTriggered = false
            }
        case 56: // left shift
            let wasDown = leftShiftDown
            leftShiftDown = flags.contains(.shift)
            // Rising edge only: hold left ⌘, tap left ⇧ to swap the pair.
            didSwapTranslate = leftShiftDown && !wasDown
        default:
            break
        }

        if didCycleStyle && rightOptDown && !rightCmdDown && !isRecordingActive {
            styleSessionDidCycle = true
            onCycleStyle?()
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

        if didSwapTranslate && leftCmdDown && !leftOptDown && !isRecordingActive {
            onSwapTranslateDirection?()
        }

        if leftCmdDown && leftOptDown && !leftShiftDown && !isRecordingActive {
            if !leftReformatTriggered {
                leftReformatTriggered = true
                onTranslateReformat?()
            }
        } else if !leftCmdDown || !leftOptDown {
            leftReformatTriggered = false
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
        leftCmdDown = false
        leftOptDown = false
        leftShiftDown = false
        leftReformatTriggered = false
    }
}
