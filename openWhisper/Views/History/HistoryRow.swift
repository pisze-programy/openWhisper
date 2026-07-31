import SwiftUI
import OpenWhisperShared

struct HistoryRow: View {
    let item: TranscriptionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.text)
                .lineLimit(3)
            Text("\(item.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(item.duration.clockString)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
