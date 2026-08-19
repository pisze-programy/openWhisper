import Foundation
import os

/// Formats finished transcripts with a fast LLM in the style selected at
/// recording time. Reads the OpenRouter API key from the shared App Group
/// (the same key the keyboard uses). Returns the original text unchanged when
/// formatting is disabled, the key is missing, or the request fails.
@MainActor @Observable
public final class TextFormattingService {
    public private(set) var isFormatting = false

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "piszeprogramy.openWhisper",
        category: "formatting"
    )

    public init() {}

    /// Whether an OpenRouter API key is configured. UI uses this to warn that a
    /// non-NONE style cannot be applied without a key.
    public static var hasApiKey: Bool {
        OpenRouterApiKeyStore.hasValue
    }

    /// Rewrites `text` in `style`. Never throws — on any failure it returns the
    /// original text so the note is still saved.
    public func format(text: String, style: TranscriptionStyle) async -> String {
        isFormatting = true
        defer { isFormatting = false }
        return await perform(text: text, style: style) ?? text
    }

    /// Rewrites an existing note. Returns nil when the key is missing or the
    /// request fails so the caller keeps the original note.
    public func reformat(text: String, style: TranscriptionStyle) async -> String? {
        await perform(text: text, style: style)
    }

    /// Rewrites an existing note in `style` AND translates it into
    /// `targetLanguageCode`, in a single request. Returns nil on failure so the
    /// caller keeps the original text.
    public func reformatAndTranslate(
        text: String,
        style: TranscriptionStyle,
        sourceLanguageCode: String?,
        targetLanguageCode: String?
    ) async -> String? {
        let apiKey = OpenRouterApiKeyStore.value
        guard !apiKey.isEmpty, !text.isEmpty else { return nil }
        let client = OpenRouterFormattingClient(apiKey: apiKey)
        let began = Date()
        do {
            let formatted = try await client.format(
                text: text,
                style: style,
                sourceLanguageCode: sourceLanguageCode,
                targetLanguageCode: targetLanguageCode
            )
            let trimmed = formatted.trimmingCharacters(in: .whitespacesAndNewlines)
            report(
                .formatAndTranslate,
                ok: !trimmed.isEmpty,
                latency: began,
                chars: text.count,
                style: style,
                source: sourceLanguageCode,
                target: targetLanguageCode
            )
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            report(.formatAndTranslate, ok: false, latency: began, chars: text.count, style: style, source: sourceLanguageCode, target: targetLanguageCode)
            logger.error("AI formatting+translation failed (\(error.localizedDescription, privacy: .public))")
            return nil
        }
    }

    /// Translates an existing note without any style rewriting (used when the
    /// selected style is NONE). Returns nil on failure so the caller keeps the
    /// original text.
    public func translateOnly(
        text: String,
        sourceLanguageCode: String?,
        targetLanguageCode: String?
    ) async -> String? {
        let apiKey = OpenRouterApiKeyStore.value
        guard !apiKey.isEmpty, !text.isEmpty else { return nil }
        let client = OpenRouterFormattingClient(apiKey: apiKey)
        let began = Date()
        do {
            let translated = try await client.translate(
                text: text,
                sourceLanguageCode: sourceLanguageCode,
                targetLanguageCode: targetLanguageCode
            )
            let trimmed = translated.trimmingCharacters(in: .whitespacesAndNewlines)
            report(
                .translateOnly,
                ok: !trimmed.isEmpty,
                latency: began,
                chars: text.count,
                style: .none,
                source: sourceLanguageCode,
                target: targetLanguageCode
            )
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            report(.translateOnly, ok: false, latency: began, chars: text.count, style: .none, source: sourceLanguageCode, target: targetLanguageCode)
            logger.error("AI translation failed (\(error.localizedDescription, privacy: .public))")
            return nil
        }
    }

    private func perform(text: String, style: TranscriptionStyle) async -> String? {
        let apiKey = OpenRouterApiKeyStore.value
        guard !apiKey.isEmpty, !text.isEmpty else { return nil }

        let client = OpenRouterFormattingClient(apiKey: apiKey)
        let began = Date()
        do {
            let formatted = try await client.format(text: text, style: style)
            let trimmed = formatted.trimmingCharacters(in: .whitespacesAndNewlines)
            report(.format, ok: !trimmed.isEmpty, latency: began, chars: text.count, style: style, source: nil, target: nil)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            report(.format, ok: false, latency: began, chars: text.count, style: style, source: nil, target: nil)
            logger.error("AI formatting failed (\(error.localizedDescription, privacy: .public))")
            return nil
        }
    }

    private func report(
        _ feature: UsageAnalytics.Feature,
        ok: Bool,
        latency began: Date,
        chars: Int,
        style: TranscriptionStyle,
        source: String?,
        target: String?
    ) {
        let latencyMs = Int(max(0, Date().timeIntervalSince(began)) * 1000)
        UsageAnalytics.track(UsageAnalytics.Event(
            feature: feature,
            ok: ok,
            latencyMs: latencyMs,
            chars: chars,
            style: style.rawValue,
            sourceLanguage: source,
            targetLanguage: target
        ))
    }
}
