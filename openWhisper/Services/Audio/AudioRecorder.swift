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
        startDate = nil

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
