import SwiftUI
import OpenWhisperShared

/// SwiftUI root for the keyboard: observes the model so state changes animate
/// in place (no per-change UIHostingController rebuilds).
struct KeyboardDictationView: View {
    @ObservedObject var model: KeyboardDictationModel
    let onOpenSettings: () -> Void

    /// Content fades in only after the system's keyboard-presentation animation
    /// has finished, masking the mic's layout jump during expansion.
    @State private var contentVisible = false

    var body: some View {
        RecordingSurface(
            isRecording: model.isRecording,
            isTranscribing: model.isTranscribing,
            error: model.error,
            errorTitle: model.errorTitle,
            fullAccessNeeded: model.fullAccessNeeded,
            elapsed: model.elapsed,
            getSamples: { model.liveSamples },
            onMicTap: { model.start() },
            onStop: { model.stop() },
            onCancel: { model.cancel() },
            onOpenSettings: onOpenSettings
        )
        .opacity(contentVisible ? 1 : 0)
        .onAppear {
            contentVisible = false
            withAnimation(.easeOut(duration: 0.3).delay(0.5)) {
                contentVisible = true
            }
        }
    }
}
