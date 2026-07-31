@preconcurrency import AVFoundation
import Foundation

nonisolated final class AudioCapturePipeline {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var outputFile: AVAudioFile?
    private var inputSampleRate: Double = 48_000
    private(set) var isRunning = false

    private static let livePreviewMaxSamples = 30 * 16_000
    private(set) var liveSamples: [Float] = []

    func start(outputURL: URL) throws {
        liveSamples.removeAll(keepingCapacity: true)
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

    func stop() {
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
                liveSamples.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: count))
                if liveSamples.count > Self.livePreviewMaxSamples {
                    liveSamples.removeFirst(liveSamples.count - Self.livePreviewMaxSamples)
                }
            }
        }
    }
}
