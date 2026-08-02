import SwiftData
import SwiftUI
import OpenWhisperShared

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ToastCenter.self) private var toast

    @Query(sort: \TranscriptionItem.createdAt, order: .reverse)
    private var items: [TranscriptionItem]

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyHistoryView()
            } else {
                timeline
            }
        }
        .navigationTitle("History")
    }

    private var timeline: some View {
        ScrollView {
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.secondary.opacity(0.2))
                    .frame(width: 1)
                    .padding(.leading, 15.5)

                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sections, id: \.day) { section in
                        dayHeader(section.day)
                        ForEach(section.items) { item in
                            historyRow(item)
                        }
                    }
                }
                .padding(.leading, 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
    }

    private typealias Section = (day: Date, items: [TranscriptionItem])

    private var sections: [Section] {
        let cal = Calendar.current
        return Dictionary(grouping: items) { cal.startOfDay(for: $0.createdAt) }
            .map { (day: $0.key, items: $0.value) }
            .sorted { $0.day > $1.day }
    }

    private func dayHeader(_ day: Date) -> some View {
        ZStack(alignment: .leading) {
            Text(day, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                .font(.subheadline.weight(.semibold))
                .padding(.leading, 34).padding(.top, 14).padding(.bottom, 6)

            Circle().fill(.blue).frame(width: 9, height: 9).padding(.leading, 11.5)
        }
    }

    private func historyRow(_ item: TranscriptionItem) -> some View {
        ZStack(alignment: .leading) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(item.createdAt, format: .dateTime.hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                    Text(item.duration.formattedDuration)
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(width: 44, alignment: .trailing)

                Text(item.text)
                    .font(.body).textSelection(.enabled).lineLimit(4)

                Spacer(minLength: 0)
            }
            .padding(.leading, 34).padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture { copy(item) }
            .contextMenu {
                Button("Copy") { copy(item) }
                Button("Delete", role: .destructive) { delete(item) }
            }

            Circle().fill(.secondary.opacity(0.5)).frame(width: 7, height: 7).padding(.leading, 12.5)
        }
    }

    private func copy(_ item: TranscriptionItem) {
        MacClipboardService.shared.copy(item.text)
        toast.present("Copied!")
    }

    private func delete(_ item: TranscriptionItem) {
        withAnimation(.easeInOut(duration: 0.2)) { modelContext.delete(item) }
        try? modelContext.save()
    }
}

private extension TimeInterval {
    var formattedDuration: String {
        let total = Int(self)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
