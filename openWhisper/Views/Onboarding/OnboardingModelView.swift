import SwiftUI
import OpenWhisperShared

struct OnboardingModelView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.largeSpacing) {
            Text("Download the speech model")
                .font(.title2.bold())

            Text("OpenWhisper runs entirely on your device. The speech model is downloaded once (~480 MB, needs ~1.3 GB of free space) — your audio never leaves your phone.")
                .font(AppTheme.hintFont)
                .foregroundStyle(AppTheme.secondaryLabel)

            ModelCardView()

            VideoPlaceholder(caption: "How it works — live transcription (video coming soon)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }
}
