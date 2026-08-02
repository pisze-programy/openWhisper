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
    @Environment(SettingsRouter.self) private var settingsRouter
    @Environment(TextFormattingService.self) private var formatting

    @Query(sort: \TranscriptionItem.createdAt, order: .reverse)
    private var items: [TranscriptionItem]

    @State private var showDeleteConfirm = false
    @State private var itemPendingDelete: TranscriptionItem?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isHandlingRecording = false
    @State private var showSettings = false
    @State private var reformattingItemID: UUID?

    private static let shortClipMaxDuration: TimeInterval = 1.0
    private static let confidenceGateThreshold: Float = 0.55

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    FirstNoteEmptyState(onStartRecording: { startRecording() })
                } else {
                    timeline
                }
            }
            .safeAreaInset(edge: .bottom) {
                recordSection
            }
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
            .onChange(of: settingsRouter.pendingSection) { _, section in
                guard section != nil else { return }
                showSettings = true
            }
            .onAppear {

                if settingsRouter.pendingSection != nil {
                    showSettings = true
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("OpenWhisper")
                        .font(.subheadline.weight(.semibold))
                }
                ToolbarItem(placement: .topBarTrailing) {

                    Button {
                        showSettings = true
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

    private var timeline: some View {
        ScrollView {
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(AppTheme.secondaryLabel.opacity(0.25))
                    .frame(width: 1)
                    .padding(.leading, 14.5)

                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sections, id: \.day) { section in
                        dayHeader(section.day)
                        ForEach(section.items) { item in
                            HistoryRow(
                                item: item,
                                onCopy: { copy(item) },
                                onDelete: {
                                    itemPendingDelete = item
                                    showDeleteConfirm = true
                                },
                                onReformat: settings.formattingEnabled ? { reformat(item) } : nil,
                                isReformatting: reformattingItemID == item.id
                            )
                        }
                    }
                }
                .padding(.trailing, 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private typealias HistorySection = (day: Date, items: [TranscriptionItem])

    private var sections: [HistorySection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: items) {
            calendar.startOfDay(for: $0.createdAt)
        }
        return grouped
            .map { (day: $0.key, items: $0.value) }
            .sorted { $0.day > $1.day }
    }

    private func dayHeader(_ day: Date) -> some View {
        ZStack(alignment: .leading) {
            Text(day, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.leading, 32)
                .padding(.top, 14)
                .padding(.bottom, 6)

            TimelineDot(style: .header)
                .padding(.leading, 10.5)
        }
    }

    private var waveformContainer: some View {
        LiveWaveform(getSamples: { recorder.liveSamples })
            .frame(maxWidth: .infinity)
            .frame(height: recorder.isRecording ? 52 : 0, alignment: .center)
            .clipped()
    }

    private var stylePicker: some View {
        Menu {
            ForEach(TranscriptionStyle.allCases) { style in
                Button {
                    settings.formattingStyle = style
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: style.systemImage)
                            .frame(width: 18)
                        Text(style.title)
                        Spacer()
                    }
                    .foregroundStyle(.primary)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .background(
                        style == settings.formattingStyle
                            ? Color(.systemGray4).opacity(0.6)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: settings.formattingStyle.systemImage)
                    .font(.caption)
                Text(settings.formattingStyle.title)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Formatting style")
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

            if settings.formattingEnabled {
                stylePicker
            }

            ZStack {
                if transcription.isTranscribing || isHandlingRecording || formatting.isFormatting {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(formatting.isFormatting ? "Polishing…" : "Transcribing…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    } else {
                        VStack(spacing: 12) {
                            MicRecordButton(isRecording: recorder.isRecording, size: 72) {

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
        Task { @MainActor in
            do {
                // Keep the mic capturing for ~1s after release so the end of the
                // user's speech isn't cut off; then finalise and transcribe.
                let url = try await recorder.stopAfterTail(1.0)
                await transcribe(url: url)
                isHandlingRecording = false
            } catch {
                isHandlingRecording = false
                present(error)
            }
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
            let finalText = await applyFormatting(to: text)
            if settings.autoCopy {
                ClipboardService.copy(finalText)
            }
            if settings.saveToHistory {
                let item = TranscriptionItem(text: finalText, duration: result.audioDuration, source: "mic")
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    modelContext.insert(item)
                }
                do {
                    try modelContext.save()
                } catch {
                    present(error)
                }
            }
        } catch TranscriptionError.noAudio {

            try? FileManager.default.removeItem(at: url)
            toast.present("No speech detected")
        } catch {
            present(error)
        }
        try? FileManager.default.removeItem(at: url)
    }

    private func applyFormatting(to text: String) async -> String {
        guard settings.formattingEnabled else { return text }
        return await formatting.format(text: text, style: settings.formattingStyle)
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

    private func reformat(_ item: TranscriptionItem) {
        guard settings.formattingEnabled, reformattingItemID == nil else { return }
        reformattingItemID = item.id
        Task { @MainActor in
            defer { reformattingItemID = nil }
            guard let rewritten = await formatting.reformat(text: item.text, style: settings.formattingStyle) else {
                toast.present("Couldn't rewrite the note")
                return
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                item.text = rewritten
            }
            do {
                try modelContext.save()
            } catch {
                present(error)
            }
        }
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

    private func present(_ error: Error) {

        if Self.shouldPresentAsToast(error) {
            toast.present(error.localizedDescription)
            return
        }
        errorMessage = error.localizedDescription
        showError = true
    }

    private static func shouldPresentAsToast(_ error: Error) -> Bool {
        if let recorderError = error as? RecorderError {
            switch recorderError {
            case .alreadyRecording, .noRecording, .formatUnavailable:
                return true
            case .permissionDenied:
                return false
            }
        }
        if let transcriptionError = error as? TranscriptionError {
            switch transcriptionError {
            case .busy, .noAudio:
                return true
            case .modelUnavailable, .failed:
                return false
            }
        }
        return false
    }
}
