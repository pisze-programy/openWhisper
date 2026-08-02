import SwiftUI

public extension View {
    @ViewBuilder
    func glassBackground(cornerRadius: CGFloat = 20) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            self.background(
                AppTheme.surface,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        }
    }
}
