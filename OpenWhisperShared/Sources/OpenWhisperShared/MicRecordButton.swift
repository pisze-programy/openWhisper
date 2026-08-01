import SwiftUI

/// The OpenWhisper record button — shared by the app and the keyboard
/// extension so both use the identical look.
public struct MicRecordButton: View {
    public let isRecording: Bool
    public let size: CGFloat
    public let action: () -> Void

    public init(isRecording: Bool, size: CGFloat = 72, action: @escaping () -> Void) {
        self.isRecording = isRecording
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isRecording ? AnyShapeStyle(Color.red) : AnyShapeStyle(.ultraThinMaterial))
                    .frame(width: size, height: size)
                    .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(isRecording ? .white : Color.accentColor)
            }
        }
        .buttonStyle(.plain)
    }
}
