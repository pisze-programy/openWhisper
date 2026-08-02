import SwiftUI
import SwiftData
import OpenWhisperShared

extension Notification.Name {
    /// Posted when the app is opened via `openwhisper://settings` (from the
    /// keyboard extension) so the user can reach the full-access guidance.
    static let openWhisperOpenSettings = Notification.Name("openWhisperOpenSettings")
}

@main
struct openWhisperApp: App {
    @State private var settings: SettingsStore
    @State private var modelDownload: ModelDownloadManager
    @State private var transcription: TranscriptionService
    @State private var recorder: AudioRecorder
    @State private var toast = ToastCenter()
    @State private var corrections = CorrectionsStore()
    private let container: ModelContainer

    init() {
        let settings = SettingsStore()
        _settings = State(initialValue: settings)
        _modelDownload = State(initialValue: .shared)
        _transcription = State(initialValue: TranscriptionService(settings: settings, modelDownload: .shared))
        _recorder = State(initialValue: AudioRecorder())
        let config = ModelConfiguration(url: ModelLocations.historyStoreURL)
        container = try! ModelContainer(for: TranscriptionItem.self, configurations: config)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .onOpenURL { url in
                    if url.host == "settings" {
                        NotificationCenter.default.post(name: .openWhisperOpenSettings, object: nil)
                    }
                }
        }
        .environment(settings)
        .environment(modelDownload)
        .environment(transcription)
        .environment(recorder)
        .environment(toast)
        .environment(corrections)
        .modelContainer(container)
    }
}
