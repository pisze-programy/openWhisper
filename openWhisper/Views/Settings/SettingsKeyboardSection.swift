import SwiftUI
import OpenWhisperShared

struct SettingsKeyboardSection: View {
    @Environment(SettingsStore.self) private var settingsStore
    @State private var apiKey: String = ""

    var body: some View {
        Section {
            SecureField("OpenRouter API key", text: $apiKey, prompt: Text("sk-or-…"))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
                .privacySensitive()

            Button {
                openKeyboardSettings()
            } label: {
                Label("Enable keyboard access", systemImage: "keyboard")
            }
        } header: {
            SectionHeader(title: "Keyboard & AI dictation")
        } footer: {
            Text("The OpenWhisper app runs 100% on-device and private. The keyboard extension uses a cloud speech model (an on-device model can't run inside a keyboard), so it needs internet access and Full Access: Settings → General → Keyboard → OpenWhisper.")
        }
        .onAppear {
            apiKey = UserDefaults(suiteName: AppGroup.identifier)?.string(forKey: AppGroup.cloudApiKeyKey) ?? ""
        }
        .onChange(of: apiKey) { _, newValue in
            UserDefaults(suiteName: AppGroup.identifier)?.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: AppGroup.cloudApiKeyKey)
        }
    }

    private func openKeyboardSettings() {
        let primary = URL(string: "App-Prefs:root=General&path=Keyboard")
        let fallback = URL(string: UIApplication.openSettingsURLString)
        if let url = primary {
            UIApplication.shared.open(url) { ok in
                if !ok, let fb = fallback {
                    UIApplication.shared.open(fb)
                }
            }
        } else if let fb = fallback {
            UIApplication.shared.open(fb)
        }
    }
}
