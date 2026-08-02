import Foundation
import UIKit
import OpenWhisperShared

@MainActor
@Observable
final class ResidentDictation {

    static weak var shared: ResidentDictation?

    enum Phase: Equatable {
        case idle
        case starting
        case ready
        case recording
        case transcribing
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    private let transcription: TranscriptionService
    private let modelDownload: ModelDownloadManager
    private let mic = ContinuousMic.shared
    private let liveActivity = DictationLiveActivityManager()

    init(transcription: TranscriptionService, modelDownload: ModelDownloadManager) {
        self.transcription = transcription
        self.modelDownload = modelDownload
    }

    var residentEnabled: Bool {
        get {
            UserDefaults(suiteName: AppGroup.identifier)?.object(forKey: "resident.enabled") as? Bool ?? true
        }
        set {
            UserDefaults(suiteName: AppGroup.identifier)?.set(newValue, forKey: "resident.enabled")
            if newValue { start() } else { stop() }
        }
    }

    private var commandPollTimer: Timer?
    private var levelPublishTimer: Timer?
    private var heartbeatTimer: Timer?
    private var wired = false

    func start() {
        wireBridge()
        startHeartbeat()
        guard residentEnabled else { return }
        phase = .starting

        guard UIApplication.shared.applicationState == .active else {
            AppGroup.publishEngineState(.loading)
            return
        }

        let micOK = mic.start()
        if micOK {
            phase = .ready
            AppGroup.publishEngineState(.ready)
        } else {
            phase = .failed("Microphone refused — open OpenWhisper in the foreground once.")
            AppGroup.publishEngineState(.error, error: phaseError)
        }
        publishInPlaceReady()
    }

    func reactivate() {
        guard residentEnabled else { return }
        mic.restartIfNeeded()
        if !mic.isRunning { _ = mic.start() }

        Task { await transcription.warmUp() }
        publishInPlaceReady()
        startHeartbeat()
    }

    func stop() {
        mic.silenceAutoStopSeconds = nil
        mic.onSilenceThresholdExceeded = nil
        mic.stop()
        stopHeartbeat()
        stopCommandPolling()
        stopLevelPublishing()
        phase = .idle
        AppGroup.publishEngineState(.unknown)
        publishInPlaceReady()
    }

    private var phaseError: String? {
        if case .failed(let message) = phase { return message }
        return nil
    }

    private func publishInPlaceReady() {
        let ready = mic.isRunning && (transcription.isModelReady || modelDownload.isReady)
        AppGroup.setInPlaceReady(ready)
    }

    private func wireBridge() {
        guard !wired else { return }
        wired = true

        DarwinBridge.observe(.startRecording) { [weak self] in
            self?.handleCommand(.start)
        }
        DarwinBridge.observe(.stopRecording) { [weak self] in
            self?.handleCommand(.stop)
        }
        DarwinBridge.observe(.cancelRecording) { [weak self] in
            self?.handleCommand(.cancel)
        }
        DarwinBridge.observe(.ping) { [weak self] in
            self?.handlePing()
        }
        DarwinBridge.observe(.keepWarm) { [weak self] in
            self?.handleKeepWarm()
        }
    }

    private func startHeartbeat() {
        AppGroup.stampHostHeartbeat()
        guard heartbeatTimer == nil else { return }
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            AppGroup.stampHostHeartbeat()
        }
        heartbeatTimer?.tolerance = 0.3
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func startCommandPolling() {
        stopCommandPolling()
        commandPollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard let command = AppGroup.readCommand() else { return }
            if command.stamp > self.lastHandledCommandStamp {
                self.lastHandledCommandStamp = command.stamp
                self.handleCommand(command.action)
            }
        }
        commandPollTimer?.tolerance = 0.05
    }

    private func stopCommandPolling() {
        commandPollTimer?.invalidate()
        commandPollTimer = nil
    }

    private var lastHandledCommandStamp: TimeInterval = 0

    private var lastCommandAction: AppGroup.Command.Action?
    private var lastCommandTime: Date?

    private func handleCommand(_ action: AppGroup.Command.Action) {

        if action == lastCommandAction,
           let last = lastCommandTime,
           Date().timeIntervalSince(last) < 0.3 {
            return
        }
        lastCommandAction = action
        lastCommandTime = Date()
        switch action {
        case .start: beginRecording()
        case .stop: endRecordingAndTranscribe()
        case .cancel: cancelRecording()
        }
    }

