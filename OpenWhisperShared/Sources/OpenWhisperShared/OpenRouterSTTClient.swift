import Foundation

/// Client for OpenRouter's speech-to-text endpoint.
///
/// Endpoint: POST https://openrouter.ai/api/v1/audio/transcriptions
/// Model:    nvidia/parakeet-tdt-0.6b-v3  (audio -> transcription)
public struct OpenRouterSTTClient: Sendable {
    public static let model = "nvidia/parakeet-tdt-0.6b-v3"
    public static let endpoint = URL(string: "https://openrouter.ai/api/v1/audio/transcriptions")!

    public let apiKey: String
    public let language: String?   // ISO-639-1, optional; omit for auto-detection
    public let httpReferer: String?
    public let appTitle: String?
    public let session: URLSession

    public init(
        apiKey: String,
        language: String? = nil,
        httpReferer: String? = nil,
        appTitle: String? = nil,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.language = language
        self.httpReferer = httpReferer
        self.appTitle = appTitle
        self.session = session
    }

    /// Transcribes a 16 kHz mono WAV file and returns the text.
    public func transcribe(wavData: Data) async throws -> String {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let httpReferer {
            request.setValue(httpReferer, forHTTPHeaderField: "HTTP-Referer")
        }
        if let appTitle {
            request.setValue(appTitle, forHTTPHeaderField: "X-OpenRouter-Title")
        }
        // Provider processing timeout is ~60 s; give the request headroom.
        request.timeoutInterval = 65

        var body: [String: Any] = [
            "model": Self.model,
            "input_audio": [
                "data": wavData.base64EncodedString(),
                "format": "wav",
            ],
            "session_id": DeviceSessionID.value,
        ]
        if let language {
            body["language"] = language
        }
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw OpenRouterError.network(message: "Failed to encode request: \(error.localizedDescription)")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OpenRouterError.network(message: error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = Self.extractErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
            switch http.statusCode {
            case 400:
                throw OpenRouterError.badRequest(message: message)
            case 401, 402, 403:
                throw OpenRouterError.authentication(message: message)
            case 429:
                throw OpenRouterError.rateLimited(message: message)
            default:
                throw OpenRouterError.server(statusCode: http.statusCode, message: message)
            }
        }

        do {
            struct Payload: Decodable {
                let text: String
            }
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            let text = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw OpenRouterError.emptyTranscription }
            return text
        } catch let error as OpenRouterError {
            throw error
        } catch {
            throw OpenRouterError.invalidResponse
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

public enum OpenRouterError: LocalizedError, Sendable {
    case badRequest(message: String)
    case authentication(message: String)
    case rateLimited(message: String)
    case server(statusCode: Int, message: String)
    case invalidResponse
    case network(message: String)
    case emptyTranscription

    public var errorDescription: String? {
        switch self {
        case .badRequest(let message):
            return "Bad request: \(message)"
        case .authentication(let message):
            return "OpenRouter rejected the API key: \(message)"
        case .rateLimited(let message):
            return "Rate limited by OpenRouter: \(message)"
        case .server(let statusCode, let message):
            return "OpenRouter error (\(statusCode)): \(message)"
        case .invalidResponse:
            return "The transcription service returned an invalid response."
        case .network(let message):
            return "Network error: \(message)"
        case .emptyTranscription:
            return "No speech detected."
        }
    }
}
