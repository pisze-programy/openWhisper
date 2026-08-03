import AppKit
import Foundation

/// Cancels an in-progress dictation when the Mac is about to sleep and re-warms
/// the audio capture graph after wake (the input device may have changed).
@MainActor
final class SystemSleepObserver {
    private let recorder: MacRecorder
    private let orchestrator: DictationOrchestrator
    private var observers: [NSObjectProtocol] = []

    init(recorder: MacRecorder, orchestrator: DictationOrchestrator) {
        self.recorder = recorder
        self.orchestrator = orchestrator
    }

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.handleWillSleep() }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.handleDidWake() }
            },
        ]
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
        }
        observers = []
    }

    private func handleWillSleep() {
        guard orchestrator.phase != .idle else { return }
        orchestrator.cancel()
    }

    private func handleDidWake() {
        Task { await recorder.prewarm() }
    }
}
