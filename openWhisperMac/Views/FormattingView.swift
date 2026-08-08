import SwiftUI
import OpenWhisperShared

struct FormattingView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !TextFormattingService.hasApiKey {
                    ApiKeyRequiredBanner()
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }

                SettingsSection("Formatting") {
                    VStack(spacing: 8) {
                        ForEach(TranscriptionStyle.allCases) { style in
                            StyleCard(
                                style: style,
                                isSelected: settings.formattingStyle == style
                            ) {
                                settings.formattingStyle = style
                            }
                            .disabled(style != .none && !TextFormattingService.hasApiKey)
                        }
                    }
                    .padding(.vertical, 8)

                    Divider()

                    ShortcutHintRow(
                        icon: "keyboard",
                        tint: .secondary,
                        text: "Switch styles from anywhere: hold right ⌥ and tap right ⇧."
                    )

                    ShortcutHintRow(
                        icon: "translate",
                        tint: .secondary,
                        text: "Translation target (None/Polish/English…) is set in the Translate tab and switched with hold right ⌘ and tap right ⇧."
                    )
                }
            }
            .padding(.top, 8)
        }
        .background(.regularMaterial)
        .navigationTitle("Formatting")
    }
}

struct ShortcutHintRow: View {
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
