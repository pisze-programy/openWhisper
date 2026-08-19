import SwiftUI
import OpenWhisperShared

struct OnboardingStylesView: View {
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(AppTheme.surface)
                    .frame(width: 96, height: 96)
                Image(systemName: "textformat")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
            }
            .padding(.top, 24)

            Text("Pick a style")
                .font(.largeTitle.bold())

            Text("Every recording can be rewritten in the style you choose before you speak.")
                .font(.body)
                .foregroundStyle(AppTheme.secondaryLabel)
                .multilineTextAlignment(.center)

            VideoPlaceholder(caption: "Demo: watch your words get rewritten")

            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    StyleInfoRow(style: .formal)
                    StyleInfoRow(style: .casual)
                    StyleInfoRow(style: .veryCasual)
                    StyleInfoRow(style: .brief)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
}

private struct StyleInfoRow: View {
    let style: TranscriptionStyle

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: style.systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(style.title)
                    .font(.subheadline.weight(.medium))
                Text(style.shortDescription)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
        }
    }
}
