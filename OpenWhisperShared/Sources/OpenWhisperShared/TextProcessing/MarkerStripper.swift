import Foundation

/// Removes bracketed acoustic markers that on-device STT engines occasionally
/// emit — e.g. `[NOISE]`, `[MUSIC]`, `[LAUGHTER]`, `(cough)`. Only markers from
/// a known set are removed, so arbitrary bracketed text (commands, numbers,
/// citations) always survives untouched.
public enum MarkerStripper {

    private static let knownMarkers: Set<String> = [
        "noise", "music", "laughter", "applause", "speech", "background",
        "background_noise", "blank_audio", "silence", "cough", "breath",
        "breathing", "inaudible", "unintelligible", "singing", "whisper",
        "clapping", "sound", "spk", "speaker", "music_intro",
    ]

    private static let markerPattern = try! NSRegularExpression(
        pattern: "[\\[\\(]\\s*([^\\]\\)]+?)\\s*[\\]\\)]"
    )

    public static func strip(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        let nsText = text as NSString
        let matches = markerPattern.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        var result = text
        for match in matches.reversed() {
            let inner = nsText.substring(with: match.range(at: 1))
            guard knownMarkers.contains(inner.lowercased()) else { continue }
            let fullRange = Range(match.range, in: result)!
            result.replaceSubrange(fullRange, with: "")
        }

        result = result.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
