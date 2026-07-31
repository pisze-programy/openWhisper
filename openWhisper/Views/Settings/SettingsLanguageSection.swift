import SwiftUI
import OpenWhisperShared

struct SettingsLanguageSection: View {
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        @Bindable var settings = settingsStore

        Section {
            Picker(
                "Language",
                selection: Binding(
                    get: { settings.languageCode ?? "auto" },
                    set: { settings.languageCode = $0 == "auto" ? nil : $0 }
                )
            ) {
                Text("Auto (Recommended)").tag("auto")
                ForEach(Language.all) { language in
                    Text(language.name).tag(language.code)
                }
            }
            .pickerStyle(.navigationLink)
        } header: {
            SectionHeader(title: "Language")
        } footer: {
            Text("By default, OpenWhisper auto-detects the language of each recording. You can pin one to always transcribe in it.")
        }
    }
}
