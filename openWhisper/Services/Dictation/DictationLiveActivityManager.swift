import Foundation
import ActivityKit
import OpenWhisperShared

@MainActor
final class DictationLiveActivityManager {

    private let isEnabled = false

    private var activity: Activity<DictationActivityAttributes>?
    private var timer: Timer?

    func startRecording(at date: Date) {
        guard isEnabled else { return }
        end()

        let attributes = DictationActivityAttributes()
        let state = DictationActivityAttributes.ContentState(
            phase: .recording,
            elapsed: 0
        )
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil)
            )
            startTicker(from: date)
        } catch {

            activity = nil
        }
    }

    func showTranscribing() {
        stopTicker()
        update(state: DictationActivityAttributes.ContentState(phase: .transcribing, elapsed: 0))
    }

    func end(note: String? = nil) {
        stopTicker()
        guard let activity else { return }
        let state = DictationActivityAttributes.ContentState(
            phase: .done,
            elapsed: 0,
            note: note
        )
        Task {
            await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .default)
            self.activity = nil
        }
    }

    private func startTicker(from date: Date) {
        stopTicker()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick(from: date)
            }
        }
        timer?.tolerance = 0.2
    }

    private func tick(from date: Date) {
        guard let activity else { return }
        let elapsed = Date().timeIntervalSince(date)
        let state = DictationActivityAttributes.ContentState(phase: .recording, elapsed: elapsed)
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    private func stopTicker() {
        timer?.invalidate()
        timer = nil
    }

    private func update(state: DictationActivityAttributes.ContentState) {
        guard let activity else { return }
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }
}
