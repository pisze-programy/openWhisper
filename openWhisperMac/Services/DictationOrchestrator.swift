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
    private let mediaPlayback: MediaPlaybackPauser
    private let sounds: FeedbackSoundService
    private let modelContext: ModelContext?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "dictation")

    private var targetAppProcessID: pid_t?
    private var activeTask: Task<Void, Never>?
    /// Formatting style captured when recording started. A style change while
    /// this recording is in flight must not affect it — the current transcript
    /// keeps the style it had at the start; the next recording uses the new one.
    private var recordingStyle: TranscriptionStyle?
    /// Translation target captured when recording started, same snapshot
    /// principle as `recordingStyle`.
    private var recordingTranslationTarget: String?

    init(
        recorder: MacRecorder,
        transcription: MacTranscriptionService,
        pipeline: PostProcessingPipeline,
        settings: SettingsStore,
        clipboard: MacClipboardService,
        insertion: TextInsertionService,
        corrections: CorrectionsStore?,
        ducking: AudioDuckingService,
        mediaPlayback: MediaPlaybackPauser,
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
        self.mediaPlayback = mediaPlayback
        self.sounds = sounds
        self.modelContext = modelContext
    }

    // MARK: - Control

    func startRecording() {
        guard phase == .idle || phase == .done || isError(phase) else { return }

        targetAppProcessID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        StatusOverlayPanel.shared.activeAppIcon = NSWorkspace.shared.frontmostApplication?.icon
        recordingStyle = settings.formattingStyle
        recordingTranslationTarget = settings.translationTargetCode

        activeTask = Task { [weak self] in
            guard let self else { return }
            self.sounds.play(.recordingStarted)
            self.beginAudioSuppression()
            do {
                try await self.recorder.start()
                self.setPhase(.listening)
            } catch {
                self.endAudioSuppression()
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
        endAudioSuppression()
        targetAppProcessID = nil
        recordingStyle = nil
        recordingTranslationTarget = nil
        activeTask?.cancel()
        activeTask = nil
        setPhase(.idle)
    }

    // MARK: - Pipeline

    private func finish(samples: [Float]) async {
        let duration = Double(samples.count) / 16_000.0
        let peak = Self.peakLevel(of: samples)
        let style = recordingStyle ?? settings.formattingStyle
        let translationTarget = recordingTranslationTarget
        recordingStyle = nil
        recordingTranslationTarget = nil

        do {
            try await transcription.waitForModelReady()
        } catch {
            endAudioSuppression()
            sounds.play(.error)
            setPhase(.failed(error.localizedDescription))
            return
        }

        guard transcription.isModelReady else {
            endAudioSuppression()
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
            endAudioSuppression()
            setPhase(.failed("Too short — hold the hotkey a moment longer."))
            return
        case .discardNoSpeech:
            endAudioSuppression()
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
                endAudioSuppression()
                setPhase(.failed("No speech detected."))
                return
            }

            let sourceCode = settings.languageCode
            // Translating into the STT's own language is a no-op (the model
            // would just echo the text back) — treat it as NONE to skip the call.
            let translationActive = translationTarget != nil && translationTarget != sourceCode
            let useLLM = style != .none || translationActive
            if useLLM {
                setPhase(.polishing)
            }
            let context = PostProcessingPipeline.Context(
                languageCode: sourceCode,
                engineId: "fluidaudio",
                formattingStyle: style,
                formattingEnabled: useLLM
            )
            let processed = try await pipeline.process(
                text: text,
                context: context,
                corrections: corrections,
                llmHandler: useLLM
                    ? { [style, translationTarget, sourceCode, formatting = TextFormattingService()] input in
                        if let target = translationTarget, target != sourceCode {
                            if style == .none {
                                guard let result = await formatting.translateOnly(
                                    text: input,
                                    sourceLanguageCode: sourceCode,
                                    targetLanguageCode: target
                                ) else { return input }
                                return result
                            }
                            // Single combined request: rewrite in `style` and
                            // require the entire output in the target language.
                            guard let result = await formatting.reformatAndTranslate(
                                text: input,
                                style: style,
                                sourceLanguageCode: sourceCode,
                                targetLanguageCode: target
                            ) else { return input }
                            return result
                        }
                        return await formatting.format(text: input, style: style)
                    }
                    : nil
            )
            text = processed.text.trimmingCharacters(in: .whitespacesAndNewlines)
            RecentsStore.shared.set(text)

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

            endAudioSuppression()
            sounds.play(.transcriptionSuccess)
            setPhase(.done)
        } catch {
            endAudioSuppression()
            sounds.play(.error)
            setPhase(.failed(error.localizedDescription))
        }
    }

    // MARK: - Helpers

    /// The media mode actually applied in this build. App Store builds never
    /// pause — pausing relies on a private framework Apple disallows there, so
    /// it degrades to muting.
    private var effectiveMediaMode: MediaHandlingMode {
#if APP_STORE
        .mute
#else
        settings.mediaHandlingMode
#endif
    }

    /// Quiets the audio environment for a recording session: pause whatever is
    /// playing, or mute the output to zero when nothing can be paused.
    private func beginAudioSuppression() {
        guard settings.mediaHandlingEnabled else { return }
        switch effectiveMediaMode {
        case .mute:
            if AudioDuckingService.isOutputPlaying() {
                ducking.duck(to: 0)
            }
        case .pause:
            mediaPlayback.startSession()
        }
    }

    /// Restores the audio environment after the session. Both services are
    /// idempotent (a no-op unless they actually changed something), so this is
    /// safe to call unconditionally — even if the setting changed mid-recording.
    private func endAudioSuppression() {
        ducking.restore()
        mediaPlayback.endSession()
    }

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
