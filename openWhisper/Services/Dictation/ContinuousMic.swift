import AVFoundation
import Foundation
import OpenWhisperShared

final class ContinuousMic {

    static let shared = ContinuousMic()
    private init() {}

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var outputFile: AVAudioFile?
    private var captureURL: URL?
    private var inputSampleRate: Double = 48_000
    private var writtenFrames: AVAudioFrameCount = 0

    private(set) var currentLevel: Float = 0

    var silenceAutoStopSeconds: TimeInterval?

    var onSilenceThresholdExceeded: (() -> Void)?
    private var silenceElapsed: TimeInterval = 0
    private var silenceTriggered = false

    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: true
    )!

    private var _running = false
    private var _capturing = false

    var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return _running }
    var isCapturing: Bool { lock.lock(); defer { lock.unlock() }; return _capturing }

    @discardableResult
    func start() -> Bool {
        lock.lock()
        if _running { lock.unlock(); return true }
        lock.unlock()

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers])
            if !session.isOtherAudioPlaying {
                try session.setActive(true)
            }
        } catch {
            return false
        }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            return false
        }
        inputSampleRate = inputFormat.sampleRate
        guard let conv = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            return false
        }
        converter = conv

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.handle(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return false
        }
        lock.lock(); _running = true; lock.unlock()
        return true
    }

    func stop() {
        lock.lock()
        let wasRunning = _running
        _running = false
        _capturing = false
        outputFile = nil
        captureURL = nil
        lock.unlock()

        guard wasRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    func restartIfNeeded() {
        lock.lock()
        let shouldRestart = _running && !engine.isRunning
        if shouldRestart {
            _running = false
            _capturing = false
            outputFile = nil
            captureURL = nil
        }
        lock.unlock()
        guard shouldRestart else { return }
        _ = start()
    }

    func beginCapture() throws -> URL {
        lock.lock()
        guard _running else { lock.unlock(); throw RecorderError.formatUnavailable }
        lock.unlock()

        let dir = AppGroup.containerURL.appendingPathComponent("dictation", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("capture-\(UUID().uuidString).wav")

        let file = try AVAudioFile(forWriting: url, settings: targetFormat.settings)

        lock.lock()
        outputFile = file
        captureURL = url
        writtenFrames = 0
        silenceElapsed = 0
        silenceTriggered = false
        _capturing = true
        lock.unlock()
        return url
    }

    @discardableResult
    func endCapture() -> URL? {
        lock.lock()
        let wasCapturing = _capturing
        _capturing = false
        let url = captureURL
        let frames = writtenFrames
        outputFile = nil
        captureURL = nil
        lock.unlock()

        guard wasCapturing, frames > 0 else {
            if let url { try? FileManager.default.removeItem(at: url) }
            return nil
        }
        return url
    }

    func cancelCapture() {
        let url = endCapture()
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {

        let rms = Self.rms(of: buffer)
        let db = rms > 0 ? 20 * log10(rms) : -160
        currentLevel = max(0, min(1, (db + 50) / 50))

        lock.lock()
        let shouldWrite = _capturing
        let target = outputFile
        let conv = converter
        lock.unlock()
        guard shouldWrite, let conv, let target, buffer.frameLength > 0 else { return }

        let ratio = targetFormat.sampleRate / (inputSampleRate > 0 ? inputSampleRate : targetFormat.sampleRate)
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var fed = false
        var conversionError: NSError?
        let status = conv.convert(to: out, error: &conversionError) { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard conversionError == nil, status == .haveData || status == .inputRanDry, out.frameLength > 0 else {
            return
        }

        do {
            try target.write(from: out)
            lock.lock()
            writtenFrames += out.frameLength
            lock.unlock()
        } catch {

        }

        monitorSilence(rms: rms, writtenFrames: out.frameLength)
    }

    private func monitorSilence(rms: Float, writtenFrames: AVAudioFrameCount) {
        lock.lock()
        guard let silenceAutoStopSeconds, _capturing, !silenceTriggered else {
            lock.unlock()
            return
        }
        if rms < 0.02 {
            silenceElapsed += Double(writtenFrames) / targetFormat.sampleRate
            if silenceElapsed >= silenceAutoStopSeconds {
                silenceTriggered = true
                lock.unlock()
                DispatchQueue.main.async { [weak self] in
                    self?.onSilenceThresholdExceeded?()
                }
                return
            }
        } else {
            silenceElapsed = 0
        }
        lock.unlock()
    }

    private static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        let channel = data[0]
        for i in 0..<frames {
            let s = channel[i]
            sum += s * s
        }
        return (sum / Float(frames)).squareRoot()
    }
}
