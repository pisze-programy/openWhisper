import SwiftUI

/// Top-level view: shows onboarding first (testing mode), then the main history screen.
struct RootView: View {
    @Environment(ModelDownloadManager.self) private var modelDownload

    /// TODO: onboarding shows on EVERY launch during testing — switch to show-once later (plan D11).
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
