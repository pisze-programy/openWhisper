import SwiftUI
import SwiftData
import OpenWhisperShared

@main
struct openWhisperApp: App {
    @State private var settings: SettingsStore
    @State private var modelDownload: ModelDownloadManager
    @State private var transcription: TranscriptionService
    @State private var recorder: AudioRecorder
    @State private var resident: ResidentDictation
    @State private var toast = ToastCenter()
    @State private var corrections = CorrectionsStore()
    @State private var settingsRouter = SettingsRouter()
    private let container: ModelContainer

    init() {
        let settings = SettingsStore()
        _settings = State(initialValue: settings)
        _modelDownload = State(initialValue: .shared)
        _transcription = State(initialValue: TranscriptionService(settings: settings, modelDownload: .shared))
        _recorder = State(initialValue: AudioRecorder())
        let resident = ResidentDictation(
            transcription: .init(settings: settings, modelDownload: .shared),
            modelDownload: .shared
        )
        _resident = State(initialValue: resident)
        ResidentDictation.shared = resident
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
                    } else if url.host == "dictate" {

                        resident.start()
                    }
                }
        }
        .environment(settings)
        .environment(modelDownload)
        .environment(transcription)
        .environment(recorder)
        .environment(resident)
        .environment(toast)
        .environment(corrections)
        .environment(settingsRouter)
        .modelContainer(container)
    }
}
