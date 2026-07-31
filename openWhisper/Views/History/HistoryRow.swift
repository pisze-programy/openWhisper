import SwiftUI
import OpenWhisperShared

struct HistoryRow: View {
    let item: TranscriptionItem
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.text)
                .lineLimit(isExpanded ? nil : 2)
            HStack(spacing: 4) {
                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(item.duration.clockString)
                    .fontWeight(.semibold)
                    .foregroundStyle(.red)
            }
            .font(.caption)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }
}
