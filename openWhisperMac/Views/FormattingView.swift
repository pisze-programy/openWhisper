import SwiftUI
import OpenWhisperShared

struct FormattingView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SettingsSection("Formatting") {
                    ToggleRow(
                        "Rewrite with AI",
                        description: "Removes filler words, fixes grammar, and applies your chosen writing style via OpenRouter.",
                        isOn: $settings.formattingEnabled
                    )
                    .padding(.bottom, 6)

                    VStack(spacing: 8) {
                        ForEach(TranscriptionStyle.allCases) { style in
                            StyleCard(
                                style: style,
                                isSelected: settings.formattingStyle == style,
                                isEnabled: settings.formattingEnabled
                            ) {
                                settings.formattingStyle = style
                            }
                        }
                    }
                    .opacity(settings.formattingEnabled ? 1 : 0.4)
                    .disabled(!settings.formattingEnabled)
                }
            }
            .padding(.top, 8)
        }
        .background(.regularMaterial)
        .navigationTitle("Formatting")
    }
}
