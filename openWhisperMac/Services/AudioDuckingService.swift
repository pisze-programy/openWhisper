import CoreAudio
import CoreAudioKit
import Foundation

/// Lowers the system output volume while recording so the user can hear
/// themselves think, and restores it when dictation ends. Pure CoreAudio —
/// no AppleScript, no private API. Default duck level 0.2 (20% of current).
@MainActor
final class AudioDuckingService {
    static let shared = AudioDuckingService()

    var duckLevel: Double = 0.2

    private var isDucked = false
    private var savedVolume: Double = 1.0

    private init() {}

    func duck() {
        guard !isDucked else { return }
        guard let current = Self.readVolume() else { return }
        savedVolume = current
        Self.writeVolume(current * max(0, min(1, duckLevel)))
        isDucked = true
    }

    func restore() {
        guard isDucked else { return }
        Self.writeVolume(savedVolume)
        isDucked = false
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
