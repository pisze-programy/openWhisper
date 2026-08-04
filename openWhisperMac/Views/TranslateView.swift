import SwiftUI
import OpenWhisperShared

/// Dedicated Translate tab: FROM/TO language pickers for the left-⌘+⌥ hotkey and
/// the shortcut reference. Kept separate from Settings because it is a core,
/// frequently-used feature.
struct TranslateView: View {
    @Environment(SettingsStore.self) private var settings

    private static let autoSentinel = "auto"
    private static let offSentinel = "off"

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
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

                    Divider()

                    ShortcutHintRow(
                        icon: "keyboard",
                        tint: .secondary,
                        text: "Translate + format selected text: hold left ⌘ and press left ⌥."
                    )
                    ShortcutHintRow(
                        icon: "arrow.triangle.2.circlepath",
                        tint: .secondary,
                        text: "Swap From/To: hold left ⌘ and tap left ⇧."
                    )
                    if settings.isTranslationActive {
                        ShortcutHintRow(
                            icon: "info.circle",
                            tint: .blue,
                            text: "Translation sends the selected text to OpenRouter. The NONE style translates without formatting."
                        )
                    }
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
