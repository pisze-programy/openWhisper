import SwiftUI

struct GlassCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .glassBackground(cornerRadius: 20)
            .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
    }
}
