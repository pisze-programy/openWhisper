import Foundation
import Combine
import UIKit
import OpenWhisperShared

@MainActor
final class KeyboardDictationModel: ObservableObject {
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var error: String?
    @Published var errorTitle: String?
    @Published var fullAccessNeeded = false
    @Published var elapsed: TimeInterval = 0

    let controller = DictationController()
    private var elapsedTimer: Timer?

    /// Set by the view controller so the transcribed text can be inserted into
    /// the host document (the model owns the transcription result).
    var onInsertText: ((String) -> Void)?

    /// Set by the view controller from its `hasFullAccess` flag.
    var isFullAccessGranted = true

    init() {
        controller.onPhaseChange = { [weak self] phase in self?.apply(phase) }
        controller.onTranscription = { [weak self] text in
            guard let self else { return }
            self.reset()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            self.onInsertText?(text)
        }
    }

    var liveSamples: [Float] { controller.liveSamples }

    func start() {
        guard isFullAccessGranted else {
            // Without Full Access the extension can't use the mic, network or
            // clipboard — explain clearly instead of failing with cryptic errors.
            isRecording = false
            isTranscribing = false
            error = "The keyboard uses a cloud model — it needs internet to dictate."
            errorTitle = "Full access needed:"
            fullAccessNeeded = true
            return
        }
        fullAccessNeeded = false
        controller.requestPermissionAndStart()
    }
    func stop() {
        controller.stopAndTranscribe()
    }
    func cancel() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        controller.cancel()
        reset()
    }

    private func apply(_ phase: DictationController.Phase) {
        switch phase {
        case .idle:
            reset()
        case .requestingPermission:
            error = nil
            isRecording = false
            isTranscribing = false
        case .recording:
            error = nil
            isRecording = true
            isTranscribing = false
            startTimer()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .transcribing:
            elapsedTimer?.invalidate()
            elapsedTimer = nil
            isRecording = false
            isTranscribing = true
        case .failed(let message):
            elapsedTimer?.invalidate()
            elapsedTimer = nil
            isRecording = false
            isTranscribing = false
            error = message
            // Style network failures like the full-access block: red title +
            // gray body.
            if message.localizedCaseInsensitiveContains("internet") || message.localizedCaseInsensitiveContains("connection") {
                errorTitle = "No internet connection:"
            } else {
                errorTitle = nil
            }
        }
    }

    private func startTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.elapsed = self?.controller.elapsed ?? 0
            }
        }
    }

    private func reset() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        isRecording = false
        isTranscribing = false
        error = nil
        errorTitle = nil
        fullAccessNeeded = false
        elapsed = 0
    }
}
