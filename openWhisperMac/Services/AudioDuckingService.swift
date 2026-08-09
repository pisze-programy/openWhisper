import CoreAudio
import CoreAudioKit
import Foundation

/// Lowers or mutes the system output while recording and restores it when
/// dictation ends. Pure CoreAudio — no AppleScript, no private API. `duck(to:)`
/// sets an absolute output level (0.0 for a full mute); `isOutputPlaying` tells
/// whether anything is actually producing audio so muting can be skipped when
/// nothing is playing.
@MainActor
final class AudioDuckingService {
    static let shared = AudioDuckingService()

    private var isDucked = false
    private var savedVolume: Double = 1.0

    private init() {}

    func duck(to level: Double) {
        guard !isDucked else { return }
        guard let current = Self.readVolume() else { return }
        savedVolume = current
        Self.writeVolume(max(0, min(1, level)))
        isDucked = true
    }

    func restore() {
        guard isDucked else { return }
        Self.writeVolume(savedVolume)
        isDucked = false
    }

    /// Whether the default output device is currently running (i.e. some app is
    /// playing sound). Used to skip muting when nothing is playing.
    static func isOutputPlaying() -> Bool {
        guard let deviceID = defaultOutputDeviceID() else { return false }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &running)
        return status == noErr && running != 0
    }

    // MARK: - CoreAudio volume

    private static func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        return status == noErr ? deviceID : nil
    }

    private static func readVolume() -> Double? {
        guard let deviceID = defaultOutputDeviceID() else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var volume = Float(1.0)
        var size = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
        guard status == noErr, volume.isFinite else { return nil }
        return Double(volume)
    }

    private static func writeVolume(_ volume: Double) {
        guard let deviceID = defaultOutputDeviceID() else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = Float(max(0, min(1, volume)))
        AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float>.size), &value)
    }
}
