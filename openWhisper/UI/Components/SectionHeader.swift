import SwiftUI

/// Small uppercase secondary section heading.
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}

#Preview {
    SectionHeader(title: "Model")
        .padding()
}
