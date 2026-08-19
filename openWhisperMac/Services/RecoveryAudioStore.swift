import Foundation
import OpenWhisperShared

/// Streams the live recording to a recovery WAV on disk so an audio-engine crash
/// or app quit never loses the user's last dictation. Written asynchronously on
/// a serial utility queue so the audio path is never blocked. Raw audio is
/// excluded from iCloud/Time Machine backups.
final class RecoveryAudioStore {
    private let directory: URL
    private let writeQueue = DispatchQueue(label: "com.openwhisper.mac.recovery", qos: .utility)

    private var activeFile: FileHandle?
    private var activeURL: URL?
    private var writtenFrames: Int = 0

    static let sampleRate: Int = 16_000

    init() {
        let base = AppGroup.containerURL
        directory = base.appendingPathComponent("dictation-recovery", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        excludeFromBackup(directory)
    }

    private func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    func startNewRecording() {
        writeQueue.sync {
            if let url = activeURL {
                try? FileManager.default.removeItem(at: url)
            }
            activeFile?.closeFile()
            let url = directory.appendingPathComponent("active-recovery-\(UUID().uuidString).wav")
            FileManager.default.createFile(atPath: url.path, contents: nil)
            activeURL = url
            activeFile = try? FileHandle(forWritingTo: url)
            writtenFrames = 0
            writeHeaderIfNeeded()
        }
    }

    func append(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        writeQueue.async { [weak self] in
            guard let self, let file = self.activeFile else { return }
            var pcm = Data(capacity: samples.count * 2)
            for sample in samples {
                let clamped = max(-1, min(1, sample))
                var value = Int16(clamped * 32767)
                withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
            }
            file.write(pcm)
            self.writtenFrames += samples.count
        }
    }

    func preserveActiveRecording() {
        writeQueue.sync {
            finalizeHeader()
            activeFile?.closeFile()
            activeFile = nil
            activeURL = nil
        }
    }

    func discardActiveRecording() {
        writeQueue.sync {
            activeFile?.closeFile()
            activeFile = nil
            if let url = activeURL {
                try? FileManager.default.removeItem(at: url)
            }
            activeURL = nil
            writtenFrames = 0
        }
    }

    /// Latest preserved recovery recording URL, if any.
    var latestRecoveryURL: URL? {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls
            .filter { $0.pathExtension == "wav" }
            .sorted { left, right in
                let l = (try? left.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let r = (try? right.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return l > r
            }
            .first
    }

    // MARK: - WAV plumbing

    private func writeHeaderIfNeeded() {
        guard let url = activeURL, let file = activeFile else { return }
        // Placeholder header; replaced with real lengths on preserve.
        let header = Self.wavHeader(dataLength: 0)
        file.truncateFile(atOffset: 0)
        file.seek(toFileOffset: 0)
        file.write(header)
    }

    private func finalizeHeader() {
        guard let url = activeURL, let file = activeFile else { return }
        let dataLength = writtenFrames * 2
        let header = Self.wavHeader(dataLength: dataLength)
        file.truncateFile(atOffset: 0)
        file.seek(toFileOffset: 0)
        file.write(header)
        try? file.synchronize()
        // Rename to a stable, sortable name.
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let target = directory.appendingPathComponent("recovery-\(timestamp).wav")
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.moveItem(at: url, to: target)
        activeURL = target
    }

    static func wavHeader(dataLength: Int) -> Data {
        let sampleRate = UInt32(Self.sampleRate)
        let byteRate = sampleRate * 2
        var header = Data()
        header.append("RIFF".data(using: .ascii)!)
        header.append(contentsOf: UInt32(36 + dataLength).littleEndianBytes)
        header.append("WAVE".data(using: .ascii)!)
        header.append("fmt ".data(using: .ascii)!)
        header.append(contentsOf: UInt32(16).littleEndianBytes)
        header.append(contentsOf: UInt16(1).littleEndianBytes) // PCM
        header.append(contentsOf: UInt16(1).littleEndianBytes) // mono
        header.append(contentsOf: sampleRate.littleEndianBytes)
        header.append(contentsOf: byteRate.littleEndianBytes)
        header.append(contentsOf: UInt16(2).littleEndianBytes) // block align
        header.append(contentsOf: UInt16(16).littleEndianBytes) // bits
        header.append("data".data(using: .ascii)!)
        header.append(contentsOf: UInt32(dataLength).littleEndianBytes)
        return header
    }
}

private extension UInt32 {
    var littleEndianBytes: [UInt8] {
        [UInt8(self & 0xFF), UInt8((self >> 8) & 0xFF), UInt8((self >> 16) & 0xFF), UInt8((self >> 24) & 0xFF)]
    }
}

private extension UInt16 {
    var littleEndianBytes: [UInt8] {
        [UInt8(self & 0xFF), UInt8((self >> 8) & 0xFF)]
    }
}
