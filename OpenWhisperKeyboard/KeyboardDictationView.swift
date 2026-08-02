import SwiftUI
import OpenWhisperShared

struct KeyboardDictationView: View {
    @ObservedObject var model: KeyboardDictationModel
    let onOpenSettings: () -> Void
    let onOpenLanguageSettings: () -> Void

    @State private var contentVisible = false

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isCompactHeight: Bool { verticalSizeClass == .compact }

    var body: some View {
        VStack(spacing: 0) {
            if !isCompactHeight {
                HStack {
                    Spacer()
                    languageChip
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
            }
            RecordingSurface(
                isRecording: model.isRecording,
                isTranscribing: model.isTranscribing,
                error: model.error,
                errorTitle: model.errorTitle,
                fullAccessNeeded: model.fullAccessNeeded,
                elapsed: model.elapsed,
                isMicEnabled: model.isFullAccessGranted,
                micDisabledHint: model.isFullAccessGranted ? nil : "Enable Full Access in iOS Settings to use dictation",
                getSamples: { model.liveSamples },
                onMicTap: { model.start() },
                onStop: { model.stop() },
                onCancel: { model.cancel() },
                onOpenSettings: onOpenSettings,
                onRetry: {
                    if model.needsAppOpen {
                        model.onOpenApp?()
                    } else {
                        model.retry()
                    }
                }
            )
        }
        .opacity(contentVisible ? 1 : 0)
        .onAppear {
            contentVisible = false
            withAnimation(.easeOut(duration: 0.3).delay(0.5)) {
                contentVisible = true
            }
        }
    }

    private var languageChip: some View {
        Button(action: onOpenLanguageSettings) {
            Label(model.currentLanguageName, systemImage: "globe")
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.secondaryLabel)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(AppTheme.surface))
        }
        .buttonStyle(.plain)
    }
}
