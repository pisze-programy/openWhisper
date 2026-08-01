@preconcurrency import AVFoundation
import Foundation

nonisolated public final class AudioCapturePipeline {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var outputFile: AVAudioFile?
    private var inputSampleRate: Double = 48_000
    public private(set) var isRunning = false

    private static let livePreviewMaxSamples = 30 * 16_000
    private var _liveSamples: [Float] = []
    private let samplesLock = NSLock()

    /// When set, the pipeline stops monitoring after the mic has been silent
    /// for this many seconds (fires `onSilenceThresholdExceeded` once).
    public var silenceAutoStopSeconds: TimeInterval?
    /// Fired once when continuous silence reaches `silenceAutoStopSeconds`.
    /// Called on the audio thread — hop to the main actor before touching UI.
    public var onSilenceThresholdExceeded: (() -> Void)?
    /// RMS below this is treated as silence (raw amplitude, ~ room noise).
    public var silenceRMSThreshold: Float = 0.02

    public var liveSamples: [Float] {
        samplesLock.lock()
        defer { samplesLock.unlock() }
        return _liveSamples
    }

    private var silenceElapsed: TimeInterval = 0
    private var silenceTriggered = false

    public init() {}

    public func start(outputURL: URL) throws {
        samplesLock.lock()
        _liveSamples.removeAll(keepingCapacity: true)
        samplesLock.unlock()
        silenceElapsed = 0
        silenceTriggered = false
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        inputSampleRate = inputFormat.sampleRate

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
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

    public func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine.reset()
        outputFile = nil
        converter = nil
        isRunning = false
    }

    private func process(buffer: AVAudioPCMBuffer) {
        guard let converter, let outputFile, buffer.frameLength > 0 else { return }

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

        let hasOutput = status == .haveData || status == .inputRanDry
        if hasOutput, conversionError == nil, converted.frameLength > 0 {
            try? outputFile.write(from: converted)
            if let ch = converted.floatChannelData {
                let count = Int(converted.frameLength)
                samplesLock.lock()
                _liveSamples.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: count))
                if _liveSamples.count > Self.livePreviewMaxSamples {
                    _liveSamples.removeFirst(_liveSamples.count - Self.livePreviewMaxSamples)
                }
                samplesLock.unlock()
                updateSilenceMonitoring(samples: ch[0], count: count)
            }
        }
    }

    private func updateSilenceMonitoring(samples: UnsafePointer<Float>, count: Int) {
        guard let silenceAutoStopSeconds, !silenceTriggered, count > 0 else { return }
        var sum: Double = 0
        for i in 0..<count {
            let s = samples[i]
            sum += Double(s) * Double(s)
        }
        let rms = Float(sqrt(sum / Double(count)))
        if rms < silenceRMSThreshold {
            silenceElapsed += Double(count) / 16_000.0
            if silenceElapsed >= silenceAutoStopSeconds {
                silenceTriggered = true
                onSilenceThresholdExceeded?()
            }
        } else {
            silenceElapsed = 0
        }
    }
}
