import Foundation
import OpenWhisperShared

/// Client for OpenRouter's chat completions endpoint, used to rewrite a finished
/// transcript into the style chosen at recording time.
///
/// Endpoint: POST https://openrouter.ai/api/v1/chat/completions
/// Model:    openai/gpt-4o-mini  (fast, cheap, strong at text rewriting)
struct OpenRouterFormattingClient: Sendable {
    static let model = "openai/gpt-4o-mini"
    static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    let apiKey: String
    let session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    /// Sends the raw transcript to the model with the style's instruction and
    /// returns the rewritten text.
    func format(text: String, style: TranscriptionStyle) async throws -> String {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": Self.model,
            "messages": [
                ["role": "system", "content": Self.systemPrompt(style: style)],
                ["role": "user", "content": text],
            ],
            "temperature": 0.3,
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
            let result = payload.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let result, !result.isEmpty else { throw FormattingError.emptyResult }
            return result
        } catch let error as FormattingError {
            throw error
        } catch {
            throw FormattingError.invalidResponse
        }
    }

    /// A simple, task-specific instruction. The style's own instruction is
    /// appended so every call is tailored to the selected style.
    private static func systemPrompt(style: TranscriptionStyle) -> String {
        """
        You rewrite voice-to-text transcripts into clean, readable text. Follow the \
        requested style. Fix obvious transcription errors using context, improve wording \
        and flow, and structure the text into sentences and paragraphs. Never invent, add, \
        remove, or change facts, names, numbers, or meaning. If the transcript is too \
        garbled to understand, only fix punctuation and capitalization and return it \
        otherwise unchanged. Output ONLY the finished text, no quotes, no commentary.

        Style: \(FormattingPrompts.instruction(for: style))
        """
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

enum FormattingError: LocalizedError, Sendable {
    case authentication(message: String)
    case rateLimited(message: String)
    case server(statusCode: Int, message: String)
    case invalidResponse
    case network(message: String)
    case emptyResult

    var errorDescription: String? {
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
