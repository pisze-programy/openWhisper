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
        } header: {
            SectionHeader(title: "OpenRouter API")
        } footer: {
            Text("Used to rewrite transcripts with AI. Your API key stays on this device.")
        }
        .onAppear {
            apiKey = OpenRouterApiKeyStore.value
        }
        .onChange(of: apiKey) { _, newValue in
            OpenRouterApiKeyStore.set(newValue)
        }
    }
}
