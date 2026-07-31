import SwiftUI

/// A settings row with a title and a right-aligned native toggle.
struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
        }
    }
}

#Preview {
    ToggleRow(title: "Auto-copy to clipboard", isOn: .constant(true))
        .padding()
}
