import Foundation

/// Client for OpenRouter's chat completions endpoint, used to rewrite a finished
/// transcript into the style chosen at recording time.
///
/// Endpoint: POST https://openrouter.ai/api/v1/chat/completions
/// Model:    openai/gpt-4o-mini  (fast, cheap, strong at text rewriting)
public struct OpenRouterFormattingClient: Sendable {
    public static let model = "openai/gpt-4o-mini"
    public static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    public let apiKey: String
    public let session: URLSession

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    /// Sends the raw transcript to the model with the style's instruction and
    /// returns the rewritten text. The transcript is wrapped in an input
    /// boundary so the model treats it as source text, and the response is
    /// sanitized of any scaffold the model echoes back.
    public func format(text: String, style: TranscriptionStyle) async throws -> String {
        try await perform(
            text: text,
            systemPrompt: PromptComposer.formatPrompt(style: style),
            temperature: Self.temperature(for: style)
        )
    }

    /// Reformat + translate in one request: applies `style` and additionally
    /// requires the result to be entirely in `targetLanguageCode`.
    public func format(
        text: String,
        style: TranscriptionStyle,
        sourceLanguageCode: String?,
        targetLanguageCode: String?
    ) async throws -> String {
        let options = PromptComposer.Options(
            languageCode: sourceLanguageCode,
            targetLanguageCode: targetLanguageCode
        )
        return try await perform(
            text: text,
            systemPrompt: PromptComposer.formatPrompt(style: style, options: options),
            temperature: Self.temperature(for: style)
        )
    }

    /// Translate-only call (used when the NONE style is combined with
    /// translation). Keeps the source text unchanged in wording beyond the
    /// translation itself.
    public func translate(
        text: String,
        sourceLanguageCode: String?,
        targetLanguageCode: String?
    ) async throws -> String {
        let options = PromptComposer.Options(languageCode: sourceLanguageCode)
        return try await perform(
            text: text,
            systemPrompt: PromptComposer.translatePrompt(
                sourceLanguageCode: sourceLanguageCode,
                targetLanguageCode: targetLanguageCode,
                options: options
            ),
            temperature: 0.2
        )
    }

    private func perform(
        text: String,
        systemPrompt: String,
        temperature: Double
    ) async throws -> String {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": Self.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": DictationInputBoundary.wrap(text)],
            ],
            "temperature": temperature,
            "session_id": DeviceSessionID.value,
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw FormattingError.network(message: "Failed to encode request: \(error.localizedDescription)")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw FormattingError.network(message: error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw FormattingError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = Self.extractErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
            switch http.statusCode {
            case 401, 402, 403:
                throw FormattingError.authentication(message: message)
            case 429:
                throw FormattingError.rateLimited(message: message)
            default:
                throw FormattingError.server(statusCode: http.statusCode, message: message)
            }
        }

        do {
            struct Payload: Decodable {
                struct Choice: Decodable {
                    struct Message: Decodable { let content: String }
                    let message: Message
                }
                let choices: [Choice]
            }
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            guard let raw = payload.choices.first?.message.content else {
                throw FormattingError.emptyResult
            }
            let result = DictationInputBoundary.sanitize(raw, originalText: text)
            guard !result.isEmpty else { throw FormattingError.emptyResult }
            return result
        } catch let error as FormattingError {
            throw error
        } catch {
            throw FormattingError.invalidResponse
        }
    }

    /// Sampling temperature per style. Kept deterministic for structured
    /// rewrites; a touch of variety for expressive styles.
    private static func temperature(for style: TranscriptionStyle) -> Double {
        switch style {
        case .none: return 0.2
        case .formal: return 0.2
        case .casual: return 0.3
        case .veryCasual: return 0.4
        case .excited: return 0.4
        }
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        struct ErrorPayload: Decodable {
            struct Body: Decodable { let message: String? }
            let error: Body?
        }
        guard
            let payload = try? JSONDecoder().decode(ErrorPayload.self, from: data),
            let message = payload.error?.message,
            !message.isEmpty
        else { return nil }
        return message
    }
}

public enum FormattingError: LocalizedError, Sendable {
    case authentication(message: String)
    case rateLimited(message: String)
    case server(statusCode: Int, message: String)
    case invalidResponse
    case network(message: String)
    case emptyResult

    public var errorDescription: String? {
        switch self {
        case .authentication(let message):
            return "OpenRouter rejected the API key: \(message)"
        case .rateLimited(let message):
            return "Rate limited by OpenRouter: \(message)"
        case .server(let statusCode, let message):
            return "OpenRouter error (\(statusCode)): \(message)"
        case .invalidResponse:
            return "The formatting service returned an invalid response."
        case .network(let message):
            return "Network error: \(message)"
        case .emptyResult:
            return "The model returned empty text."
        }
    }
}
