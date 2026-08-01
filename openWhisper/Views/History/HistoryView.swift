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
    @Environment(ToastCenter.self) private var toast
    @Environment(CorrectionsStore.self) private var corrections

    @Query(sort: \TranscriptionItem.createdAt, order: .reverse)
    private var items: [TranscriptionItem]

    @State private var showDeleteConfirm = false
    @State private var itemPendingDelete: TranscriptionItem?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isHandlingRecording = false

    private static let shortClipMaxDuration: TimeInterval = 1.0
    private static let confidenceGateThreshold: Float = 0.55

    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { item in
                    HistoryRow(item: item)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .glassBackground(cornerRadius: 16)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                        .contextMenu {
                            Button {
                                copy(item)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            Button(role: .destructive) {
                                itemPendingDelete = item
                                showDeleteConfirm = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
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
            .overlay(alignment: .bottom) {
                recordSection
            }
            .contentMargins(.bottom, 210, for: .scrollContent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("OpenWhisper")
                        .font(.subheadline.weight(.semibold))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .alert(
                "Delete this transcription?",
                isPresented: $showDeleteConfirm,
                presenting: itemPendingDelete
            ) { item in
                Button("Delete", role: .destructive) { delete(item) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This cannot be undone.")
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
        .task {
            recorder.onAutoStop = { stopAndTranscribe() }
            removeJunkEntries()
        }
    }

    private var waveformContainer: some View {
        LiveWaveform(getSamples: { recorder.liveSamples })
            .frame(maxWidth: .infinity)
            .frame(height: recorder.isRecording ? 52 : 0, alignment: .center)
            .clipped()
    }

    private var recordSection: some View {
        VStack(spacing: 10) {
            waveformContainer

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

            ZStack {
                if transcription.isTranscribing || isHandlingRecording {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Transcribing…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    } else {
                        VStack(spacing: 12) {
                            MicRecordButton(isRecording: recorder.isRecording, size: 72) {
                                // Tapping alone does nothing — recording is press-and-hold
                            }
                            .disabled(!modelDownload.isReady || isHandlingRecording || !transcription.isModelReady)
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { _ in
                                        guard !recorder.isRecording else { return }
                                        startRecording()
                                    }
                                    .onEnded { _ in
                                        stopAndTranscribe()
                                    }
                            )

                            if modelDownload.isReady && !transcription.isModelReady {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Warming the model…")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text(recorder.isRecording ? "Listening…" : "Tap to record")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 104)
                .padding(.vertical, 10)
                .animation(.easeInOut(duration: 0.25), value: transcription.isTranscribing)
                .animation(.easeInOut(duration: 0.25), value: isHandlingRecording)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(bottomBarBackground)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: recorder.isRecording)
    }

    private var bottomBarBackground: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 24,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 24,
            style: .continuous
        )
        return Group {
            if #available(iOS 26.0, *) {
                shape
                    .fill(.clear)
                    .glassEffect(.regular, in: shape)
            } else {
                shape
                    .fill(.ultraThinMaterial)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func startRecording() {
        guard modelDownload.isReady, !transcription.isTranscribing, !isHandlingRecording else { return }
        Task { @MainActor in
            do {
                try await recorder.start()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } catch {
                present(error)
            }
        }
    }

    private func stopAndTranscribe() {
        guard recorder.isRecording, !transcription.isTranscribing, !isHandlingRecording else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
            if result.audioDuration < Self.shortClipMaxDuration
                && result.confidence < Self.confidenceGateThreshold
            {
                try? FileManager.default.removeItem(at: url)
                toast.present("No speech detected")
                return
            }
            let text = TranscriptionValidator.cleanedText(corrections.apply(to: NumberNormalizer.normalize(SpeechPunctuation.normalize(result.text))))
            guard TranscriptionValidator.isMeaningful(text) else {
                try? FileManager.default.removeItem(at: url)
                toast.present("No speech detected")
                return
            }
            if settings.autoCopy {
                ClipboardService.copy(text)
            }
            if settings.saveToHistory {
                let item = TranscriptionItem(text: text, duration: result.audioDuration, source: "mic")
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    modelContext.insert(item)
                }
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

    private func removeJunkEntries() {
        let junk = items.filter { !TranscriptionValidator.isMeaningful($0.text) }
        guard !junk.isEmpty else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            for item in junk {
                modelContext.delete(item)
            }
        }
        do {
            try modelContext.save()
        } catch {
            present(error)
        }
    }

    private func copy(_ item: TranscriptionItem) {
        ClipboardService.copy(item.text)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        toast.present("Copied!")
    }

    private func delete(_ item: TranscriptionItem) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            modelContext.delete(item)
        }
        do {
            try modelContext.save()
        } catch {
            present(error)
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            for index in offsets {
                modelContext.delete(items[index])
            }
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
