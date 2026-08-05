import AppKit
import Foundation
import OpenWhisperShared
import os

/// Processes the text the user copied to the clipboard with the same
/// post-processing pipeline dictation uses: local cleanup + optional AI
/// formatting and/or translation. The result is pasted into the focused
/// editable field (replacing a selection, or inserting at the caret) or left on
/// the clipboard when there is no editable field. Driven by the left-side
/// hotkeys.
@MainActor
final class ReformatOrchestrator {
    private(set) var isRunning = false

    private let settings: SettingsStore
    private let pipeline: PostProcessingPipeline
    private let insertion: TextInsertionService
    private let clipboard: MacClipboardService
    private let corrections: CorrectionsStore
    private let sounds: FeedbackSoundService
    private let formatting = TextFormattingService()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "piszeprogramy.openWhisper",
        category: "reformat"
    )

    private var activeTask: Task<Void, Never>?
    private var targetApp: NSRunningApplication?

    init(
        settings: SettingsStore,
        pipeline: PostProcessingPipeline,
        insertion: TextInsertionService,
        clipboard: MacClipboardService,
        corrections: CorrectionsStore,
        sounds: FeedbackSoundService
    ) {
        self.settings = settings
        self.pipeline = pipeline
        self.insertion = insertion
        self.clipboard = clipboard
        self.corrections = corrections
        self.sounds = sounds
    }

    private enum ReformatError: LocalizedError {
        case llmFailed

        var errorDescription: String? {
            "The AI formatting/translation request failed. Check your OpenRouter key and network connection."
        }
    }

    // MARK: - Control

    func run() {
        guard !isRunning else { return }
        guard insertion.isAccessibilityGranted else {
            insertion.requestAccessibilityPermission()
            StatusOverlayPanel.shared.showMessage(title: "Allow Accessibility", icon: .warning, tint: .orange)
            return
        }

        let translateActive = settings.isTranslationActive
        let needsAPI = translateActive || settings.formattingStyle != .none
        if needsAPI, !TextFormattingService.hasApiKey {
            StatusOverlayPanel.shared.showMessage(
                title: "Go to Settings",
                detail: "Add your OpenRouter API key to translate.",
                icon: .error,
                tint: .red
            )
            return
        }

        targetApp = NSWorkspace.shared.frontmostApplication
        let source = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !source.isEmpty else {
            StatusOverlayPanel.shared.showMessage(title: "No text on clipboard")
            return
        }

        isRunning = true
        StatusOverlayPanel.shared.show(
            phase: .polishing,
            title: translateActive ? "Translating…" : "Reformatting…"
        )

        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let processed = try await self.process(text: source, translateActive: translateActive)
                let trimmed = processed.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    self.showFailure("The result was empty.")
                    return
                }
                self.deliver(trimmed)
            } catch {
                self.showFailure(error.localizedDescription)
            }
        }
    }

    /// Cancels an in-flight reformat. Called when dictation starts so the two
    /// operations never run at the same time.
    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        isRunning = false
        StatusOverlayPanel.shared.hide()
    }

    // MARK: - Pipeline

    private func process(text: String, translateActive: Bool) async throws -> String {
        let style = settings.formattingStyle
        let sourceCode = settings.translateSourceCode
        let targetCode = settings.translateTargetCode

        let useLLM = translateActive || style != .none
        let context = PostProcessingPipeline.Context(
            languageCode: translateActive ? sourceCode : settings.languageCode,
            engineId: "fluidaudio",
            formattingStyle: style,
            formattingEnabled: useLLM
        )

        let llmHandler: ((String) async throws -> String)?
        if useLLM {
            llmHandler = { [formatting] input in
                if translateActive {
                    if style == .none {
                        guard let result = await formatting.translateOnly(
                            text: input,
                            sourceLanguageCode: sourceCode,
                            targetLanguageCode: targetCode
                        ) else { throw ReformatError.llmFailed }
                        return result
                    }
                    guard let result = await formatting.reformatAndTranslate(
                        text: input,
                        style: style,
                        sourceLanguageCode: sourceCode,
                        targetLanguageCode: targetCode
                    ) else { throw ReformatError.llmFailed }
                    return result
                }
                guard let result = await formatting.reformat(text: input, style: style) else {
                    throw ReformatError.llmFailed
                }
                return result
            }
        } else {
            llmHandler = nil
        }

        let result = try await pipeline.process(
            text: text,
            context: context,
            corrections: corrections,
            llmHandler: llmHandler
        )
        return result.text
    }

    // MARK: - Delivery

    private func deliver(_ text: String) {
        RecentsStore.shared.set(text)
        sounds.play(.transcriptionSuccess)

        // Always paste when there is an editable field under focus (a selection
        // gets replaced, otherwise the text is inserted at the caret). When the
        // frontmost app has no editable field (e.g. a web page), leave the
        // result on the clipboard.
        if insertion.canPasteToActiveField() {
            // Put the window the user started from back on top before pasting so
            // the result lands where the hotkey was pressed, not where the focus
            // wandered while the request was in flight.
            targetApp?.activate(options: [.activateIgnoringOtherApps])
            let outputFormat = OutputFormatResolver.resolvedFormat(
                storedFormat: "auto",
                bundleIdentifier: targetApp?.bundleIdentifier
            )
            Task { [weak self] in
                guard let self else { return }
                await self.insertion.insertText(
                    text,
                    outputFormat: outputFormat,
                    preserveClipboard: self.settings.preserveClipboard
                )
                StatusOverlayPanel.shared.showMessage(title: "Copied", icon: .check, tint: .green)
                self.isRunning = false
            }
            return
        }

        clipboard.copy(text)
        StatusOverlayPanel.shared.showMessage(title: "Copied", icon: .check, tint: .green)
        isRunning = false
    }

    private func showFailure(_ detail: String) {
        logger.error("Reformat failed: \(detail, privacy: .public)")
        StatusOverlayPanel.shared.showMessage(title: "Failed", icon: .warning, tint: .orange)
        isRunning = false
    }
}
