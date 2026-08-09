import Foundation

/// Pauses the currently playing media (Music, Spotify, YouTube in a browser —
/// anything shown in "Now Playing") and resumes it at the same position.
///
/// On the public DMG build it uses the private MediaRemote framework, loaded at
/// runtime via `dlsym` (nothing is linked against it). Pause is only sent once
/// we confirm something is actually playing, and Play is sent only if we paused
/// — media that was already paused is never started.
///
/// On App Store builds the MediaRemote code is excluded entirely (`#if
/// !APP_STORE`); the type stays as a no-op so the rest of the app has a single
/// code path, and media handling there falls back to output muting.
@MainActor
final class MediaPlaybackPauser {
    static let shared = MediaPlaybackPauser()

#if !APP_STORE
    private let mediaQueue = DispatchQueue(label: "openwhisper.media", qos: .userInitiated)
    private var sendCommand: (@convention(c) (Int, AnyObject?) -> Void)?
    private var getIsPlaying: (@convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void)?
    private var sessionActive = false
    private var didPause = false
#endif

    private init() {
#if !APP_STORE
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW) else {
            return
        }
        if let symbol = dlsym(handle, "MRMediaRemoteSendCommand") {
            sendCommand = unsafeBitCast(symbol, to: (@convention(c) (Int, AnyObject?) -> Void)?.self)
        }
        if let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") {
            getIsPlaying = unsafeBitCast(
                symbol,
                to: (@convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void)?.self
            )
        }
#endif
    }

#if !APP_STORE
    /// Called when a dictation session starts: pause whatever is playing.
    func startSession() {
        guard !sessionActive, let getIsPlaying else { return }
        sessionActive = true
        didPause = false
        getIsPlaying(mediaQueue) { [weak self] isPlaying in
            DispatchQueue.main.async {
                guard let self, self.sessionActive, isPlaying, let send = self.sendCommand else { return }
                send(1, nil) // kMRMediaRemoteCommandPause
                self.didPause = true
            }
        }
    }

    /// Called when the dictation session ends: resume only if we paused it.
    func endSession() {
        guard sessionActive else { return }
        sessionActive = false
        if didPause, let send = sendCommand {
            send(0, nil) // kMRMediaRemoteCommandPlay
        }
        didPause = false
    }
#else
    func startSession() {}
    func endSession() {}
#endif
}
