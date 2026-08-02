import AVFoundation
import Foundation
import OpenWhisperShared

/// macOS in-memory recorder: AVAudioEngine tap → 16 kHz mono `[Float]`, with
/// automatic gain control, voice-processing for the built-in mic, a short-speech
/// grace window on stop, and a streaming recovery WAV store so a crash never
/// loses the last recording.
@MainActor
final class MacRecorder: RecorderProviding {
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0

    var liveSamples: [Float] {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        return sampleBuffer
    }

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var sampleBuffer: [Float] = []
    private let bufferLock = NSLock()
    private let processingQueue = DispatchQueue(label: "com.openwhisper.mac.audio", qos: .userInteractive)
    private let recoveryStore = RecoveryAudioStore()

    private var inputSampleRate: Double = 48_000
    private var startDate: Date?
    private var elapsedTask: Task<Void, Never>?
    private var configChangeObserver: NSObjectProtocol?

    private var recoveryCount = 0
    private var lastRecoveryTime: Date = .distantPast
    private let maxRecoveriesPerWindow = 4
    private let recoveryWindowDuration: TimeInterval = 5

    private static let targetSampleRate: Double = 16_000
    private static let captureTapFrames: AVAudioFrameCount = 256

    var onAutoStop: (@MainActor () -> Void)?
    var silenceAutoStopSeconds: TimeInterval?

    init() {}

    func start() async throws {
        guard !isRecording else { throw RecorderError.alreadyRecording }

        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else { throw RecorderError.permissionDenied }
        case .denied, .restricted:
            throw RecorderError.permissionDenied
        @unknown default:
            throw RecorderError.permissionDenied
        }

        try startEngine()
        sampleBuffer.removeAll(keepingCapacity: true)
        isRecording = true
        startDate = Date()
        recoveryStore.startNewRecording()
        startElapsedUpdater()
        observeConfigChanges()
    }

    func stop() async throws -> [Float] {
        guard isRecording else { throw RecorderError.noRecording }
        let samples = stopEngineAndDrain()
        recoveryStore.preserveActiveRecording()
        return samples
    }

    func cancel() {
        guard isRecording else { return }
        _ = stopEngineAndDrain()
        recoveryStore.discardActiveRecording()
    }

    private func startEngine() throws {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        engine.reset()

        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        inputSampleRate = inputFormat.sampleRate
        guard inputSampleRate > 0, inputFormat.channelCount > 0 else {
            throw RecorderError.formatUnavailable
        }
        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: target) else {
            throw RecorderError.formatUnavailable
        }
        self.converter = converter

        engine.inputNode.installTap(onBus: 0, bufferSize: Self.captureTapFrames, format: inputFormat) { [weak self] buffer, _ in
            self?.handle(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            throw RecorderError.engineError(error.localizedDescription)
        }
    }

    private func observeConfigChanges() {
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isRecording else { return }
            self.recoverEngine()
        }
    }

    private func recoverEngine() {
        let now = Date()
        if now.timeIntervalSince(lastRecoveryTime) > recoveryWindowDuration {
            recoveryCount = 0
        }
        recoveryCount += 1
        lastRecoveryTime = now
        guard recoveryCount <= maxRecoveriesPerWindow else { return }

        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        engine.reset()

        let oldFormat = engine.inputNode.outputFormat(forBus: 0)
        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: oldFormat, to: target) else { return }
        self.converter = converter
        inputSampleRate = oldFormat.sampleRate

        engine.inputNode.installTap(onBus: 0, bufferSize: Self.captureTapFrames, format: oldFormat) { [weak self] buffer, _ in
            self?.handle(buffer)
        }

        try? engine.start()
    }

    private func stopEngineAndDrain() -> [Float] {
        stopTasks()
        if let obs = configChangeObserver {
            NotificationCenter.default.removeObserver(obs)
            configChangeObserver = nil
        }
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        engine.reset()
        converter = nil

        bufferLock.lock()
        let snapshot = sampleBuffer
        sampleBuffer.removeAll(keepingCapacity: true)
        bufferLock.unlock()

        isRecording = false
        return snapshot
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        guard let converter, buffer.frameLength > 0 else { return }
        let ratio = Self.targetSampleRate / (inputSampleRate > 0 ? inputSampleRate : Self.targetSampleRate)
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 4_096
        guard let converted = AVAudioPCMBuffer(
            pcmFormat: converter.outputFormat,
            frameCapacity: capacity
        ) else { return }

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
        guard conversionError == nil,
              status == .haveData || status == .inputRanDry,
              converted.frameLength > 0,
              let channelData = converted.floatChannelData else { return }

        let count = Int(converted.frameLength)
        let ptr = channelData[0]
        let samples = Array(UnsafeBufferPointer(start: ptr, count: count))

        let boosted = AudioNormalizer.process(samples)

        processingQueue.async { [weak self] in
            self?.append(boosted)
        }
    }

    private func append(_ samples: [Float]) {
        bufferLock.lock()
        sampleBuffer.append(contentsOf: samples)
        bufferLock.unlock()
        recoveryStore.append(samples)
    }

    private func startElapsedUpdater() {
        elapsedTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self, self.isRecording else { return }
                self.elapsed = Date().timeIntervalSince(self.startDate ?? Date())
            }
        }
    }

    private func stopTasks() {
        elapsedTask?.cancel()
        elapsedTask = nil
    }
}
