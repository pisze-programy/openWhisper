import SwiftUI
import OpenWhisperShared

/// Dedicated Translate tab: FROM/TO language pickers for the FN+right-⌥ hotkey
/// and the shortcut reference. Kept separate from Settings because it is a
/// core, frequently-used feature.
struct TranslateView: View {
    @Environment(SettingsStore.self) private var settings

    private static let autoSentinel = "auto"
    private static let offSentinel = "off"

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !TextFormattingService.hasApiKey {
                    ApiKeyRequiredBanner()
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }

                let keyAvailable = TextFormattingService.hasApiKey
                SettingsSection("Translate") {
                    LanguagePickerRow(
                        title: "From",
                        selection: Binding(
                            get: {
                                guard let code = settings.translateSourceCode else { return Self.autoSentinel }
                                return code
                            },
                            set: { settings.translateSourceCode = $0 == Self.autoSentinel ? nil : $0 }
                        ),
                        includeAuto: true
                    )
                    .disabled(!keyAvailable)

                    Divider()

                    LanguagePickerRow(
                        title: "To",
                        selection: Binding(
                            get: {
                                guard let code = settings.translateTargetCode else { return Self.offSentinel }
                                return code
                            },
                            set: { settings.translateTargetCode = $0 == Self.offSentinel ? nil : $0 }
                        ),
                        includeOff: true
                    )
                    .disabled(!keyAvailable)

                    Divider()

                    ShortcutHintRow(
                        icon: "keyboard",
                        tint: .secondary,
                        text: "Copy the text, then press FN + right ⌥ to translate + format it (paste replaces the selection)."
                    )
                }
            }
            .padding(.top, 8)
        }
        .background(.regularMaterial)
        .navigationTitle("Translate")
    }
}

private struct LanguagePickerRow: View {
    let title: String
    @Binding var selection: String
    let includeAuto: Bool
    let includeOff: Bool

    init(title: String, selection: Binding<String>, includeAuto: Bool = false, includeOff: Bool = false) {
        self.title = title
        self._selection = selection
        self.includeAuto = includeAuto
        self.includeOff = includeOff
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.callout)
            Spacer()
            Picker("", selection: $selection) {
                if includeAuto {
                    Text("Auto (detect)").tag("auto")
                }
                if includeOff {
                    Text("Off (reformat only)").tag("off")
                }
                ForEach(Language.all) { language in
                    Text(language.name).tag(language.code)
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
