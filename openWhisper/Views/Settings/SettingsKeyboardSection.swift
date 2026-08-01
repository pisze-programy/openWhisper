import SwiftUI
import OpenWhisperShared

/// Cloud dictation / keyboard settings: the OpenRouter API key used by the
/// keyboard extension (stored in the shared App Group suite so the extension
/// can read it).
struct SettingsKeyboardSection: View {
    @Environment(SettingsStore.self) private var settingsStore
    @State private var apiKey: String = ""
    @State private var isSecure = true

    var body: some View {
        Section {
            HStack {
                Group {
                    if isSecure {
                        SecureField("OpenRouter API key", text: $apiKey, prompt: Text("sk-or-…"))
                    } else {
                        TextField("OpenRouter API key", text: $apiKey, prompt: Text("sk-or-…"))
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
                .privacySensitive()
            }
            Toggle("Hide key", isOn: $isSecure)
        } header: {
            SectionHeader(title: "Keyboard & AI dictation")
        } footer: {
            Text("Used by the keyboard extension for cloud speech-to-text. Get a key at openrouter.ai — audio is sent to your chosen provider. The on-device app stays local and free. For the keyboard microphone, also enable Allow Full Access (Settings → General → Keyboard → OpenWhisper).")
        }
        .onAppear {
            apiKey = UserDefaults(suiteName: AppGroup.identifier)?.string(forKey: AppGroup.cloudApiKeyKey) ?? ""
        }
        .onChange(of: apiKey) { _, newValue in
            UserDefaults(suiteName: AppGroup.identifier)?.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: AppGroup.cloudApiKeyKey)
        }
    }
}
