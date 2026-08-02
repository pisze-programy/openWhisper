import SwiftUI
import OpenWhisperShared

struct OnboardingIntroView: View {
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(AppTheme.surface)
                    .frame(width: 96, height: 96)
                Image(systemName: "waveform")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
            }
            .padding(.top, 24)

            Text("OpenWhisper")
                .font(.largeTitle.bold())

            Text("Turn your speech into text on your device.")
                .font(.body)
                .foregroundStyle(AppTheme.secondaryLabel)
                .multilineTextAlignment(.center)

            GlassCard {
                Text("“Speak three times faster than you type.”")
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }

            VideoPlaceholder(caption: "Demo video coming soon")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
}
