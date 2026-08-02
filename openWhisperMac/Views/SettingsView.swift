import SwiftUI
import OpenWhisperShared

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(PermissionManager.self) private var permissionManager

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
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

                SettingsSection("Audio") {
                    ToggleRow(
                        "Whisper Mode (auto gain)",
                        description: "Boosts quiet speech and smooths volume before transcription.",
                        isOn: $settings.microphoneBoostEnabled
                    )
                    ToggleRow(
                        "Keep short or quiet clips",
                        description: "Transcribes even brief recordings that would otherwise be discarded as noise.",
                        isOn: $settings.transcribeShortQuietClipsAggressively
                    )
                    ToggleRow(
                        "Require second Esc to cancel",
                        description: "Press Escape twice within 1.5 seconds to cancel an active recording.",
                        isOn: $settings.requireSecondEscapeToCancel
                    )
                }

                SettingsSection("History") {
                    ToggleRow(
                        "Save transcriptions to history",
                        description: "Keeps a timeline of your past dictation sessions in the History tab.",
                        isOn: $settings.saveToHistory
                    )
                }

                SettingsSection("Permissions") {
                    PermissionStatusRow(
                        title: "Microphone",
                        granted: permissionManager.microphoneStatus.isGranted,
                        actionTitle: "Open System Settings",
                        action: { permissionManager.openMicrophoneSettings() }
                    )
                    PermissionStatusRow(
                        title: "Accessibility",
                        granted: permissionManager.accessibilityStatus.isGranted,
                        actionTitle: "Open System Settings",
                        action: { permissionManager.openAccessibilitySettings() }
                    )
                }

                SettingsSection("OpenRouter API") {
                    ApiKeyRow(keyName: AppGroup.cloudApiKeyKey, placeholder: "sk-or-...")
                }

                HStack {
                    Spacer()
                    Button("Show onboarding again") {
                        settings.onboardingCompleted = false
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                    Spacer()
                }
                .padding(.vertical, 20)
            }
            .padding(.top, 8)
        }
        .background(.regularMaterial)
        .navigationTitle("Settings")
    }
}

private struct StyleCard: View {
    let style: TranscriptionStyle
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(style.title)
                        .font(.callout.weight(.medium))
                    Text(style.shortDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(style.afterExample)
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.6))
                        .lineLimit(1)
                        .italic()
                    Text(style.whenToUse)
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.6))
                }
                Spacer()
                Image(systemName: isSelected ? "circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .blue : .secondary.opacity(0.4))
                    .padding(.top, 4)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? .blue.opacity(0.06) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? .blue.opacity(0.2) : .clear, lineWidth: 1)
        )
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 6)

            VStack(spacing: 0) {
                content
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
        }
    }
}

private struct ToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    init(_ title: String, description: String, isOn: Binding<Bool>) {
        self.title = title
        self.description = description
        self._isOn = isOn
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct PermissionStatusRow: View {
    let title: String
    let granted: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.callout)
            Spacer()
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct ApiKeyRow: View {
    let keyName: String
    let placeholder: String
    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your API key stays on this device.")
                .font(.caption)
                .foregroundStyle(.secondary)

            SecureField(placeholder, text: $text, prompt: Text("sk-or-..."))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onChange(of: text) { _, newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    UserDefaults.standard.set(trimmed, forKey: keyName)
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onAppear {
            text = UserDefaults.standard.string(forKey: keyName) ?? ""
        }
    }
}
