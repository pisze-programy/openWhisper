import SwiftUI

struct OnboardingIntroView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.tint)
                .padding(.top, 24)

            Text("OpenWhisper")
                .font(.largeTitle.bold())

            Text("Turn your speech into text on your device.")
                .font(.body)
                .foregroundStyle(.secondary)
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
