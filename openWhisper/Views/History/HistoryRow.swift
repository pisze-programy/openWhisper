import SwiftUI
import OpenWhisperShared

/// A timeline note: a dot on the leading rail, the hour + duration (gray) in a
/// narrow leading column, the full note text to the right. Tap copies; long-press
/// shows the Copy/Delete menu. There is no expansion.
struct HistoryRow: View {
    let item: TranscriptionItem
    var onCopy: () -> Void
    var onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(item.createdAt, format: .dateTime.hour().minute())
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryLabel)
                    Text(item.duration.clockString)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
                .frame(width: 44, alignment: .trailing)

                Text(item.text)
                    .font(.body)
                    .textSelection(.enabled)

                Spacer(minLength: 0)
            }
            .padding(.leading, 32)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture(perform: onCopy)
            .contextMenu {
                Button {
                    onCopy()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }

            // Dot centered on the rail (rail is a 1 pt line at x = 15).
            TimelineDot(style: .note)
                .padding(.leading, 11.5)
        }
    }
}

/// A dot marker that sits on the timeline rail. The note dot is small and
/// secondary; the day-header dot is slightly larger and accent-colored.
struct TimelineDot: View {
    enum Style {
        case header
        case note
    }

    let style: Style

    var body: some View {
        Circle()
            .fill(style == .header ? AppTheme.accent : AppTheme.secondaryLabel.opacity(0.5))
            .frame(width: style == .header ? 9 : 7, height: style == .header ? 9 : 7)
    }
}
