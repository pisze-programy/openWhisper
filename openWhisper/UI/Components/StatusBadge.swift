import SwiftUI

/// Compact capsule showing the model download state with an SF Symbol and short label.
struct StatusBadge: View {
    let status: ModelStatus

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(label)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
    }

    private var icon: String {
        switch status {
        case .notDownloaded: return "arrow.down.circle"
        case .downloading: return "arrow.down.circle.fill"
        case .ready: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        }
    }

    private var label: String {
        switch status {
        case .notDownloaded: return "Not downloaded"
        case .downloading(let progress): return "Downloading \(Int(progress * 100))%"
        case .ready: return "Ready"
        case .failed: return "Failed"
        }
    }

    private var color: Color {
        switch status {
        case .notDownloaded: return .gray
        case .downloading: return .blue
        case .ready: return .green
        case .failed: return .red
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        StatusBadge(status: .ready)
        StatusBadge(status: .downloading(progress: 0.42))
        StatusBadge(status: .notDownloaded)
        StatusBadge(status: .failed("Network error"))
    }
    .padding()
}
