import Foundation
import AVFoundation
import UIKit
import OpenWhisperShared

/// Drives keyboard dictation: permission → record (shared pipeline) → pad →
/// cloud STT (OpenRouter) → result. All UI-facing callbacks fire on the main
/// thread. Reuses the shared `AudioCapturePipeline` (which also does the
/// silence auto-stop from the app's shared settings).
final class DictationController {
    enum Phase: Equatable {
        case idle
        case requestingPermission
        case recording
        case transcribing
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    var onPhaseChange: ((Phase) -> Void)?
    var onTranscription: ((String) -> Void)?

    var liveSamples: [Float] { pipeline.liveSamples }
    private(set) var elapsed: TimeInterval = 0
    private let maxRecordingSeconds: TimeInterval = 60

    private let pipeline = AudioCapturePipeline()
    private var recordingURL: URL?
    private var startDate: Date?
    private var elapsedTimer: Timer?
    private var didFinish = false
    /// Bumped on every start/cancel so stale transcription completions are dropped.
    private var transcriptionGeneration = 0
    private var interruptionObserver: (any NSObjectProtocol)?

    private let sharedDefaults = UserDefaults(suiteName: AppGroup.identifier)

    init() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard
                let info = notification.userInfo,
                let rawValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                let type = AVAudioSession.InterruptionType(rawValue: rawValue),
                type == .began
            else { return }
            // An interruption (e.g. a phone call) stops recording and transcribes
            // whatever was captured so far.
            self.stopAndTranscribe()
        }
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        stopElapsedTimer()
        pipeline.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    /// The current cloud API key (from the App Group suite, set in the app's
    /// Settings). Empty when not configured.
    var apiKey: String {
        sharedDefaults?.string(forKey: AppGroup.cloudApiKeyKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - Flow

    func requestPermissionAndStart() {
        guard phase == .idle || isFailed else { return }
        didFinish = false
        phase = .requestingPermission
        onPhaseChange?(phase)

        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                if granted {
                    guard self.phase == .requestingPermission, !self.didFinish else { return }
                    self.startRecording()
                } else {
                    self.fail("Microphone access was denied. Enable it in Settings.")
                }
            }
        }
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    private func startRecording() {
        didFinish = false
        transcriptionGeneration += 1
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)
        } catch {
            fail("Couldn't start the audio session.")
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyboardDictation-\(UUID().uuidString).wav")
        do {
            // Honor the app's shared silence auto-stop settings.
            let enabled = sharedDefaults?.object(forKey: AppGroup.autoStopOnSilenceKey) as? Bool ?? true
            let seconds = sharedDefaults?.object(forKey: AppGroup.autoStopSilenceSecondsKey) as? Double ?? 5.0
            pipeline.silenceAutoStopSeconds = enabled ? seconds : nil
            pipeline.onSilenceThresholdExceeded = { [weak self] in
                DispatchQueue.main.async { self?.stopAndTranscribe() }
            }
            try pipeline.start(outputURL: url)
        } catch {
            try? session.setActive(false, options: [])
            fail("Couldn't start recording.")
            return
        }
        recordingURL = url
        startDate = Date()
        elapsed = 0
        phase = .recording
        onPhaseChange?(phase)
        startElapsedTimer()
    }

    func stopAndTranscribe() {
        guard phase == .recording, !didFinish else { return }
        didFinish = true
        stopElapsedTimer()
        pipeline.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])

        guard let url = recordingURL else { return }
        phase = .transcribing
        onPhaseChange?(phase)

        let key = apiKey
        guard !key.isEmpty else {
            fail("No API key set — add it in OpenWhisper → Settings.")
            return
        }

        let language = sharedDefaults?.string(forKey: AppGroup.languageCodeKey)
        let generation = transcriptionGeneration
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let raw = try Data(contentsOf: url)
                let samples = WAVPCM.decode(raw) ?? []
                let padded = SilencePadding.pad(samples, sampleRate: 16_000)
                let wav = WAVPCM.encode(padded)
                let client = OpenRouterSTTClient(apiKey: key, language: language)
                let text = try await client.transcribe(wavData: wav)
                try? FileManager.default.removeItem(at: url)
                await MainActor.run {
                    guard let self else { return }
                    guard generation == self.transcriptionGeneration else { return }
                    self.phase = .idle
                    self.onPhaseChange?(self.phase)
                    self.onTranscription?(text)
                }
            } catch {
                try? FileManager.default.removeItem(at: url)
                let message = (error as? OpenRouterError)?.errorDescription ?? error.localizedDescription
                await MainActor.run {
                    guard let self else { return }
                    guard generation == self.transcriptionGeneration else { return }
                    self.fail(message)
                }
            }
        }
    }

    func cancel() {
        didFinish = true
        transcriptionGeneration += 1
        stopElapsedTimer()
        pipeline.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        if let url = recordingURL { try? FileManager.default.removeItem(at: url) }
        phase = .idle
        onPhaseChange?(phase)
    }

    // MARK: - Helpers

    private func fail(_ message: String) {
        pipeline.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        phase = .failed(message)
        onPhaseChange?(phase)
    }

    private func startElapsedTimer() {
        stopElapsedTimer()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let start = self.startDate else { return }
            self.elapsed = Date().timeIntervalSince(start)
            if self.elapsed >= self.maxRecordingSeconds {
                self.stopAndTranscribe()
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }
}
