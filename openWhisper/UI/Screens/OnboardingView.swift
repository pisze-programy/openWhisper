import SwiftUI

/// Two-step onboarding: intro + model download. Shown on every launch during testing (plan §4c / D11).
struct OnboardingView: View {
    var onFinish: () -> Void
    var onSkip: (() -> Void)? = nil

    @Environment(ModelDownloadManager.self) private var modelDownload

    @State private var step = 0

    private let totalSteps = 2

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    if step == 0 {
                        introStep
                    } else {
                        modelStep
                    }
                }
                .frame(maxWidth: .infinity)

                Spacer(minLength: 16)

                pageDots
                primaryButton
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") { skip() }
                }
            }
        }
    }

    // MARK: - Step 1: Intro

    private var introStep: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "waveform")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.tint)
                    .padding(.top, 24)

                Text("OpenWhisper")
                    .font(.largeTitle.bold())

                Text("Turn your speech into text on your device.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                GlassCard {
                    Text("“Speak three times faster than you type.”")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                }

                VideoPlaceholder()
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Step 2: Model download

    private var modelStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "One-time model download")

                Text("OpenWhisper runs entirely on your device. Before you can transcribe, the speech model is downloaded once (~450 MB). Your audio never leaves your phone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                switch modelDownload.status {
                case .notDownloaded:
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("~450 MB, one-time download", systemImage: "arrow.down.circle")
                            Label("Runs fully on-device", systemImage: "lock.fill")
                            Label("Works offline after download", systemImage: "internaldrive")
                        }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Task { await modelDownload.startDownload() }
                    } label: {
                        Text("Start Download")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 4)

                case .downloading(let progress):
                    VStack(spacing: 10) {
                        if progress > 0 {
                            ProgressView(value: progress)
                            Text("\(Int(progress * 100))% — you can leave this screen anytime; the download is resumable and will continue when you retry it")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            // No byte count yet — show an indeterminate spinner
                            // so the screen never looks stuck at 0%.
                            ProgressView()
                            Text("Downloading…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 8)

                case .ready:
                    Label("Model ready", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                        .padding(.top, 8)

                case .failed(let message):
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Download failed", systemImage: "exclamationmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.red)
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Try Again") {
                            Task { await modelDownload.startDownload() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Controls

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Circle()
                    .fill(index == step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 16)
    }

    private var primaryButton: some View {
        Button {
            if step == 0 {
                withAnimation { step = 1 }
            } else {
                onFinish()
            }
        } label: {
            Text(step == 0 ? "Next" : "Finish")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func skip() {
        if let onSkip {
            onSkip()
        } else {
            onFinish()
        }
    }
}

/// 16:9 demo video placeholder — a real video player can be dropped in later.
private struct VideoPlaceholder: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black)

            VStack(spacing: 10) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.white.opacity(0.9))
                Text("Demo video coming soon")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
    }
}
