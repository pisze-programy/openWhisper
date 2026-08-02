import AVFoundation
import Foundation

final class KeyboardRecorder {

    var silenceAutoStopSeconds: TimeInterval?

    var onSilenceThresholdExceeded: (() -> Void)?

    var silenceRMSThreshold: Float = 0.02

    private var recorder: AVAudioRecorder?
    private var meteringTimer: Timer?

    private var levelHistory: [Float] = []
    private var silenceElapsed: TimeInterval = 0
    private var silenceTriggered = false

    private var lastPollDate: Date?

    var isRecording: Bool { recorder?.isRecording ?? false }

    func start(outputURL: URL) throws {
        meteringTimer?.invalidate()
        meteringTimer = nil
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let recorder = try AVAudioRecorder(url: outputURL, settings: settings)
        recorder.isMeteringEnabled = true

        let maxStartAttempts = 3
        let attemptGap: TimeInterval = 0.2
        var started = false
        for attempt in 1...maxStartAttempts {
            let prepared = recorder.prepareToRecord()
            if prepared {
                started = recorder.record()
            }
            if started { break }
            if attempt < maxStartAttempts {
                Thread.sleep(forTimeInterval: attemptGap)
            }
        }

        guard started else {
            throw KeyboardRecorderError.recordFailed
        }
        self.recorder = recorder
        silenceElapsed = 0
        silenceTriggered = false
        lastPollDate = Date()
        levelHistory = []
        startMeteringTimer()
    }

    func stop() {
        meteringTimer?.invalidate()
        meteringTimer = nil
        recorder?.stop()
        recorder = nil
        lastPollDate = nil
    }

    var liveSamples: [Float] {
        let bucketCount = 28
        let repeatCount = 65
        let levels = levelHistory.suffix(bucketCount)
        var out = [Float]()
        out.reserveCapacity(bucketCount * repeatCount)
        let leadingZeros = bucketCount - levels.count
        out.append(contentsOf: repeatElement(0, count: leadingZeros * repeatCount))
        for level in levels {
            out.append(contentsOf: repeatElement(level, count: repeatCount))
        }
        return out
    }

    private func startMeteringTimer() {
        meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.pollMeters()
        }
    }

    private func pollMeters() {
        guard let recorder else { return }
        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0)
        let amplitude = pow(10.0, Double(db) / 20.0)
        let level = Float(min(1, max(0, amplitude)))
        levelHistory.append(level)
        if levelHistory.count > 28 {
            levelHistory.removeFirst(levelHistory.count - 28)
        }
        guard let silenceAutoStopSeconds, !silenceTriggered else { return }

        let now = Date()
        let delta = lastPollDate.map { now.timeIntervalSince($0) } ?? 0
        lastPollDate = now
        if Float(amplitude) < silenceRMSThreshold {
            silenceElapsed += delta
            if silenceElapsed >= silenceAutoStopSeconds {
                silenceTriggered = true
                onSilenceThresholdExceeded?()
            }
        } else {
            silenceElapsed = 0
        }
    }
}

enum KeyboardRecorderError: LocalizedError {
    case recordFailed

    var errorDescription: String? {
        switch self {
        case .recordFailed:
            return "Couldn't start recording."
        }
    }
}
