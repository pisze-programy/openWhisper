import SwiftUI

struct RootView: View {
    @Environment(ModelDownloadManager.self) private var modelDownload

    @State private var showOnboarding = true

    var body: some View {
        Group {
            if showOnboarding {
                OnboardingView(onFinish: { showOnboarding = false })
                    .onAppear { modelDownload.refreshStatus() }
            } else {
                HistoryView()
                    .onAppear { modelDownload.refreshStatus() }
            }
        }
    }
}
