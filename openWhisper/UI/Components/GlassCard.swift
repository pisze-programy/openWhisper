import SwiftUI

/// A reusable frosted-glass card: rounded corners, ultra-thin material, subtle shadow.
/// This is the only place glass styling is applied — never ad hoc per screen.
struct GlassCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
    }
}

#Preview {
    GlassCard {
        Text("Hello, glass.")
    }
    .padding()
}
