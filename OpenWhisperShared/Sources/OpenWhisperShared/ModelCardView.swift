import SwiftUI

public struct ModelCardView: View {
    @Environment(ModelDownloadManager.self) private var modelDownload

    public init() {}

    public var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "waveform.badge.mic")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Parakeet TDT 0.6B v3")
                        .font(.headline)
                }

                if let available = modelDownload.availableFreeSpaceGB,
                   modelDownload.status == .notDownloaded {
                    Text(modelDownload.isLowOnSpace
                         ? String(format: "Low storage — only %.1f GB free.", available)
                         : String(format: "Free space: %.1f GB available.", available))
                        .font(.caption)
                        .foregroundStyle(modelDownload.isLowOnSpace ? .orange : .secondary)
                }

                switch modelDownload.status {
                case .notDownloaded:
                    Button {
                        Task { await modelDownload.startDownload() }
                    } label: {
                        Label("Download Model", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(modelDownload.isLowOnSpace)

                case .downloading(let progress):
                    VStack(alignment: .leading, spacing: 10) {
                        ProgressView(value: progress)
                            .tint(.accentColor)
                        HStack {
                            Text("\(Int(progress * 100))%")
                                .font(.headline.monospacedDigit())
                            if progress > 0 {
                                Text("· \(progressText(for: progress))")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .font(.callout)
                        Text("You can close this window — the download continues in the background.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                case .ready:
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title3)
                        Text("Ready to transcribe")
                            .font(.callout)
                        Spacer()
                    }
                    HStack(spacing: 6) {
                        Text("Wrong version or corrupted?")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Button("Re-download") {
                            Task { await modelDownload.startDownload(force: true) }
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }

                case .failed(let message):
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.title3)
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                    Button {
                        Task { await modelDownload.startDownload() }
                    } label: {
                        Label("Try Again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func progressText(for progress: Double) -> String {
        let doneMB = Int((progress * 480).rounded())
        return "\(doneMB) of ~480 MB"
    }
}
