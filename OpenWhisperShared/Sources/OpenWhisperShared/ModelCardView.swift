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
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Parakeet TDT 0.6B v3")
                            .font(.headline)
                        Text("~480 MB · one-time download")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let available = modelDownload.availableFreeSpaceGB,
                   modelDownload.status == .notDownloaded {
                    Text(modelDownload.isLowOnSpace
                         ? String(format: "Low storage — only %.1f GB free, %.1f GB required.", available, ModelDownloadManager.minRequiredFreeSpaceGB)
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
                            if let eta = modelDownload.etaSeconds, eta.isFinite, eta > 0 {
                                Text("~\(etaText(eta)) left")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
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
        let total = modelDownload.totalMB ?? ModelDownloadManager.modelSizeMB
        let doneMB = Int((progress * total).rounded())
        return "\(doneMB) of ~\(Int(total.rounded())) MB"
    }

    private func etaText(_ seconds: TimeInterval) -> String {
        if seconds >= 60 {
            let minutes = Int(seconds / 60)
            let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
            return "\(minutes) min \(secs) s"
        }
        return "\(Int(seconds)) s"
    }
}
