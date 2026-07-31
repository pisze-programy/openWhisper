import Foundation

enum TranscriptionValidator {
    static func isMeaningful(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.unicodeScalars.contains { scalar in
            CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar)
        }
    }

    static func cleanedText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = trimmed.replacingOccurrences(
            of: "\\s{2,}",
            with: " ",
            options: .regularExpression
        )
        var cleaned = collapsed
        while cleaned.last == "." {
            cleaned.removeLast()
        }
        if cleaned != collapsed,
           let last = cleaned.unicodeScalars.last,
           CharacterSet.alphanumerics.contains(last) {
            cleaned.append(".")
        }
        cleaned = cleaned
            .replacingOccurrences(of: " (?=[,;:.!?])", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return cleaned
    }
}
