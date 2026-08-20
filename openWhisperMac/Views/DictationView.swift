import SwiftUI
import OpenWhisperShared

struct DictationView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SettingsSection("Speech Model") {
                    MacModelCardView()
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

                    Divider()

#if APP_STORE
                    ToggleRow(
                        "Mute media while dictating",
                        description: "Mutes the system output while recording so music or video doesn't interfere with the microphone.",
                        isOn: $settings.mediaHandlingEnabled
                    )
#else
                    ToggleRow(
                        "Mute or pause media while dictating",
                        description: "Pauses music/video (e.g. YouTube) while recording and resumes where it stopped; Mute lowers the output to zero instead.",
                        isOn: $settings.mediaHandlingEnabled
                    )
                    if settings.mediaHandlingEnabled {
                        MediaModeRow(mode: $settings.mediaHandlingMode)
                    }
#endif
                }
            }
            .padding(.top, 8)
        }
        .background(.regularMaterial)
        .navigationTitle("Dictation")
    }
}

/// Mute vs Pause selector shown when media handling is enabled (public build —
/// the App Store build only ever offers mute).
private struct MediaModeRow: View {
    @Binding var mode: MediaHandlingMode

    var body: some View {
        HStack {
            Text("During dictation")
                .font(.callout)
            Spacer()
            Picker("", selection: $mode) {
                ForEach(MediaHandlingMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
