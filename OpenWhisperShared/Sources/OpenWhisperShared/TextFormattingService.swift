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
        !storedApiKey.isEmpty
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

    private func perform(text: String, style: TranscriptionStyle) async -> String? {
        let apiKey = Self.storedApiKey
        guard !apiKey.isEmpty, !text.isEmpty else { return nil }

        let client = OpenRouterFormattingClient(apiKey: apiKey)
        do {
            let formatted = try await client.format(text: text, style: style)
            let trimmed = formatted.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            logger.error("AI formatting failed (\(error.localizedDescription, privacy: .public))")
            return nil
        }
    }

    private static var storedApiKey: String {
        let key = UserDefaults.standard.string(forKey: AppGroup.cloudApiKeyKey)
            ?? UserDefaults(suiteName: AppGroup.identifier)?.string(forKey: AppGroup.cloudApiKeyKey)
            ?? ""
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
