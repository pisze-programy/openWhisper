import SwiftUI
import Foundation

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(ToastCenter.self) private var toast
    @Environment(SettingsRouter.self) private var settingsRouter

    var body: some View {
        @Bindable var settings = settingsStore

        ScrollViewReader { proxy in
            Form {
                SettingsModelSection()

                SettingsKeyboardSection()

                Section {
                    ToggleRow(title: "Auto-copy to clipboard", isOn: $settings.autoCopy)

                    HStack {
                        Text("Max recording duration")
                        Spacer()
                        Text("10 minutes")
                            .foregroundStyle(.secondary)
                    }

                    ToggleRow(title: "Auto-stop on silence", isOn: $settings.autoStopOnSilence)

                    HStack {
                        Text("Silence timeout")
                        Spacer()
                        Text("5 seconds")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Microphone level")
                            Spacer()
                            Text(gainLabel(settings.micGain))
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { gainStep(settings.micGain) },
                                set: { settings.micGain = gainValue(Int($0.rounded())) }
                            ),
                            in: 1...3,
                            step: 1
                        )
                        HStack {
                            Text("Quiet")
                            Spacer()
                            Text("Optimal")
                            Spacer()
                            Text("High")
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        Text("If transcripts come out empty or you sound too quiet, slide to High. If your voice clips or distorts, slide to Quiet. \"Optimal\" is a good starting point.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    SectionHeader(title: "Recording")
                }

                Section {
                    ToggleRow(title: "Save transcriptions to history", isOn: $settings.saveToHistory)

                    Text("When off, transcriptions are not stored")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    SectionHeader(title: "Privacy")
                }

                SettingsLanguageSection()
                    .id("settings-section-language")

                SettingsDictionarySection()

                Section {
                    NavigationRow(title: "Notepad & smart corrections", subtitle: "Phase 2")
                        .disabled(true)
                } header: {
                    SectionHeader(title: "Upcoming")
                }

                Section {
                    Button("Show onboarding again") {
                        settingsStore.onboardingCompleted = false
                    }
                } header: {
                    SectionHeader(title: "Onboarding")
                }

                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Text("About OpenWhisper")
                    }

                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    SectionHeader(title: "About")
                }
            }
            .onAppear { requestScrollIfNeeded(proxy) }
            .onChange(of: settingsRouter.pendingSection) { _, _ in requestScrollIfNeeded(proxy) }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: settingsStore.autoCopy) { _, _ in toast.present("Saved!") }
        .onChange(of: settingsStore.saveToHistory) { _, _ in toast.present("Saved!") }
        .onChange(of: settingsStore.computeUnits) { _, _ in toast.present("Saved!") }
        .onChange(of: settingsStore.languageCode) { _, _ in toast.present("Saved!") }
    }

    private func requestScrollIfNeeded(_ proxy: ScrollViewProxy) {
        guard settingsRouter.pendingSection == "language" else { return }
        DispatchQueue.main.async {
            guard settingsRouter.pendingSection == "language" else { return }
            withAnimation { proxy.scrollTo("settings-section-language", anchor: .center) }
            settingsRouter.pendingSection = nil
        }
    }

    private func gainLabel(_ gain: Double) -> String {
        switch gain {
        case 2: return "Quiet"
        case 8: return "High"
        default: return "Optimal"
        }
    }

    private func gainStep(_ gain: Double) -> Double {
        switch gain {
        case 2: return 1
        case 8: return 3
        default: return 2
        }
    }

    private func gainValue(_ step: Int) -> Double {
        switch step {
        case 1: return 2
        case 3: return 8
        default: return 5
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
