import AppKit
import Foundation
import OpenWhisperShared
import SwiftData
import os

/// Orchestrates one dictation cycle: recorder → short-speech classification →
/// STT → post-processing → clipboard/insert → history. Drives the overlay state
/// and captures the frontmost app before the overlay shows.
@MainActor
final class DictationOrchestrator {
    enum Phase: Equatable {
        case idle
        case listening
        case transcribing
        case polishing
        case done
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    var onPhaseChange: (@MainActor (Phase) -> Void)?

    private let recorder: MacRecorder
    private let transcription: MacTranscriptionService
    private let pipeline: PostProcessingPipeline
    private let settings: SettingsStore
    private let clipboard: MacClipboardService
    private let insertion: TextInsertionService
    private let corrections: CorrectionsStore?
    private let ducking: AudioDuckingService
    private let sounds: FeedbackSoundService
    private let modelContext: ModelContext?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "piszeprogramy.openWhisper", category: "dictation")

    private var targetAppProcessID: pid_t?
    private var activeTask: Task<Void, Never>?

    init(
        recorder: MacRecorder,
        transcription: MacTranscriptionService,
        pipeline: PostProcessingPipeline,
        settings: SettingsStore,
        clipboard: MacClipboardService,
        insertion: TextInsertionService,
        corrections: CorrectionsStore?,
        ducking: AudioDuckingService,
        sounds: FeedbackSoundService,
        modelContext: ModelContext?
    ) {
        self.recorder = recorder
        self.transcription = transcription
        self.pipeline = pipeline
        self.settings = settings
        self.clipboard = clipboard
        self.insertion = insertion
        self.corrections = corrections
        self.ducking = ducking
        self.sounds = sounds
        self.modelContext = modelContext
    }

    // MARK: - Control

    func startRecording() {
        guard phase == .idle || phase == .done || isError(phase) else { return }

        targetAppProcessID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        StatusOverlayPanel.shared.activeAppIcon = NSWorkspace.shared.frontmostApplication?.icon

        activeTask = Task { [weak self] in
            guard let self else { return }
            self.sounds.play(.recordingStarted)
            self.ducking.duck()
            do {
                try await self.recorder.start()
                self.setPhase(.listening)
            } catch {
                self.ducking.restore()
                self.setPhase(.failed(error.localizedDescription))
            }
        }
    }

    func stopAndTranscribe() {
        guard phase == .listening else { return }
        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let samples = try await self.recorder.stop()
                try? await Task.sleep(for: .milliseconds(50))
                await self.finish(samples: samples)
            } catch {
                self.setPhase(.failed(error.localizedDescription))
            }
        }
    }

    func cancel() {
        recorder.cancel()
        ducking.restore()
        targetAppProcessID = nil
        activeTask?.cancel()
        activeTask = nil
        setPhase(.idle)
    }

    // MARK: - Pipeline

    private func finish(samples: [Float]) async {
        let duration = Double(samples.count) / 16_000.0
        let peak = Self.peakLevel(of: samples)

        do {
            try await transcription.waitForModelReady()
        } catch {
            ducking.restore()
            sounds.play(.error)
            setPhase(.failed(error.localizedDescription))
            return
        }

        guard transcription.isModelReady else {
            ducking.restore()
            sounds.play(.error)
            setPhase(.failed("The speech model is not ready."))
            return
        }

        let decision = ShortSpeechClassifier.classify(
            rawDuration: duration,
            peakLevel: peak,
            hasConfirmedText: false,
            transcribeShortQuietClipsAggressively: settings.transcribeShortQuietClipsAggressively
        )
        switch decision {
        case .discardTooShort:
            ducking.restore()
            setPhase(.failed("Too short — hold the hotkey a moment longer."))
            return
        case .discardNoSpeech:
            ducking.restore()
            setPhase(.failed("No speech detected."))
            return
        case .transcribe:
            break
        }

        setPhase(.transcribing)
        do {
            let padded = SilencePadder.pad(samples, rawDuration: duration)
            let result = try await transcription.transcribe(samples: padded)
            var text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                ducking.restore()
                setPhase(.failed("No speech detected."))
                return
            }

            if settings.formattingEnabled {
                setPhase(.polishing)
            }
            let context = PostProcessingPipeline.Context(
                languageCode: settings.languageCode,
                engineId: "fluidaudio",
                formattingStyle: settings.formattingStyle,
                formattingEnabled: settings.formattingEnabled
            )
            let processed = try await pipeline.process(
                text: text,
                context: context,
                corrections: corrections,
                llmHandler: settings.formattingEnabled
                    ? { [settings, formatting = TextFormattingService()] text in
                        await formatting.format(text: text, style: settings.formattingStyle)
                    }
                    : nil
            )
            text = processed.text.trimmingCharacters(in: .whitespacesAndNewlines)
            RecentsStore.set(text)

            if settings.autoCopy {
                clipboard.copy(text)
            }

            if settings.autoPaste {
                let outputFormat = OutputFormatResolver.resolvedFormat(
                    storedFormat: "auto",
                    bundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                )
                _ = await insertion.insertText(
                    text,
                    outputFormat: outputFormat,
                    preserveClipboard: settings.preserveClipboard
                )
            }

            if settings.saveToHistory, let ctx = modelContext {
                do {
                    let item = TranscriptionItem(text: text, duration: result.audioDuration, source: "mic")
                    ctx.insert(item)
                    try ctx.save()
                } catch {
                    logger.error("Failed to save history: \(error.localizedDescription)")
                }
            }

            ducking.restore()
            sounds.play(.transcriptionSuccess)
            setPhase(.done)
        } catch {
            ducking.restore()
            sounds.play(.error)
            setPhase(.failed(error.localizedDescription))
        }
    }

    // MARK: - Helpers

    private func setPhase(_ phase: Phase) {
        self.phase = phase
        onPhaseChange?(phase)

        switch phase {
        case .done:
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                if case .done = self?.phase { self?.setPhase(.idle) }
            }
        case .failed:
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3.0))
                if case .failed = self?.phase { self?.setPhase(.idle) }
            }
        default:
            break
        }
    }

    private func isError(_ phase: Phase) -> Bool {
        if case .failed = phase { return true }
        return false
    }

    private static func peakLevel(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Double = 0
        for sample in samples {
            sum += Double(sample) * Double(sample)
        }
        return Float(sqrt(sum / Double(samples.count)))
    }
}
