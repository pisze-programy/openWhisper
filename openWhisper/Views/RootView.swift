import SwiftUI
import OpenWhisperShared

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SettingsStore.self) private var settings
    @Environment(ModelDownloadManager.self) private var modelDownload
    @Environment(TranscriptionService.self) private var transcription

    var body: some View {
        ZStack {
            Group {
                if settings.onboardingCompleted {
                    HistoryView()
                        .onAppear { modelDownload.refreshStatus() }
                } else {
                    OnboardingView(onFinish: { settings.onboardingCompleted = true })
                        .onAppear { modelDownload.refreshStatus() }
                }
            }
            .task { await transcription.warmUp() }
            .onChange(of: modelDownload.status) { _, newStatus in
                if newStatus == .ready {
                    Task { await transcription.warmUp() }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    Task { await transcription.warmUp() }
                case .background:
                    transcription.enterBackground()
                default:
                    break
                }
            }

            ToastOverlay()
        }
    }
}
