import SwiftUI

/// The complete dictation surface: idle mic → live waveform + stop/cancel →
/// transcribing spinner → error. Shared by the app and the keyboard extension.
public struct RecordingSurface: View {
    public let isRecording: Bool
    public let isTranscribing: Bool
    public let error: String?
    public let elapsed: TimeInterval
    public let getSamples: () -> [Float]
    public let onMicTap: () -> Void
    public let onStop: () -> Void
    public let onCancel: () -> Void

    public init(
        isRecording: Bool,
        isTranscribing: Bool,
        error: String?,
        elapsed: TimeInterval,
        getSamples: @escaping () -> [Float],
        onMicTap: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.isRecording = isRecording
        self.isTranscribing = isTranscribing
        self.error = error
        self.elapsed = elapsed
        self.getSamples = getSamples
        self.onMicTap = onMicTap
        self.onStop = onStop
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 16) {
            if isTranscribing {
                ProgressView()
                    .controlSize(.large)
                Text("Transcribing…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if isRecording {
                VStack(spacing: 14) {
                    LiveWaveform(getSamples: getSamples)
                        .frame(height: 48)
                    Text(timeString(elapsed))
                        .font(.system(.title3, design: .monospaced))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 24) {
                        MicRecordButton(isRecording: true, size: 72, action: onStop)
                        Button(action: onCancel) {
                            Image(systemName: "xmark")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                VStack(spacing: 14) {
                    MicRecordButton(isRecording: false, size: 88, action: onMicTap)
                    Text(error ?? "Tap the mic to dictate")
                        .font(.footnote)
                        .foregroundStyle(error == nil ? Color.secondary : Color.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func timeString(_ t: TimeInterval) -> String {
        let total = Int(t)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
