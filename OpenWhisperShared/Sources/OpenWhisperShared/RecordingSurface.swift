import SwiftUI

public struct RecordingSurface: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    public let isRecording: Bool
    public let isTranscribing: Bool
    public let error: String?
    public let errorTitle: String?
    public let fullAccessNeeded: Bool
    public let elapsed: TimeInterval

    public let isMicEnabled: Bool

    public let micDisabledHint: String?
    public let getSamples: () -> [Float]
    public let onMicTap: () -> Void
    public let onStop: () -> Void
    public let onCancel: () -> Void
    public let onOpenSettings: () -> Void

    public let onRetry: () -> Void

    public init(
        isRecording: Bool,
        isTranscribing: Bool,
        error: String?,
        errorTitle: String?,
        fullAccessNeeded: Bool,
        elapsed: TimeInterval,
        isMicEnabled: Bool = true,
        micDisabledHint: String? = nil,
        getSamples: @escaping () -> [Float],
        onMicTap: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onRetry: @escaping () -> Void = {}
    ) {
        self.isRecording = isRecording
        self.isTranscribing = isTranscribing
        self.error = error
        self.errorTitle = errorTitle
        self.fullAccessNeeded = fullAccessNeeded
        self.elapsed = elapsed
        self.isMicEnabled = isMicEnabled
        self.micDisabledHint = micDisabledHint
        self.getSamples = getSamples
        self.onMicTap = onMicTap
        self.onStop = onStop
        self.onCancel = onCancel
        self.onOpenSettings = onOpenSettings
        self.onRetry = onRetry
    }

    private var isCompactHeight: Bool { verticalSizeClass == .compact }

    private var buttonSize: CGFloat { isCompactHeight ? 64 : AppTheme.keyboardRecordButtonSize }
    private var waveformHeight: CGFloat { isCompactHeight ? 32 : 48 }
    private var cancelButtonSize: CGFloat { isCompactHeight ? 36 : 44 }
    private var outerSpacing: CGFloat { isCompactHeight ? AppTheme.smallSpacing : AppTheme.largeSpacing }
    private var innerSpacing: CGFloat { isCompactHeight ? AppTheme.smallSpacing : AppTheme.mediumSpacing }

    public var body: some View {

        VStack(spacing: outerSpacing) {
            if isTranscribing {
                VStack(spacing: innerSpacing) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Transcribing…")
                        .font(AppTheme.hintFont)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            } else if isRecording {
                VStack(spacing: innerSpacing) {
                    LiveWaveform(getSamples: getSamples)
                        .frame(height: waveformHeight)
                    Text(timeString(elapsed))
                        .font(AppTheme.timerFont)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 24) {
                        MicRecordButton(isRecording: true, size: buttonSize, action: onStop)
                        Button(action: onCancel) {
                            ZStack {
                                if #available(iOS 26.0, *) {
                                    Circle()
                                        .fill(.clear)
                                        .glassEffect(.regular, in: Circle())
                                } else {
                                    Circle().fill(AppTheme.surface)
                                }
                                Image(systemName: "xmark")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: cancelButtonSize, height: cancelButtonSize)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.opacity)
            } else if fullAccessNeeded || errorTitle != nil {

                VStack(alignment: .leading, spacing: 8) {
                    Text(errorTitle ?? "Full access needed:")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.destructive)
                    Text(error ?? "")
                        .font(AppTheme.captionFont)
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                    if fullAccessNeeded {
                        Text("Settings → Keyboard → OpenWhisper → Allow Full Access")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            onOpenSettings()
                        } label: {
                            Label("Open Settings", systemImage: "arrow.up.right.square")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                        }
                        .padding(.top, 2)
                    } else {
                        Button {
                            onRetry()
                        } label: {
                            Label("Try Again", systemImage: "arrow.clockwise")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            } else {

                Group {
                    if isCompactHeight {
                        HStack(spacing: AppTheme.mediumSpacing) {
                            MicRecordButton(isRecording: false, size: buttonSize, isEnabled: isMicEnabled, action: onMicTap)
                            Text(micDisabledHint ?? error ?? "Tap the mic to dictate")
                                .font(.caption2)
                                .foregroundStyle(micDisabledHint != nil || error != nil ? AppTheme.destructive : AppTheme.secondaryLabel)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 24)
                    } else {
                        VStack(spacing: innerSpacing) {
                            MicRecordButton(isRecording: false, size: buttonSize, isEnabled: isMicEnabled, action: onMicTap)
                            Text(micDisabledHint ?? error ?? "Tap the mic to dictate")
                                .font(AppTheme.captionFont)
                                .foregroundStyle(micDisabledHint != nil || error != nil ? AppTheme.destructive : AppTheme.secondaryLabel)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: isRecording)
        .animation(.easeInOut(duration: 0.2), value: isTranscribing)
        .animation(.easeInOut(duration: 0.2), value: error)
    }

    private func timeString(_ t: TimeInterval) -> String {
        let total = Int(t)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
