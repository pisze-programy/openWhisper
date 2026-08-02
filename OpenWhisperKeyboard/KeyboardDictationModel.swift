import Foundation
import Combine
import UIKit
import OpenWhisperShared

@MainActor
final class KeyboardDictationModel: ObservableObject {
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var error: String?
    @Published var errorTitle: String?
    @Published var fullAccessNeeded = false
    @Published var elapsed: TimeInterval = 0

    @Published var needsAppOpen = false

    @Published private(set) var currentLanguageName: String = "Auto"

    @Published private(set) var hasAPIKey: Bool

    var onInsertText: ((String) -> Void)?

    var onOpenApp: (() -> Void)?

    var isFullAccessGranted = true

    private var resultPollTimer: Timer?
    private var levelTimer: Timer?
    private var lastSeenStamp: TimeInterval = 0
    private var lastInsertedStamp: TimeInterval = 0
    private var recordingStartedAt: Date?
    private var wired = false

    private var pendingCommand: AppGroup.Command.Action?

    init() {
        let key = UserDefaults(suiteName: AppGroup.identifier)?.string(forKey: AppGroup.cloudApiKeyKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        hasAPIKey = !key.isEmpty
        lastInsertedStamp = AppGroup.lastInsertedStamp
        lastSeenStamp = lastInsertedStamp
        wireBridge()
        refreshConfiguration()
    }

    private var controllerAPIKey: String {
        UserDefaults(suiteName: AppGroup.identifier)?.string(forKey: AppGroup.cloudApiKeyKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var liveSamples: [Float] {
        let bucketCount = 28
        let repeatCount = 65
        let level = max(0, min(1, AppGroup.currentLevel()))
        var out = [Float]()
        out.reserveCapacity(bucketCount * repeatCount)

        for i in 0..<bucketCount {
            let fill = i >= bucketCount - 6 ? level : level * 0.35
            out.append(contentsOf: repeatElement(fill, count: repeatCount))
        }
        return out
    }

    func refreshConfiguration() {
        let code = UserDefaults(suiteName: AppGroup.identifier)?.string(forKey: AppGroup.languageCodeKey)
        currentLanguageName = code.flatMap { Language.language(for: $0)?.name } ?? "Auto"
        hasAPIKey = !controllerAPIKey.isEmpty
        if !isFullAccessGranted {
            error = "The keyboard needs Full Access to talk to the OpenWhisper app."
            errorTitle = "Full access needed:"
            fullAccessNeeded = true
        } else {
            fullAccessNeeded = false
            if errorTitle == "Full access needed:" {
                error = nil
                errorTitle = nil
            }
        }
    }

    func start() {
        guard isFullAccessGranted else {
            isRecording = false
            isTranscribing = false
            error = "The keyboard needs Full Access to talk to the OpenWhisper app."
            errorTitle = "Full access needed:"
            fullAccessNeeded = true
            return
        }

        guard AppGroup.isHostAlive() else {
            needsAppOpen = true
            error = "The OpenWhisper app isn't running in the background. Open it once, then come back here."
            errorTitle = "Open OpenWhisper first:"
            fullAccessNeeded = false
            return
        }

        isRecording = true
        isTranscribing = false
        error = nil
        errorTitle = nil
        fullAccessNeeded = false
        needsAppOpen = false
        recordingStartedAt = Date()

        AppGroup.clearDictation()
        lastInsertedStamp = AppGroup.lastInsertedStamp
        lastSeenStamp = lastInsertedStamp

        AppGroup.writeCommand(.start)
        DarwinBridge.post(.startRecording)
        startLevelTimer()
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false

        if let started = recordingStartedAt, Date().timeIntervalSince(started) < 0.35 {
            recordingStartedAt = nil
            resetForIdle()
            return
        }
        recordingStartedAt = nil

        isTranscribing = true
        AppGroup.writeCommand(.stop)
        DarwinBridge.post(.stopRecording)
        startResultPolling()
        stopLevelTimer()
    }

    func cancel() {
        recordingStartedAt = nil
        isRecording = false
        isTranscribing = false
        AppGroup.writeCommand(.cancel)
        DarwinBridge.post(.cancelRecording)
        stopLevelTimer()
        stopResultPolling()
        resetForIdle()
    }

    func retry() {
        error = nil
        errorTitle = nil
        fullAccessNeeded = false
        needsAppOpen = false
        isRecording = false
        isTranscribing = false
    }

    private func resetForIdle() {
        isRecording = false
        isTranscribing = false
        elapsed = 0
    }

    private func wireBridge() {
        guard !wired else { return }
        wired = true

        DarwinBridge.observe(.resultReady) { [weak self] in
            self?.tryInsertNewDictation()
        }
        DarwinBridge.observe(.stateChanged) { [weak self] in
            self?.refreshStateFromApp()
        }
        DarwinBridge.observe(.pong) { [weak self] in
            self?.needsAppOpen = false
        }
    }

    private func refreshStateFromApp() {
        switch AppGroup.currentEngineState() {
        case .recording:
            isRecording = true
        case .transcribing:
            isRecording = false
            isTranscribing = true
        case .ready, .unknown:
            if isTranscribing { tryInsertNewDictation() }
            if !AppGroup.isHostAlive() {
                needsAppOpen = true
            }
        case .error, .loading:
            break
        }
    }

    private func startResultPolling() {
        stopResultPolling()
        resultPollTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.tryInsertNewDictation()
        }
        resultPollTimer?.tolerance = 0.05
    }

    private func stopResultPolling() {
        resultPollTimer?.invalidate()
        resultPollTimer = nil
    }

    private func tryInsertNewDictation() {
        let stamp = AppGroup.lastDictationStamp
        guard stamp > 0, stamp > lastInsertedStamp, stamp != lastSeenStamp else {

            return
        }
        lastSeenStamp = stamp

        guard let payload = AppGroup.readDictation() else {
            return
        }
        lastInsertedStamp = stamp
        AppGroup.setLastInsertedStamp(stamp)

        AppGroup.clearDictation()
        stopResultPolling()
        stopLevelTimer()

        if payload.text.isEmpty {
            isTranscribing = false
            resetForIdle()
            error = payload.note ?? "No speech detected"
            errorTitle = nil
            fullAccessNeeded = false
            return
        }

        isTranscribing = false
        resetForIdle()
        onInsertText?(payload.text)
    }

    private func startLevelTimer() {
        stopLevelTimer()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.elapsed = Date().timeIntervalSince(self?.recordingStartedAt ?? Date())
            let level = AppGroup.currentLevel()
            _ = level
        }
        levelTimer?.tolerance = 0.05
    }

    private func stopLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = nil
    }
}
