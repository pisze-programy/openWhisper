import SwiftUI
import OpenWhisperShared

struct DictationView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SettingsSection("Speech Model") {
                    ModelCardView()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }

                SettingsSection("Dictation") {
                    ToggleRow(
                        "Auto-copy to clipboard",
                        description: "Copies the transcribed text automatically when dictation finishes.",
                        isOn: $settings.autoCopy
                    )
                    ToggleRow(
                        "Auto-paste into active app",
                        description: "Pastes the text directly into the frontmost app. Requires Accessibility permission.",
                        isOn: $settings.autoPaste
                    )
                    ToggleRow(
                        "Preserve clipboard after paste",
                        description: "Restores the previous clipboard content after pasting.",
                        isOn: $settings.preserveClipboard
                    )
                }

                SettingsSection("OpenRouter API") {
                    ApiKeyRow(keyName: AppGroup.cloudApiKeyKey, placeholder: "sk-or-...")
                }
            }
            .padding(.top, 8)
        }
        .background(.regularMaterial)
        .navigationTitle("Dictation")
    }
}
