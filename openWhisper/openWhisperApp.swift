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
    @State private var corrections = CorrectionsStore()
    @State private var settingsRouter = SettingsRouter()
    @State private var formatting = TextFormattingService()
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
                        let section = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                            .queryItems?.first(where: { $0.name == "section" })?.value
                        settingsRouter.pendingSection = section
                    }
                }
        }
        .environment(settings)
        .environment(modelDownload)
        .environment(transcription)
        .environment(recorder)
        .environment(toast)
        .environment(corrections)
        .environment(settingsRouter)
        .environment(formatting)
        .modelContainer(container)
    }
}
