import SwiftUI

public struct MicRecordButton: View {
    public let isRecording: Bool
    public let size: CGFloat

    public let isEnabled: Bool
    public let action: () -> Void

    public init(
        isRecording: Bool,
        size: CGFloat = AppTheme.appRecordButtonSize,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.isRecording = isRecording
        self.size = size
        self.isEnabled = isEnabled
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

            .opacity(isEnabled ? 1 : 0.4)
            .saturation(isEnabled ? 1 : 0.1)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
