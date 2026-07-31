import SwiftUI
import Foundation

struct AboutView: View {
    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(.tint)
                        .padding(.top, 24)

                    Text("OpenWhisper")
                        .font(.title2.bold())

                    Text("Version \(appVersion)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("Turn your speech into text on your device.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                        .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)

            Section("Licenses & Attribution") {
                Text("App source code: Apache-2.0.")
                    .font(.footnote)
                Text("Model: CC-BY-4.0 — Parakeet TDT 0.6B v3 © NVIDIA. Core ML conversion by mweinbach1.")
                    .font(.footnote)
                Text("Package parakeet-coreml-swift: Apache-2.0.")
                    .font(.footnote)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
