// @preconcurrency: AVFAudio is not fully Sendable-annotated; the import
// suppresses @Sendable capture warnings that are irrelevant on the audio
// thread (all state here is confined to AudioCapturePipeline).
@preconcurrency import AVFoundation
import Foundation

/// Errors surfaced by `AudioRecorder`.
enum RecorderError: LocalizedError {
    case permissionDenied
    case formatUnavailable
    case noRecording
    case alreadyRecording

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone access was denied. Enable it in Settings."
        case .formatUnavailable:
            return "Couldn't set up the recording format."
        case .noRecording:
            return "There is no recording to stop."
        case .alreadyRecording:
            return "A recording is already in progress."
        }
    }
}

/// Records 16 kHz mono WAV audio from the microphone.
///
/// The AVAudioEngine tap fires on an audio thread; conversion and file
/// writes happen in `AudioCapturePipeline`, which owns no MainActor state,
/// so the tap never touches the main actor directly. MainActor-visible
/// state (`isRecording`, `elapsed`) is only changed from `start`/`stop`
/// and from MainActor tasks.
@MainActor @Observable
final class AudioRecorder {
    private(set) var isRecording: Bool = false
    private(set) var elapsed: TimeInterval = 0

    /// Longest allowed recording, in seconds.
    static let maxRecordingDuration: TimeInterval = SettingsStore.maxRecordingDuration

    /// Called on the main actor when `maxRecordingDuration` elapses.
    var onAutoStop: (@MainActor () -> Void)?

    private let pipeline = AudioCapturePipeline()
    private var fileURL: URL?
    private var autoStopTask: Task<Void, Never>?
    private var elapsedTask: Task<Void, Never>?
    private var startDate: Date?
    private var interruptionObserverRegistered = false

    /// Starts recording to a fresh temporary WAV file.
    func start() async throws {
        guard !isRecording else { throw RecorderError.alreadyRecording }
        // Drop the previous temp file, if any.
        if let previous = fileURL {
            try? FileManager.default.removeItem(at: previous)
            fileURL = nil
        }
        elapsed = 0
        startDate = nil

        guard await AVAudioApplication.requestRecordPermission() else {
            throw RecorderError.permissionDenied
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Recording-\(UUID().uuidString).wav")
        do {
            try pipeline.start(outputURL: url)
        } catch {
            // Don't leak an active session or a running engine tap when
            // setup fails.
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

    /// Stops recording and returns the recorded file's URL.
    /// Safe to call after auto-stop already fired.
    func stop() throws -> URL {
        if isRecording {
            stopTasks()
            pipeline.stop()
            isRecording = false
            try? AVAudioSession.sharedInstance().setActive(false, options: [])
        }
        guard let fileURL else {
            throw RecorderError.noRecording
        }
        return fileURL
    }

    // MARK: - Interruptions

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

    /// Mirrors `performAutoStop()` for system interruptions (phone call,
    /// Siri, Control Center). `onAutoStop` is invoked while `isRecording` is
    /// still true so the view's handler can call `stop()` to obtain the file
    /// URL — same ordering as the auto-stop path.
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
        // IMPORTANT: notify the view BEFORE clearing isRecording.
        onAutoStop?()
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [])
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Internals

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
        // IMPORTANT: notify the view BEFORE clearing isRecording — the view's
        // handler calls stop() (guarded on isRecording) to obtain the file URL.
        onAutoStop?()
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [])
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

/// AVAudioEngine tap → 16 kHz mono Float32 conversion → WAV file writing.
///
/// Runs entirely off the main actor (the tap fires on an audio thread), so
/// it intentionally owns no MainActor state.
nonisolated final class AudioCapturePipeline {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var outputFile: AVAudioFile?
    private var inputSampleRate: Double = 48_000
    private(set) var isRunning = false

    func start(outputURL: URL) throws {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        inputSampleRate = inputFormat.sampleRate

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw RecorderError.formatUnavailable
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecorderError.formatUnavailable
        }
        self.converter = converter

        let file = try AVAudioFile(forWriting: outputURL, settings: targetFormat.settings)
        self.outputFile = file

        let bufferSize = AVAudioFrameCount(max(inputFormat.sampleRate * 0.1, 4_096))
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine.reset()
        outputFile = nil
        converter = nil
        isRunning = false
    }

    /// Called on the audio thread for each input buffer.
    private func process(buffer: AVAudioPCMBuffer) {
        guard let converter, let outputFile, buffer.frameLength > 0 else { return }

        // Output capacity scales with the sample-rate ratio, plus headroom
        // for the converter's internal resampler latency.
        let ratio = 16_000 / (inputSampleRate > 0 ? inputSampleRate : 16_000)
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 4_096
        guard let converted = AVAudioPCMBuffer(
            pcmFormat: converter.outputFormat,
            frameCapacity: capacity
        ) else {
            return
        }

        var fed = false
        var conversionError: NSError?
        let status = converter.convert(to: converted, error: &conversionError) { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if status == .haveData, conversionError == nil, converted.frameLength > 0 {
            // A tap callback can't throw; a dropped buffer here is a
            // best-effort loss rather than a crash.
            try? outputFile.write(from: converted)
        }
    }
}
