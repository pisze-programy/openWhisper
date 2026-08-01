import Foundation

/// Minimal WAV codec for the 16 kHz mono files our pipeline writes
/// (32-bit IEEE float) and the 16-bit PCM we re-encode for the cloud STT.
public enum WAVPCM {
    /// Decodes a WAV into Float samples in [-1, 1]. Supports 16-bit PCM
    /// (format tag 1) and 32-bit IEEE float (format tag 3), mono only.
    public static func decode(_ data: Data) -> [Float]? {
        guard data.count > 44 else { return nil }

        func u16(_ o: Int) -> UInt16? {
            guard o + 2 <= data.count else { return nil }
            return data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt16.self) }
        }
        func u32(_ o: Int) -> UInt32? {
            guard o + 4 <= data.count else { return nil }
            return data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) }
        }

        guard let channels = u16(22), channels == 1 else { return nil }
        guard let formatTag = u16(20), formatTag == 1 || formatTag == 3 else { return nil }

        // Walk chunks to find the "data" chunk.
        var offset = 12 // skip "RIFF" size "WAVE"
        while offset + 8 <= data.count {
            let chunkID = String(decoding: data[offset..<offset + 4], as: UTF8.self)
            guard let size = u32(offset + 4) else { return nil }
            let payloadStart = offset + 8
            if chunkID == "data" {
                let payload = data[payloadStart..<min(payloadStart + Int(size), data.count)]
                return samples(from: payload, formatTag: formatTag)
            }
            offset = payloadStart + Int(size) + (Int(size) % 2) // pad to even
        }
        return nil
    }

    private static func samples(from payload: Data, formatTag: UInt16) -> [Float]? {
        switch formatTag {
        case 1: // PCM 16-bit
            guard payload.count % 2 == 0 else { return nil }
            var out = [Float]()
            out.reserveCapacity(payload.count / 2)
            payload.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                let ptr = raw.bindMemory(to: Int16.self)
                for i in 0..<(payload.count / 2) {
                    out.append(Float(ptr[i]) / 32768.0)
                }
            }
            return out
        case 3: // IEEE float 32-bit
            guard payload.count % 4 == 0 else { return nil }
            var out = [Float]()
            out.reserveCapacity(payload.count / 4)
            payload.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                let ptr = raw.bindMemory(to: Float32.self)
                for i in 0..<(payload.count / 4) {
                    out.append(ptr[i])
                }
            }
            return out
        default:
            return nil
        }
    }

    /// Encodes Float samples in [-1, 1] into a 16-bit PCM mono WAV.
    public static func encode(_ samples: [Float], sampleRate: Int = 16_000) -> Data {
        var data = Data()
        let byteCount = samples.count * 2
        func append(_ s: String) { data.append(contentsOf: s.utf8) }
        func appendU32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func appendU16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }

        append("RIFF")
        appendU32(UInt32(36 + byteCount))
        append("WAVE")
        append("fmt ")
        appendU32(16)
        appendU16(1)              // PCM
        appendU16(1)              // mono
        appendU32(UInt32(sampleRate))
        appendU32(UInt32(sampleRate * 2)) // byte rate
        appendU16(2)              // block align
        appendU16(16)             // bits per sample
        append("data")
        appendU32(UInt32(byteCount))

        var pcm = [Int16]()
        pcm.reserveCapacity(samples.count)
        for s in samples {
            let clamped = max(-1, min(1, s))
            pcm.append(Int16(clamped * 32767))
        }
        pcm.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }
}
