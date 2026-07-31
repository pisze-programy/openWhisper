import SwiftUI

struct SettingsDictionarySection: View {
    @Environment(CorrectionsStore.self) private var corrections

    @State private var wrong = ""
    @State private var correct = ""
    @State private var caseSensitive = false

    var body: some View {
        Section {
            ForEach(corrections.corrections) { correction in
                HStack(spacing: 6) {
                    Text(correction.wrong)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(correction.correct)
                    if correction.caseSensitive {
                        Text("Aa")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    corrections.remove(corrections.corrections[index])
                }
            }

            HStack(spacing: 6) {
                TextField("Heard as", text: $wrong)
                    .autocorrectionDisabled()
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                TextField("Should be", text: $correct)
                    .autocorrectionDisabled()
                Button {
                    caseSensitive.toggle()
                } label: {
                    Text("Aa")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(caseSensitive ? Color.accentColor : Color.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(caseSensitive ? Color.accentColor.opacity(0.15) : Color(.systemGray5))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Exact case")
                .accessibilityValue(caseSensitive ? "On" : "Off")
                Button("Add") {
                    corrections.add(wrong: wrong, correct: correct, caseSensitive: caseSensitive)
                    wrong = ""
                    correct = ""
                    caseSensitive = false
                }
                .disabled(wrong.trimmingCharacters(in: .whitespaces).isEmpty
                          || correct.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            SectionHeader(title: "Dictionary")
        } footer: {
            Text("Fix words Parakeet hears wrong. Corrections apply to new transcriptions.")
        }
    }
}
