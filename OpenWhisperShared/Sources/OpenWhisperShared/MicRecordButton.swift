import SwiftUI

/// The OpenWhisper record button — shared by the app and the keyboard
/// extension so both use the identical look.
public struct MicRecordButton: View {
    public let isRecording: Bool
    public let size: CGFloat
    public let action: () -> Void

    public init(isRecording: Bool, size: CGFloat = AppTheme.appRecordButtonSize, action: @escaping () -> Void) {
        self.isRecording = isRecording
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                if isRecording {
                    Circle()
                        .fill(AnyShapeStyle(AppTheme.destructive))
                        .frame(width: size, height: size)
                        .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
                } else if #available(iOS 26.0, *) {
                    // Liquid Glass: the record button is a floating overlay element,
                    // so it gets a glass effect with an accent tint + press feedback.
                    Circle()
                        .fill(.clear)
                        .frame(width: size, height: size)
                        .glassEffect(
                            .regular.tint(AppTheme.accent.opacity(0.18)).interactive(),
                            in: Circle()
                        )
                        .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
                } else {
                    Circle()
                        .fill(AppTheme.surface)
                        .frame(width: size, height: size)
                        .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
                }
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(isRecording ? .white : AppTheme.accent)
            }
        }
        .buttonStyle(.plain)
    }
}
