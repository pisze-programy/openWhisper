import Foundation
import Combine
import OpenWhisperShared

@MainActor
final class KeyboardDictationModel: ObservableObject {
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var error: String?
    @Published var elapsed: TimeInterval = 0

    let controller = DictationController()
    private var elapsedTimer: Timer?

    /// Set by the view controller so the transcribed text can be inserted into
    /// the host document (the model owns the transcription result).
    var onInsertText: ((String) -> Void)?

    init() {
        controller.onPhaseChange = { [weak self] phase in self?.apply(phase) }
        controller.onTranscription = { [weak self] text in
            guard let self else { return }
            self.reset()
            self.onInsertText?(text)
        }
    }

    var liveSamples: [Float] { controller.liveSamples }

    func start() {
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
        elapsed = 0
    }
}
