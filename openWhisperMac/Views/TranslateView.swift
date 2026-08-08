import SwiftUI
import OpenWhisperShared

/// Dedicated Translate tab: manages the target languages the right ⌘+⇧ hotkey
/// cycles through, styled like the Formatting cards. NONE is always part of the
/// cycle and cannot be removed. The source is always the Speech-to-Text
/// language — there is no FROM picker.
struct TranslateView: View {
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

                let keyAvailable = TextFormattingService.hasApiKey
                SettingsSection("Translation targets") {
                    NoneTargetCard(isSelected: settings.translationTargetCode == nil) {
                        settings.translationTargetCode = nil
                    }

                    ForEach(settings.translationTargets, id: \.self) { code in
                        TargetLanguageCard(
                            language: Language.language(for: code) ?? Language(code: code, name: code),
                            isSelected: settings.translationTargetCode == code,
                            onSelect: { settings.translationTargetCode = code },
                            onRemove: { settings.translationTargets.removeAll { $0 == code } }
                        )
                        .disabled(!keyAvailable)
                    }

                    Divider()

                    AddLanguageRow(
                        available: Language.all.filter { language in
                            !settings.translationTargets.contains(language.code)
                        }
                    ) { language in
                        settings.translationTargets.append(language.code)
                        settings.translationTargetCode = language.code
                    }
                    .disabled(!keyAvailable)
                }

                SettingsSection("How it works") {
                    ShortcutHintRow(
                        icon: "keyboard",
                        tint: .secondary,
                        text: "Switch the translation target from anywhere: hold right ⌘ and tap right ⇧."
                    )
                    ShortcutHintRow(
                        icon: "translate",
                        tint: .secondary,
                        text: "You speak in the Speech-to-Text language. The transcript is translated into the selected target; None keeps it as spoken."
                    )
                    ShortcutHintRow(
                        icon: "checkmark.circle",
                        tint: .secondary,
                        text: "Tap a card to select the target; a filled circle marks the selection."
                    )
                }
            }
            .padding(.top, 8)
        }
        .background(.regularMaterial)
        .navigationTitle("Translate")
    }
}

/// NONE — always part of the cycle, cannot be removed.
private struct NoneTargetCard: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("None")
                        .font(.callout.weight(.medium))
                    Text("No translation — output stays in the Speech-to-Text language.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .blue : .secondary.opacity(0.4))
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(12)
    }
}

/// An enabled target language: tap to select, minus to remove from the cycle.
private struct TargetLanguageCard: View {
    let language: Language
    let isSelected: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onSelect) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(language.name)
                            .font(.callout.weight(.medium))
                        Text("Target language — cycled with right ⌘ + ⇧.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: isSelected ? "circle.fill" : "circle")
                        .font(.system(size: 12))
                        .foregroundStyle(isSelected ? .blue : .secondary.opacity(0.4))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Remove from the cycle")
        }
        .padding(12)
    }
}

/// Picker that appends a new language to the cycle list.
private struct AddLanguageRow: View {
    let available: [Language]
    let onAdd: (Language) -> Void

    @State private var pending: Language?

    var body: some View {
        HStack {
            Text("Add language")
                .font(.callout)
            Spacer()
            Picker("", selection: $pending) {
                Text("Choose…").tag(Language?.none)
                ForEach(available) { language in
                    Text(language.name).tag(language as Language?)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .onChange(of: pending) { _, newValue in
                if let newValue {
                    onAdd(newValue)
                    pending = nil
                }
            }
            .disabled(available.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
