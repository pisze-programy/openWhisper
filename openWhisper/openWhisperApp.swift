import SwiftUI
import SwiftData
import OpenWhisperShared

@main
struct openWhisperApp: App {
    @State private var settings: SettingsStore
    @State private var modelDownload: ModelDownloadManager
    @State private var transcription: TranscriptionService
    @State private var recorder: AudioRecorder
    @State private var toast = ToastCenter()
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
        }
        .environment(settings)
        .environment(modelDownload)
        .environment(transcription)
        .environment(recorder)
        .environment(toast)
        .modelContainer(container)
    }
}
