import OpenWhisperShared

@preconcurrency import AVFoundation
import Foundation

@MainActor @Observable
final class AudioRecorder {
    private(set) var isRecording: Bool = false
    private(set) var elapsed: TimeInterval = 0

    static let maxRecordingDuration: TimeInterval = SettingsStore.maxRecordingDuration

    var onAutoStop: (@MainActor () -> Void)?

    var liveSamples: [Float] { pipeline.liveSamples }

    private let pipeline = AudioCapturePipeline()
    private var fileURL: URL?
    private var autoStopTask: Task<Void, Never>?
    private var elapsedTask: Task<Void, Never>?
    private var startDate: Date?
    private var interruptionObserverRegistered = false

    private var previousSessionCategory: AVAudioSession.Category?
    private var previousSessionMode: AVAudioSession.Mode?
    private var previousSessionOptions: AVAudioSession.CategoryOptions?

    func start() async throws {
        guard !isRecording else { throw RecorderError.alreadyRecording }
        if let previous = fileURL {
            try? FileManager.default.removeItem(at: previous)
            fileURL = nil
        }
        elapsed = 0
        startDate = Date()

        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            throw RecorderError.permissionDenied
        }

        let session = AVAudioSession.sharedInstance()
        previousSessionCategory = session.category
        previousSessionMode = session.mode
        previousSessionOptions = session.categoryOptions
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Recording-\(UUID().uuidString).wav")
        if SettingsStore.silenceAutoStopEnabled {
            pipeline.silenceAutoStopSeconds = SettingsStore.silenceAutoStopSeconds
        } else {
            pipeline.silenceAutoStopSeconds = nil
        }
        // The `.measurement` mode has no AGC — boost the flat mic level so
        // normal speech clears the silence threshold and the STT gets a loud
        // recording. User-adjustable in Settings (default 5 = "Optimal").
        pipeline.inputGain = Float(SettingsStore.sharedMicGain)
        pipeline.onSilenceThresholdExceeded = { [weak self] in
            // Callback runs on the audio thread — hop to the main actor.
            Task { @MainActor [weak self] in
                self?.performAutoStop()
            }
        }
        do {
            try pipeline.start(outputURL: url)
        } catch {
            pipeline.stop()
            try? session.setActive(false, options: [])
            throw error
        }
        fileURL = url
        startDate = Date()
        isRecording = true

        registerForInterruptions()
        startElapsedUpdater()
        scheduleAutoStop()
    }

    func stop() throws -> URL {
        let wasRecording = isRecording
        if wasRecording {
            stopTasks()
            pipeline.stop()
            isRecording = false
            restoreAudioSession()
        }
        guard let fileURL else {
            throw RecorderError.noRecording
        }
        return fileURL
    }

    /// Stops the recording **visually immediately**, but keeps the mic capturing
    /// for `tail` seconds more so the end of the user's speech is not cut off
    /// when they release the button. The file is then finalised and returned.
    func stopAfterTail(_ tail: TimeInterval = 1.0) async throws -> URL {
        guard isRecording else { throw RecorderError.noRecording }
        // Immediate visual stop — the UI reflects "stopped" right away.
        isRecording = false
        stopTasks()
        // Keep the pipeline (and the audio session) alive for the tail so the
        // mic records the trailing speech into the same file.
        try? await Task.sleep(nanoseconds: UInt64(tail * 1_000_000_000))
        pipeline.stop()
        restoreAudioSession()
        guard let fileURL else {
            throw RecorderError.noRecording
        }
        return fileURL
    }

    private func registerForInterruptions() {
        guard !interruptionObserverRegistered else { return }
        interruptionObserverRegistered = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard isRecording else { return }
        guard
            let info = notification.userInfo,
            let rawValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: rawValue),
            type == .began
        else { return }

        stopTasks()
        pipeline.stop()
        onAutoStop?()
        isRecording = false
        restoreAudioSession()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func scheduleAutoStop() {
        autoStopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.maxRecordingDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.performAutoStop()
        }
    }

    private func performAutoStop() {
        guard isRecording else { return }
        stopTasks()
        pipeline.stop()
        onAutoStop?()
        isRecording = false
        restoreAudioSession()
    }

    private func restoreAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
        if let previousSessionCategory, let previousSessionMode, let previousSessionOptions {
            try? session.setCategory(previousSessionCategory, mode: previousSessionMode, options: previousSessionOptions)
        }
    }

    private func startElapsedUpdater() {
        elapsedTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled, let self, self.isRecording else { return }
                self.elapsed = Date().timeIntervalSince(self.startDate ?? Date())
            }
        }
    }

    private func stopTasks() {
        autoStopTask?.cancel()
        elapsedTask?.cancel()
        autoStopTask = nil
        elapsedTask = nil
    }
}
