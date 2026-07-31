import SwiftUI

struct KeyboardSetupCard: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var status: KeyboardStatus = .notEnabled

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                statusBadge
                    .fixedSize()

                HStack(spacing: 10) {
                    Image(systemName: "keyboard")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keyboard extension")
                            .font(.headline)
                        Text("Insert transcriptions into any text field")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                switch status {
                case .enabled:
                    Label("Your OpenWhisper keyboard is enabled. Tap a transcription to insert it.", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                case .notEnabled:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("To add it:")
                            .font(.footnote.weight(.semibold))
                        Text("1. Open iOS Settings\n2. General → Keyboard → Keyboards\n3. Add New Keyboard → OpenWhisper")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button {
                            KeyboardDetector.openSettings()
                        } label: {
                            Label("Open iOS Settings", systemImage: "gear")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        Text("The status updates after you open the keyboard once.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .onAppear { refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(label)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(statusColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(statusColor.opacity(0.12), in: Capsule())
    }

    private var icon: String {
        switch status {
        case .enabled: return "checkmark"
        case .notEnabled: return "exclamationmark"
        }
    }

    private var label: String {
        switch status {
        case .enabled: return "Enabled"
        case .notEnabled: return "Not added"
        }
    }

    private var statusColor: Color {
        switch status {
        case .enabled: .green
        case .notEnabled: .orange
        }
    }

    private func refresh() {
        status = KeyboardDetector.status
    }
}