    private func handlePing() {
        AppGroup.stampHostHeartbeat()
        DarwinBridge.post(.pong)
        AppGroup.publishEngineState(mapPhaseToEngineState())
    }

    private func handleKeepWarm() {
        AppGroup.stampHostHeartbeat()
        if !mic.isRunning { _ = mic.start() }
        Task { await transcription.warmUp() }
        publishInPlaceReady()
    }

    private func mapPhaseToEngineState() -> AppGroup.EngineState {
        switch phase {
        case .idle, .starting: return .loading
        case .ready: return .ready
        case .recording: return .recording
        case .transcribing: return .transcribing
        case .failed: return .error
        }
    }

    private var recordingStartedAt: Date?

    private func beginRecording() {
        guard phase == .ready || phase == .starting else { return }
        guard mic.isRunning else {

            AppGroup.publishEngineState(.error, error: "Open OpenWhisper once in the foreground.")
            return
        }

        mic.silenceAutoStopSeconds = 4.0
        mic.onSilenceThresholdExceeded = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.phase == .recording else { return }
                self.endRecordingAndTranscribe()
            }
        }
        do {
            try mic.beginCapture()
        } catch {
            AppGroup.publishEngineState(.error, error: "Couldn't start recording.")
            return
        }
        recordingStartedAt = Date()
        phase = .recording
        AppGroup.publishEngineState(.recording)
        startCommandPolling()
        startLevelPublishing()
        liveActivity.startRecording(at: recordingStartedAt ?? Date())
    }

    private func startLevelPublishing() {
        stopLevelPublishing()
        levelPublishTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            AppGroup.publishLevel(self.mic.currentLevel)
        }
        levelPublishTimer?.tolerance = 0.05
    }

    private func stopLevelPublishing() {
        levelPublishTimer?.invalidate()
        levelPublishTimer = nil
    }

    private func endRecordingAndTranscribe() {
        guard phase == .recording else {

            return
        }
        recordingStartedAt = nil
        mic.silenceAutoStopSeconds = nil
        mic.onSilenceThresholdExceeded = nil
        phase = .transcribing
        AppGroup.publishEngineState(.transcribing)
        stopCommandPolling()
        stopLevelPublishing()
        liveActivity.showTranscribing()

        guard let url = mic.endCapture() else {
            finishWithNote("No speech detected")
            return
        }

        let audioURL = url
        Task {
            do {
                let result = try await transcription.transcribe(audioURL: audioURL)
                try? FileManager.default.removeItem(at: audioURL)
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    finishWithNote("No speech detected")
                } else {
                    AppGroup.writeDictation(text: text)
                    DarwinBridge.post(.resultReady)
                    finishPhase(.ready)
                }
            } catch TranscriptionError.noAudio {
                try? FileManager.default.removeItem(at: audioURL)
                finishWithNote("No speech detected")
            } catch {
                try? FileManager.default.removeItem(at: audioURL)
                AppGroup.publishEngineState(.error, error: error.localizedDescription)
                finishPhase(.failed(error.localizedDescription))
                DarwinBridge.post(.stateChanged)
            }
        }
    }

    private func cancelRecording() {
        recordingStartedAt = nil
        mic.silenceAutoStopSeconds = nil
        mic.onSilenceThresholdExceeded = nil
        mic.cancelCapture()
        stopCommandPolling()
        stopLevelPublishing()
        liveActivity.end()
        finishPhase(.ready)
        AppGroup.publishEngineState(.ready)
    }

    func stopFromLiveActivity() {
        switch phase {
        case .recording:
            endRecordingAndTranscribe()
        case .transcribing:
            liveActivity.end()
        default:
            liveActivity.end()
        }
    }

    private func finishWithNote(_ note: String) {
        AppGroup.writeDictation(text: "", note: note)
        DarwinBridge.post(.resultReady)
        liveActivity.end(note: note)
        finishPhase(.ready)
    }

    private func finishPhase(_ phase: Phase) {
        self.phase = phase
        AppGroup.publishEngineState(mapPhaseToEngineState())
        DarwinBridge.post(.stateChanged)
        if case .ready = phase {
            liveActivity.end()
        }
        if case .failed = phase {
            liveActivity.end()
        }
    }
}
