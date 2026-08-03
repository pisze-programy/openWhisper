import AVFoundation
import AppKit
import Foundation

/// Plays feedback sounds for dictation events: recording start, transcription
/// success, and errors. Supports bundled, system, and user-installed sounds.
@MainActor
final class FeedbackSoundService {
    enum Event {
        case recordingStarted
        case transcriptionSuccess
        case styleChanged
        case error
    }

    static let shared = FeedbackSoundService()

    var enabled = true

    private var players: [AVAudioPlayer] = []

    private init() {}

    func play(_ event: Event) {
        guard enabled else { return }
        let name: String?
        switch event {
        case .recordingStarted: name = "recording_start"
        case .transcriptionSuccess: name = "transcription_success"
        case .styleChanged: name = nil
        case .error: name = "error"
        }

        if let url = bundledSound(named: name ?? "") {
            playFile(at: url)
        } else if let systemName = systemSoundName(for: event) {
            let sound = NSSound(named: systemName)
            sound?.play()
        }
    }

    func playbackDuration(of event: Event) -> TimeInterval {
        let name: String
        switch event {
        case .recordingStarted: name = "recording_start"
        case .transcriptionSuccess: name = "transcription_success"
        case .styleChanged: return 0
        case .error: name = "error"
        }
        guard let url = bundledSound(named: name),
              let player = try? AVAudioPlayer(contentsOf: url) else { return 0 }
        return player.duration
    }

    private func playFile(at url: URL) {
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        players.append(player)
        player.delegate = nil
        player.play()
        // Drop reference shortly after playback ends.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((player.duration + 0.5) * 1_000_000_000))
            self?.players.removeAll { $0 === player }
        }
    }

    private func bundledSound(named name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "wav") ?? Bundle.main.url(forResource: name, withExtension: "aiff")
    }

    private func systemSoundName(for event: Event) -> String? {
        switch event {
        case .recordingStarted: return "Bottle"
        case .transcriptionSuccess: return "Glass"
        case .styleChanged: return "Glass"
        case .error: return "Funk"
        }
    }
}
