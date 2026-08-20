import SwiftUI
import OpenWhisperShared

/// macOS speech-model card driven by the real FluidAudio engine state
/// (`MacTranscriptionService`), not the iOS Core ML download manager.
/// Shows missing/loading/ready/failed and triggers `warmUp()` on demand.
struct MacModelCardView: View {
    @Environment(MacTranscriptionService.self) private var transcription

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "waveform.badge.mic")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Parakeet TDT 0.6B v3")
                            .font(.headline)
                        Text("~480 MB · one-time download")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if transcription.isModelReady {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title3)
                        Text("Ready to transcribe")
                            .font(.callout)
                        Spacer()
                    }
                } else if let error = transcription.modelError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.title3)
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                    Button {
                        Task { await transcription.downloadAndWarmUp() }
                    } label: {
                        Label("Try Again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                } else if transcription.isWarmingUp {
                    VStack(alignment: .leading, spacing: 10) {
                        ProgressView()
                            .tint(.accentColor)
                        Text("Downloading the speech model (~480 MB)…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("You can close this window — the download continues in the background.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Button {
                        Task { await transcription.downloadAndWarmUp() }
                    } label: {
                        Label("Download Model", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
