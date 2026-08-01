import SwiftUI

struct ModelCardView: View {
    @Environment(ModelDownloadManager.self) private var modelDownload

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                // The progress bar below already shows the download percentage —
                // the badge would duplicate it, so it's hidden while downloading.
                switch modelDownload.status {
                case .downloading:
                    EmptyView()
                default:
                    StatusBadge(status: modelDownload.status)
                        .fixedSize()
                }

                HStack(spacing: 10) {
                    Image(systemName: "waveform.badge.mic")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Parakeet TDT 0.6B v3")
                            .font(.headline)
                        Text("On-device speech-to-text · ~480 MB download · 25 European languages")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if modelDownload.status == .notDownloaded {
                    if let available = modelDownload.availableFreeSpaceGB {
                        Text(modelDownload.isLowOnSpace
                             ? String(format: "Low storage — only %.1f GB free. The model needs ~%.1f GB; the download may fail.", available, ModelDownloadManager.minRequiredFreeSpaceGB)
                             : String(format: "Free space: %.1f GB — model needs ~%.1f GB.", available, ModelDownloadManager.minRequiredFreeSpaceGB))
                            .font(.caption)
                            .foregroundStyle(modelDownload.isLowOnSpace ? .orange : .secondary)
                    }
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

                case .downloading(let progress):
                    VStack(alignment: .leading, spacing: 8) {
                        if progress > 0 {
                            ProgressView(value: progress)
                            Text("\(Int(progress * 100))% · \(progressText(for: progress))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                            Text("Downloading…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("You can leave this screen anytime — the download is resumable.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                case .ready:
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Saved on this device — ready to transcribe")
                            .font(.footnote)
                    }
                    HStack(spacing: 8) {
                        Text("Something went wrong?")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button {
                            Task { await modelDownload.startDownload(force: true) }
                        } label: {
                            Text("Re-download Model")
                        }
                        .font(.footnote)
                        .buttonStyle(.borderless)
                    }

                case .failed(let message):
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
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
        return "\(doneMB) MB of ~480 MB"
    }
}
