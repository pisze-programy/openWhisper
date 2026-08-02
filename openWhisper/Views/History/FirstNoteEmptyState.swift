import SwiftUI
import OpenWhisperShared

/// First-launch empty state for the history screen: explains the value, shows
/// example prompts that start a recording on tap, and reinforces the on-device
/// privacy promise — never a blank wall.
struct FirstNoteEmptyState: View {
    var onStartRecording: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(AppTheme.accent)

            Text("Speak your first note")
                .font(.title3.weight(.semibold))

            Text("Tap the mic and just talk — about your day, an idea, or a message you need to send. Everything stays on your device.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryLabel)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                Text("Try saying:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(Self.examplePrompts, id: \.self) { prompt in
                    Button {
                        onStartRecording()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "quote.opening")
                                .font(.caption)
                                .foregroundStyle(AppTheme.accent)
                            Text(prompt)
                                .font(.subheadline)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "mic.fill")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryLabel)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            AppTheme.surface,
                            in: RoundedRectangle(cornerRadius: AppTheme.buttonCornerRadius, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(
                AppTheme.surface,
                in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
            )

            Text("100% on-device · private by default")
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryLabel)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Things the user can say out loud to get started — first-person openers,
    /// not finished notes. Tapping one starts a recording.
    private static let examplePrompts = [
        "Let me draft a quick email to my client…",
        "Okay, so today's meeting was about…",
        "Random idea — what if we…",
    ]
}
