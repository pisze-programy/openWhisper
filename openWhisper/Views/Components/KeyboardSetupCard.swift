import SwiftUI

struct KeyboardSetupCard: View {
    @State private var status: KeyboardStatus = .notEnabled

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
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
                    Spacer()
                    statusBadge
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
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .onAppear { refresh() }
    }

    private var statusBadge: some View {
        Group {
            switch status {
            case .enabled:
                Label("Enabled", systemImage: "checkmark")
            case .notEnabled:
                Label("Not added", systemImage: "exclamationmark")
            }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.15), in: Capsule())
        .foregroundStyle(statusColor)
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
