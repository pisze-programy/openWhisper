import SwiftUI
import ParakeetTDT

struct SettingsModelSection: View {
    @Environment(SettingsStore.self) private var settingsStore

    private let computeUnitOptions: [(unit: ParakeetComputeUnits, label: String)] = [
        (unit: .gpu, label: "GPU"),
        (unit: .cpu, label: "CPU"),
        (unit: .all, label: "All"),
    ]

    var body: some View {
        @Bindable var settings = settingsStore

        Section {
            ModelCardView()
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            Picker("Compute Units", selection: $settings.computeUnits) {
                ForEach(computeUnitOptions, id: \.label) { option in
                    Text(option.label).tag(option.unit)
                }
            }
            .pickerStyle(.menu)
        } header: {
            SectionHeader(title: "Model")
        } footer: {
            Text("Which hardware runs the transcription on your device. GPU is the default — fastest on most devices. CPU uses the least memory; All lets Core ML choose.")
        }
    }
}
