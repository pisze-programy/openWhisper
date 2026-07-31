import SwiftUI

/// A tappable-looking row with an optional subtitle and a trailing chevron.
struct NavigationRow: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }
}

#Preview {
    VStack {
        NavigationRow(title: "Language", subtitle: "English, Polish")
        NavigationRow(title: "Notepad & smart corrections", subtitle: "Phase 2")
    }
    .padding()
}
