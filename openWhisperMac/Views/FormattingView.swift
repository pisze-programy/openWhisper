import SwiftUI
import OpenWhisperShared

struct FormattingView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SettingsSection("Formatting") {
                    VStack(spacing: 8) {
                        ForEach(TranscriptionStyle.allCases) { style in
                            StyleCard(
                                style: style,
                                isSelected: settings.formattingStyle == style
                            ) {
                                settings.formattingStyle = style
                            }
                        }
                    }
                    .padding(.vertical, 8)

                    if settings.formattingStyle != .none && !TextFormattingService.hasApiKey {
                        ShortcutHintRow(
                            icon: "exclamationmark.triangle.fill",
                            tint: .orange,
                            text: "This style uses the OpenRouter API. Add your key in Dictation → OpenRouter API, or pick None for a fast, local transcript."
                        )
                    }

                    Divider()

                    ShortcutHintRow(
                        icon: "keyboard",
                        tint: .secondary,
                        text: "Switch styles from anywhere: hold right ⌥ and tap right ⇧."
                    )
                }
            }
            .padding(.top, 8)
        }
        .background(.regularMaterial)
        .navigationTitle("Formatting")
    }
}

private struct ShortcutHintRow: View {
    let icon: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(tint)
                .padding(.top, 1)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
