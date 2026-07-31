import AVFoundation
import Foundation

/// Loads any AVFoundation-readable audio (wav / flac / mp3 / m4a / ...) into
/// a 16 kHz mono `[Float]` waveform in [-1, 1].
///
/// Uses `AVAudioConverter` so resampling + channel down-mix + bit-depth
/// conversion all happen in one pass.
public enum AudioLoader {
    public static func loadMono16k(at url: URL) throws -> [Float] {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw ParakeetError.audioLoadFailed(url: url, underlying: error)
        }

        let inFormat = file.processingFormat
        let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!

        let converter = AVAudioConverter(from: inFormat, to: outFormat)
        converter?.sampleRateConverterQuality = Int(AVAudioQuality.high.rawValue)

        let framesPerChunk: AVAudioFrameCount = 4096
        let inBuffer = AVAudioPCMBuffer(
            pcmFormat: inFormat, frameCapacity: framesPerChunk
        )!

        var output = [Float]()
        output.reserveCapacity(Int(file.length) * 16_000 / Int(inFormat.sampleRate) + 1024)

        while true {
            // Provider closure: feed one decoded chunk from the source file at a time.
            var isEndOfInput = false
            let inputBlock: AVAudioConverterInputBlock = { _, statusPtr in
                if isEndOfInput {
                    statusPtr.pointee = .endOfStream
                    return nil
                }
                do {
                    try file.read(into: inBuffer)
                } catch {
                    statusPtr.pointee = .endOfStream
                    return nil
                }
                if inBuffer.frameLength == 0 {
                    statusPtr.pointee = .endOfStream
                    isEndOfInput = true
                    return nil
                }
                statusPtr.pointee = .haveData
                return inBuffer
            }

            // Convert in blocks sized to the output rate so rate conversion is steady.
            let outCapacity = AVAudioFrameCount(
                ceil(Double(framesPerChunk) * outFormat.sampleRate / inFormat.sampleRate)
            ) + 64
            let outBuffer = AVAudioPCMBuffer(
                pcmFormat: outFormat, frameCapacity: outCapacity
            )!

            var converterError: NSError?
            let status = converter?.convert(
                to: outBuffer, error: &converterError, withInputFrom: inputBlock
            ) ?? .error

            if let err = converterError {
                throw ParakeetError.audioLoadFailed(url: url, underlying: err)
            }

            if outBuffer.frameLength > 0, let ch = outBuffer.floatChannelData {
                let ptr = ch[0]
                let count = Int(outBuffer.frameLength)
                output.append(contentsOf: UnsafeBufferPointer(start: ptr, count: count))
            }

            if status == .endOfStream || status == .error {
                break
            }
            if isEndOfInput && outBuffer.frameLength == 0 {
                break
            }
        }

        if output.isEmpty {
            throw ParakeetError.audioEmpty(url: url)
        }
        return output
    }
}
