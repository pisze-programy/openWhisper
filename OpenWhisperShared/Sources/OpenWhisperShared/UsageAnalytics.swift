import Foundation

/// Fire-and-forget anonymous usage analytics. Sends counters only — never
/// transcript text. Payload: install ID, feature, language(s), style, outcome,
/// latency and character count. Gated by the user's `usageAnalyticsEnabled`
/// setting and best-effort: network errors are ignored silently.
public enum UsageAnalytics {
    public enum Feature: String, Encodable, Sendable {
        case format
        case formatAndTranslate
        case translateOnly
    }

    public struct Event: Encodable, Sendable {
        public let feature: Feature
        public let ok: Bool
        public let latencyMs: Int
        public let chars: Int
        public let style: String?
        public let sourceLanguage: String?
        public let targetLanguage: String?

        public init(
            feature: Feature,
            ok: Bool,
            latencyMs: Int,
            chars: Int,
            style: String? = nil,
            sourceLanguage: String? = nil,
            targetLanguage: String? = nil
        ) {
            self.feature = feature
            self.ok = ok
            self.latencyMs = latencyMs
            self.chars = chars
            self.style = style
            self.sourceLanguage = sourceLanguage
            self.targetLanguage = targetLanguage
        }
    }

    private struct Payload: Encodable, Sendable {
        let app: String
        let installId: String
        let ts: Date
        let events: [Event]
    }

    /// The analytics endpoint. Point this at the deployed Worker (see
    /// `server/README.md`). Kept as a constant so the binary contains no
    /// configurable secrets.
    public static var endpoint = URL(string: "https://openwhisper-usage.pisze-programy.workers.dev/v1/track")!

    /// Whether the user opted into anonymous usage analytics (Settings toggle).
    public static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: AppGroup.usageAnalyticsEnabledKey) as? Bool
            ?? true
    }

    /// Fire-and-forget telemetry request. Errors are dropped deliberately —
    /// dictation must never be blocked (or retried) because of analytics.
    private static func send(_ request: URLRequest) {
        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }

    public static func track(_ event: Event) {
        track([event])
    }

    public static func track(_ events: [Event]) {
        guard isEnabled, !events.isEmpty else { return }
        let payload = Payload(
            app: "openwhisper-macos",
            installId: InstallID.value,
            ts: Date(),
            events: events
        )
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 8
        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            return
        }
        send(request)
    }

    /// Measures `work` and reports the result. Kept simple on purpose — the
    /// `ok`/latency/chars counters are captured here so callers just wrap.
    public static func trackResult<T>(
        feature: Feature,
        style: String? = nil,
        sourceLanguage: String? = nil,
        targetLanguage: String? = nil,
        result: T?,
        chars: Int = 0,
        latencyMs: Int
    ) {
        track(Event(
            feature: feature,
            ok: result != nil,
            latencyMs: latencyMs,
            chars: chars,
            style: style,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage
        ))
    }
}
