import SwiftUI

public struct SectionHeader: View {
    public let title: String

    public init(title: String) {
        self.title = title
    }

    public var body: some View {
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
