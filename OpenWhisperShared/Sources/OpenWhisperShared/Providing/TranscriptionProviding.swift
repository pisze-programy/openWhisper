import Foundation

/// Abstraction over the on-device speech-to-text backend. iOS ships
/// `parakeet-coreml-swift`; macOS ships `FluidAudio`. Neither is visible to the
/// rest of the app — everything talks to this protocol.
@MainActor
public protocol TranscriptionProviding: AnyObject {
    var isModelReady: Bool { get }
    var isWarmingUp: Bool { get }
    var isTranscribing: Bool { get }

    /// Ensures the model is resident and warm. No-op when already ready.
    func warmUp() async

    /// Transcribes raw 16 kHz mono float samples and returns the text result.
    func transcribe(samples: [Float]) async throws -> TranscriptionResult
}

/// Abstraction over the recording front end (mic capture + in-memory buffer).
@MainActor
public protocol RecorderProviding: AnyObject {
    var isRecording: Bool { get }
    var liveSamples: [Float] { get }
    var elapsed: TimeInterval { get }

    /// Starts capturing. Throws when permission is missing or capture fails.
    func start() async throws

    /// Stops capture and returns the recorded 16 kHz mono samples.
    func stop() async throws -> [Float]

    /// Discards the current recording.
    func cancel()
}

/// Abstraction over the clipboard so iOS (`UIPasteboard`) and macOS
/// (`NSPasteboard`) share one call site.
@MainActor
public protocol ClipboardProviding: AnyObject {
    func copy(_ text: String)
}

/// Abstraction over the model lifecycle (download + status). iOS and macOS ship
/// different model registries but expose the same surface.
@MainActor
public protocol ModelProviding: AnyObject {
    var status: ModelStatus { get }
    var isReady: Bool { get }

    func refreshStatus()
    func startDownload(force: Bool) async
}
