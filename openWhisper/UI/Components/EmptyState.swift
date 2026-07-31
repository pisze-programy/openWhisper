import SwiftUI

/// Centered empty-state placeholder: icon, title, subtitle.
struct EmptyState: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }
}

#Preview {
    EmptyState(
        systemImage: "waveform",
        title: "No transcriptions yet",
        subtitle: "Tap the mic and start speaking"
    )
}
