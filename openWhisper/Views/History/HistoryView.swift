import SwiftUI
import SwiftData
import UIKit
import OpenWhisperShared

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings
    @Environment(ModelDownloadManager.self) private var modelDownload
    @Environment(TranscriptionService.self) private var transcription
    @Environment(AudioRecorder.self) private var recorder

    @Query(sort: \TranscriptionItem.createdAt, order: .reverse)
    private var items: [TranscriptionItem]

    @State private var showClearConfirm = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isHandlingRecording = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { item in
                    HistoryRow(item: item)
                        .contentShape(Rectangle())
                        .onTapGesture { copy(item) }
                }
                .onDelete(perform: deleteItems)
            }
            .overlay {
                if items.isEmpty {
                    EmptyState(
                        systemImage: "waveform",
                        title: "No transcriptions yet",
                        subtitle: "Tap the mic and start speaking"
                    )
                }
            }
            .safeAreaInset(edge: .bottom) {
                recordSection
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            .navigationTitle("OpenWhisper")
            .toolbar {
                if !items.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Clear All", role: .destructive) {
                            showClearConfirm = true
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .confirmationDialog(
                "Clear all transcriptions?",
                isPresented: $showClearConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear All", role: .destructive) { clearAll() }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
        .task {
            recorder.onAutoStop = { stopAndTranscribe() }
        }
    }

    private var recordSection: some View {
        VStack(spacing: 10) {
            if !modelDownload.isReady {
                NavigationLink {
                    SettingsView()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Transcription not supported — download the model in Settings")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            GlassCard {
                VStack(spacing: 12) {
                    if transcription.isTranscribing || isHandlingRecording {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Transcribing…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        Button {
                            if recorder.isRecording {
                                stopAndTranscribe()
                            } else {
                                startRecording()
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(recorder.isRecording ? Color.red : Color.accentColor)
                                    .frame(width: 72, height: 72)
                                    .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
                                Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!modelDownload.isReady || isHandlingRecording)

                        Text(recorder.isRecording ? recorder.elapsed.clockString : "Tap to record")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
        }
    }

    private func startRecording() {
        guard modelDownload.isReady, !transcription.isTranscribing, !isHandlingRecording else { return }
        Task { @MainActor in
            do {
                try await recorder.start()
            } catch {
                present(error)
            }
        }
    }

    private func stopAndTranscribe() {
        guard recorder.isRecording, !transcription.isTranscribing, !isHandlingRecording else { return }
        isHandlingRecording = true
        do {
            let url = try recorder.stop()
            Task { @MainActor in
                await transcribe(url: url)
                isHandlingRecording = false
            }
        } catch {
            isHandlingRecording = false
            present(error)
        }
    }

    private func transcribe(url: URL) async {
        do {
            let result = try await transcription.transcribe(audioURL: url)
            if settings.autoCopy {
                ClipboardService.copy(result.text)
            }
            if settings.saveToHistory {
                let item = TranscriptionItem(text: result.text, duration: result.audioDuration, source: "mic")
                modelContext.insert(item)
                do {
                    try modelContext.save()
                } catch {
                    present(error)
                }
            }
        } catch {
            present(error)
        }
        try? FileManager.default.removeItem(at: url)
    }

    private func copy(_ item: TranscriptionItem) {
        ClipboardService.copy(item.text)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(items[index])
        }
        do {
            try modelContext.save()
        } catch {
            present(error)
        }
    }

    private func clearAll() {
        for item in items {
            modelContext.delete(item)
        }
        do {
            try modelContext.save()
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}
