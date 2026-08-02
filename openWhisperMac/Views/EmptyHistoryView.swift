import SwiftUI

struct EmptyHistoryView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                sampleSection
                footer
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            Text("Your transcriptions appear here")
                .font(.title3.weight(.semibold))
            Text("Press right ⌘+⌥ anywhere, speak, and release. Your words are transcribed on-device and pasted into the active app.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding(.top, 60)
        .padding(.bottom, 32)
    }

    private var sampleSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What your notes can look like")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            VStack(spacing: 6) {
                ForEach(SampleCard.all) { card in
                    SampleCardView(card: card)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var footer: some View {
        Text("100% on-device · private by default")
            .font(.caption2)
            .foregroundStyle(.secondary.opacity(0.6))
            .padding(.top, 24)
            .padding(.bottom, 40)
    }
}

private struct SampleCardView: View {
    let card: SampleCard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(card.style, systemImage: card.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(card.duration)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Text(card.text)
                .font(.subheadline)
                .lineLimit(3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
    }
}

private struct SampleCard: Identifiable {
    let id = UUID()
    let style: String
    let icon: String
    let duration: String
    let text: String

    static let all: [SampleCard] = [
        SampleCard(style: "Formal", icon: "textformat", duration: "0:12",
                   text: "I think we should schedule the quarterly review for next Tuesday at 10 AM. Please confirm if this time works for you."),
        SampleCard(style: "Casual", icon: "bubble.left", duration: "0:08",
                   text: "Hey, are you free tomorrow? Let's grab lunch and catch up. I found this great new place near the office."),
        SampleCard(style: "Minimal", icon: "scissors", duration: "0:06",
                   text: "hey just got home, traffic was crazy but made it, call you later"),
        SampleCard(style: "Brief", icon: "list.bullet", duration: "0:05",
                   text: "• Schedule dentist appointment\n• Pick up dry cleaning\n• Send quarterly numbers to Alex"),
    ]
}
