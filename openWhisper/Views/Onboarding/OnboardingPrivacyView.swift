import SwiftUI
import OpenWhisperShared

struct OnboardingPrivacyView: View {
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(AppTheme.surface)
                    .frame(width: 96, height: 96)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
            }
            .padding(.top, 24)

            Text("Your privacy")
                .font(.largeTitle.bold())

            Text("We never use your transcriptions to train models — everything stays on your device.")
                .font(.body)
                .foregroundStyle(AppTheme.secondaryLabel)
                .multilineTextAlignment(.center)

            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    PrivacyRow(icon: "internaldrive", text: "Your audio is processed on your device and never leaves it")
                    PrivacyRow(icon: "person.crop.circle.badge.questionmark", text: "No account, no sign-up")
                    PrivacyRow(icon: "hand.raised.fill", text: "Your words are never used for training")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
}

private struct PrivacyRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 28)
            Text(text)
                .font(.subheadline)
        }
    }
}
