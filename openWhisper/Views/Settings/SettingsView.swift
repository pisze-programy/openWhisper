import SwiftUI
import Foundation

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(ToastCenter.self) private var toast

    var body: some View {
        @Bindable var settings = settingsStore

        Form {
            SettingsModelSection()

            Section {
                ToggleRow(title: "Auto-copy to clipboard", isOn: $settings.autoCopy)

                HStack {
                    Text("Max recording duration")
                    Spacer()
                    Text("10 minutes")
                        .foregroundStyle(.secondary)
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
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: settingsStore.autoCopy) { _, _ in toast.present("Saved!") }
        .onChange(of: settingsStore.saveToHistory) { _, _ in toast.present("Saved!") }
        .onChange(of: settingsStore.computeUnits) { _, _ in toast.present("Saved!") }
        .onChange(of: settingsStore.languageCode) { _, _ in toast.present("Saved!") }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
