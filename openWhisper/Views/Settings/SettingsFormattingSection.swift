import SwiftUI
import OpenWhisperShared

struct SettingsFormattingSection: View {
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        Section {
            ForEach(TranscriptionStyle.allCases) { style in
                StyleOptionRow(style: style, isSelected: settingsStore.formattingStyle == style) {
                    settingsStore.formattingStyle = style
                }
            }
        } header: {
            SectionHeader(title: "Formatting Style")
        } footer: {
            Text("Pick None for a fast, local transcript with no API request. Other styles are rewritten by a cloud model and need the OpenRouter API key above.")
        }
    }
}

private struct StyleOptionRow: View {
    let style: TranscriptionStyle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: style.systemImage)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .frame(width: 20)
                    Text(style.title)
                        .font(.headline)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }

                Text(style.shortDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Before")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(style.beforeExample)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text("After")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(style.afterExample)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.primary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text("Use for: \(style.whenToUse)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
