import SwiftUI

/// The complete dictation surface: idle mic → live waveform + stop/cancel →
/// transcribing spinner → error. Shared by the app and the keyboard extension.
public struct RecordingSurface: View {
    public let isRecording: Bool
    public let isTranscribing: Bool
    public let error: String?
    public let errorTitle: String?
    public let fullAccessNeeded: Bool
    public let elapsed: TimeInterval
    public let getSamples: () -> [Float]
    public let onMicTap: () -> Void
    public let onStop: () -> Void
    public let onCancel: () -> Void
    public let onOpenSettings: () -> Void

    public init(
        isRecording: Bool,
        isTranscribing: Bool,
        error: String?,
        errorTitle: String?,
        fullAccessNeeded: Bool,
        elapsed: TimeInterval,
        getSamples: @escaping () -> [Float],
        onMicTap: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.isRecording = isRecording
        self.isTranscribing = isTranscribing
        self.error = error
        self.errorTitle = errorTitle
        self.fullAccessNeeded = fullAccessNeeded
        self.elapsed = elapsed
        self.getSamples = getSamples
        self.onMicTap = onMicTap
        self.onStop = onStop
        self.onCancel = onCancel
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        // Cap the content column so it stays centered and compact on wide screens (iPad).
        VStack(spacing: AppTheme.largeSpacing) {
            if isTranscribing {
                VStack(spacing: AppTheme.mediumSpacing) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Transcribing…")
                        .font(AppTheme.hintFont)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            } else if isRecording {
                VStack(spacing: AppTheme.mediumSpacing) {
                    LiveWaveform(getSamples: getSamples)
                        .frame(height: 48)
                    Text(timeString(elapsed))
                        .font(AppTheme.timerFont)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 24) {
                        MicRecordButton(isRecording: true, size: AppTheme.appRecordButtonSize, action: onStop)
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
                            .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.opacity)
            } else if fullAccessNeeded || errorTitle != nil {
                // Leading-aligned explanation block — red accent only on the
                // title, the details in gray, and a direct path to the fix.
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
                    }
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            } else {
                VStack(spacing: AppTheme.mediumSpacing) {
                    MicRecordButton(isRecording: false, size: AppTheme.keyboardRecordButtonSize, action: onMicTap)
                    Text(error ?? "Tap the mic to dictate")
                        .font(AppTheme.captionFont)
                        .foregroundStyle(error == nil ? AppTheme.secondaryLabel : AppTheme.destructive)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
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
