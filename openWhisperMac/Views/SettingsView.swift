import SwiftUI
import OpenWhisperShared

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(PermissionManager.self) private var permissionManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SettingsSection("API Key") {
                    ApiKeyRow(placeholder: "sk-or-...") {
                        settings.resetCloudFeaturesIfNoKey()
                    }
                    ShortcutHintRow(
                        icon: "key.fill",
                        tint: .secondary,
                        text: "Used by AI formatting and translations. Stored in your Mac's Keychain."
                    )
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

                SettingsSection("General") {
                    ToggleRow(
                        "Launch at login",
                        description: "Starts OpenWhisper automatically when you log in to your Mac.",
                        isOn: Binding(
                            get: { settings.launchAtLogin },
                            set: { newValue in
                                settings.launchAtLogin = newValue
                                LaunchAtLoginService.apply(newValue)
                            }
                        )
                    )
                    ToggleRow(
                        "Share anonymous usage stats",
                        description: "Reports only usage counters (feature, language, outcome). Never your transcript text.",
                        isOn: $settings.usageAnalyticsEnabled
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
                        action: { permissionManager.openAccessibilitySettings() },
                        showRestartHint: true
                    )
                }

                HStack {
                    Spacer()
                    Button("Show onboarding again") {
                        settings.onboardingCompleted = false
                        openWindow(id: "setup")
                        NSApp.setActivationPolicy(.regular)
                        DispatchQueue.main.async {
                            NSApp.windows.first(where: { $0.title == "OpenWhisper Setup" })?.makeKeyAndOrderFront(nil)
                            NSApp.activate(ignoringOtherApps: true)
                        }
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
        // macOS may take a moment (or an app restart) to reflect an
        // Accessibility grant; poll so the row updates in place.
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            permissionManager.refresh()
        }
    }
}

struct StyleCard: View {
    let style: TranscriptionStyle
    let isSelected: Bool
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

struct SettingsSection<Content: View>: View {
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

struct ToggleRow: View {
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
    /// Shows a hint under the row when the permission is still reported as
    /// not-granted (e.g. Accessibility needs an app restart to be picked up).
    var showRestartHint: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
            if !granted && showRestartHint {
                Text("Granted in System Settings but still grey here? macOS sometimes needs OpenWhisper to be restarted.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct ApiKeyRow: View {
    let placeholder: String
    /// Called after the key changes (added, edited, or cleared) so the store
    /// can reset cloud-dependent state (style/target) when the key is removed.
    var onKeyChange: () -> Void = {}
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
                    OpenRouterApiKeyStore.set(newValue)
                    onKeyChange()
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onAppear {
            text = OpenRouterApiKeyStore.value
        }
    }
}
