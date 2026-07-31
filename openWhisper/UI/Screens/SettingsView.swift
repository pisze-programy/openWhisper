import SwiftUI
import Foundation
import ParakeetTDT

/// Settings: model status/download, compute units, recording, privacy, reserved and about sections.
struct SettingsView: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(ModelDownloadManager.self) private var modelDownload

    private let computeUnitOptions: [(unit: ParakeetComputeUnits, label: String)] = [
        (unit: .ane, label: "ANE"),
        (unit: .gpu, label: "GPU"),
        (unit: .cpu, label: "CPU"),
        (unit: .all, label: "All"),
    ]

    var body: some View {
        @Bindable var settings = settingsStore

        Form {
            Section {
                HStack {
                    Text("Status")
                    Spacer()
                    StatusBadge(status: modelDownload.status)
                }

                Text(statusDetailText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if modelDownload.isReady {
                    Button("Re-download Model") {
                        Task { await modelDownload.startDownload(force: true) }
                    }
                } else {
                    switch modelDownload.status {
                    case .downloading(let progress):
                        HStack(spacing: 8) {
                            if progress > 0 {
                                ProgressView(value: progress)
                            } else {
                                ProgressView()
                            }
                            Text("Downloading…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    default:
                        Button("Download Model") {
                            Task { await modelDownload.startDownload() }
                        }
                    }
                }

                Picker("Compute Units", selection: $settings.computeUnits) {
                    ForEach(computeUnitOptions, id: \.label) { option in
                        Text(option.label).tag(option.unit)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                SectionHeader(title: "Model")
            }

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

            Section {
                NavigationRow(title: "Language", subtitle: "English, Polish")
                    .disabled(true)
                NavigationRow(title: "Notepad & smart corrections", subtitle: "Phase 2")
                    .disabled(true)
            } header: {
                SectionHeader(title: "Upcoming")
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
    }

    private var statusDetailText: String {
        switch modelDownload.status {
        case .notDownloaded:
            return "The model is not on this device yet. Transcription is blocked until it is downloaded."
        case .downloading(let progress):
            return "Downloading… \(Int(progress * 100))%"
        case .ready:
            return "Downloaded and active on this device."
        case .failed:
            return "The download failed. Check your connection and try again."
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
