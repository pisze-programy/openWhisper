import SwiftUI
import ParakeetTDT

struct SettingsModelSection: View {
    @Environment(SettingsStore.self) private var settingsStore

    private let computeUnitOptions: [(unit: ParakeetComputeUnits, label: String)] = [
        (unit: .ane, label: "ANE (Apple Neural Engine)"),
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
            Text("Which hardware runs the transcription on your device. ANE (Apple Neural Engine) is the default — best balance of speed and battery. GPU can be faster on some devices; CPU uses the least memory.")
        }
    }
}
