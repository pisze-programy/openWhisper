import SwiftUI
import OpenWhisperShared

/// First-launch setup: permissions (microphone + accessibility) then model
/// download, then finish.
struct SetupWindow: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ModelDownloadManager.self) private var modelDownload
    @Environment(PermissionManager.self) private var permissionManager

    private enum Step: Int, CaseIterable {
        case permissions
        case model
        case finish
    }

    @State private var step = Step.permissions
    @State private var dictatedText: String = ""
    @FocusState private var isTextAreaFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .permissions: permissionsView
                case .model: modelView
                case .finish: finishView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                Spacer()
                if step != .finish {
                    Button(primaryButtonTitle) {
                        advance()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(.bar)
        }
        .frame(width: 760, height: 540)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionManager.refresh()
        }
        // macOS can take a moment (or an app restart) to reflect an
        // Accessibility grant. Poll so the checkmark appears without the user
        // having to leave and re-enter the window.
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            guard step == .permissions else { return }
            permissionManager.refresh()
        }
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private var permissionsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to OpenWhisper")
                        .font(.title2.bold())
                    Text("Press right ⌘+⌥, speak, release. That's it.")
                        .foregroundStyle(.secondary)
                }
            }

            Divider().padding(.vertical, 20)

            VStack(spacing: 12) {
                PermissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    detail: "OpenWhisper captures your voice through the microphone to transcribe speech into text on your device. Without this, dictation is not possible.",
                    status: permissionManager.microphoneStatus,
                    actionTitle: permissionManager.microphoneStatus == .denied ? "Open System Settings" : "Allow",
                    action: {
                        if permissionManager.microphoneStatus == .denied {
                            permissionManager.openMicrophoneSettings()
                        } else {
                            Task { await permissionManager.requestMicrophone() }
                        }
                    }
                )

                PermissionRow(
                    icon: "hand.raised.fill",
                    title: "Accessibility",
                    detail: "OpenWhisper uses the Accessibility API to paste transcribed text directly into whichever app you're working in. You can skip this and use Copy & Paste instead.",
                    status: permissionManager.accessibilityStatus,
                    actionTitle: "Open System Settings",
                    action: {
                        permissionManager.openAccessibilitySettings()
                    }
                )

                if permissionManager.accessibilityStatus == .denied {
                    Text("Granted in System Settings but still grey here? macOS sometimes needs OpenWhisper to be restarted.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                }
            }

            Spacer()

            Text("You can change these anytime in OpenWhisper → Settings → Permissions.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)
        }
        .padding(28)
    }

    private var modelView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Download the speech model")
                .font(.title2.bold())

            MacModelCardView()

            Text("You can skip this — dictation will show an error until the model is downloaded.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.leading, 4)

            HStack {
                Spacer()
                Button("Skip") {
                    step = .finish
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Text("Your audio stays on your device. Optional AI formatting and translation send the transcript text to the OpenRouter provider.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
        }
        .padding(28)
    }

    private var finishView: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.regularMaterial.opacity(0.5))
                        .frame(width: 120, height: 40)
                        .mask(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 8)
                                .frame(width: 96)
                        }
                        .overlay(alignment: .trailing) {
                            Rectangle()
                                .fill(.quaternary)
                                .frame(width: 0.5)
                                .frame(maxHeight: .infinity)
                                .offset(x: 0)
                        }

                    keyCap("⌘", size: 44)
                    keyCap("⌥", size: 44)
                }

                HStack {
                    Spacer()
                    Text("Use both on the right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Text("Press && hold, speak, release.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    Circle().fill(.red.opacity(0.5)).frame(width: 12, height: 12)
                    Circle().fill(.yellow.opacity(0.5)).frame(width: 12, height: 12)
                    Circle().fill(.green.opacity(0.5)).frame(width: 12, height: 12)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.regularMaterial)

                Divider()

                TextEditor(text: $dictatedText)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .scrollContentBackground(.hidden)
                    .focused($isTextAreaFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .overlay(alignment: .topLeading) {
                        if dictatedText.isEmpty {
                            Text("hey so um i was thinking we should probably meet tomorrow at like ten to discuss the quarter results you know what i mean")
                                .font(.callout.monospaced())
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .allowsHitTesting(false)
                        }
                    }
            }
            .frame(width: 460, height: 140)
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.tertiary.opacity(0.2), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
            .onTapGesture { isTextAreaFocused = true }

            Spacer()

            Button {
                settings.onboardingCompleted = true
                NSApp.setActivationPolicy(.accessory)
                NSApplication.shared.keyWindow?.close()
            } label: {
                Text("Done")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 32)
        .onAppear { isTextAreaFocused = true }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            let last = RecentsStore.shared.lastText
            if !last.isEmpty, dictatedText != last {
                dictatedText = last
            }
        }
    }

    private func keyCap(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(.quaternary, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.12), radius: 3, y: 3)
    }

    private var primaryButtonTitle: String {
        switch step {
        case .permissions:
            return "Continue"
        case .model:
            return "Continue"
        case .finish:
            return ""
        }
    }

    private func advance() {
        let index = step.rawValue
        guard index < Step.allCases.count - 1 else { return }
        step = Step(rawValue: index + 1) ?? .finish
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let detail: String
    let status: PermissionManager.PermissionStatus
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if status.isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            } else {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
        )
    }
}
