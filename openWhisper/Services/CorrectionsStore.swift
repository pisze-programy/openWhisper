import Foundation
import Observation

struct Correction: Identifiable, Codable, Equatable {
    let id: UUID
    var wrong: String
    var correct: String
    var caseSensitive: Bool = false

    init(id: UUID, wrong: String, correct: String, caseSensitive: Bool = false) {
        self.id = id
        self.wrong = wrong
        self.correct = correct
        self.caseSensitive = caseSensitive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        wrong = try container.decode(String.self, forKey: .wrong)
        correct = try container.decode(String.self, forKey: .correct)
        caseSensitive = try container.decodeIfPresent(Bool.self, forKey: .caseSensitive) ?? false
    }
}

@MainActor @Observable
final class CorrectionsStore {
    private(set) var corrections: [Correction] = []

    private let defaults = UserDefaults.standard
    private let key = "settings.corrections"

    init() {
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Correction].self, from: data) {
            corrections = decoded
        }
    }

    func add(wrong: String, correct: String, caseSensitive: Bool = false) {
        let trimmedWrong = wrong.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCorrect = correct.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWrong.isEmpty, !trimmedCorrect.isEmpty else { return }
        corrections.append(Correction(id: UUID(), wrong: trimmedWrong, correct: trimmedCorrect, caseSensitive: caseSensitive))
        persist()
    }

    func remove(_ correction: Correction) {
        corrections.removeAll { $0.id == correction.id }
        persist()
    }

    func apply(to text: String) -> String {
        var result = text
        for correction in corrections {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: correction.wrong) + "\\b"
            var options: NSRegularExpression.Options = [.useUnicodeWordBoundaries]
            if !correction.caseSensitive {
                options.insert(.caseInsensitive)
            }
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: options
            ) else { continue }
            let fullRange = NSRange(result.startIndex..., in: result)
            let template = NSRegularExpression.escapedTemplate(for: correction.correct)
            result = regex.stringByReplacingMatches(
                in: result, options: [], range: fullRange, withTemplate: template
            )
        }
        return result
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(corrections) {
            defaults.set(data, forKey: key)
        }
    }
}
