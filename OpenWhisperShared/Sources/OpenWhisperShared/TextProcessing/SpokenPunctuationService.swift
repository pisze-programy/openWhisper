import Foundation

/// Applies spoken-punctuation rules ("comma", "question mark", …) to a raw
/// transcript, then normalizes spacing around punctuation. Serves as a fallback
/// for engines that don't emit punctuation natively; for native-punctuation
/// engines it runs in `.automatic` mode and only touches text it can improve.
@MainActor
public final class SpokenPunctuationService {
    private let rulesLoader: SpokenPunctuationRuleLoader

    public init(rulesLoader: SpokenPunctuationRuleLoader = SpokenPunctuationRuleLoader()) {
        self.rulesLoader = rulesLoader
    }

    public func normalize(
        text: String,
        language: String?,
        mode: SpokenPunctuationStrategy
    ) -> String {
        guard !text.isEmpty, let ruleSet = rulesLoader.ruleSet(for: language) else {
            return text
        }

        var result = text
        var appliedAny = false

        for rule in ruleSet.rules.sorted(by: { $0.phrase.count > $1.phrase.count }) {
            let updated = replaceWholePhrase(rule.phrase, with: rule.replacement, in: result)
            if updated != result {
                appliedAny = true
                result = updated
            }
        }

        switch mode {
        case .nativeOnly:
            return text
        case .automatic where !appliedAny:
            // The model already punctuated; don't restructure it.
            return text
        case .automatic, .fallbackOnly:
            return normalizeSpacing(in: result)
        }
    }

    private func replaceWholePhrase(_ phrase: String, with replacement: String, in text: String) -> String {
        let words = phrase.split(whereSeparator: \.isWhitespace)
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined(separator: #"\s+"#)
        guard let regex = try? NSRegularExpression(
            pattern: #"(?<![\p{L}\p{N}])\#(words)(?![\p{L}\p{N}])"#,
            options: [.caseInsensitive]
        ) else { return text }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        guard !matches.isEmpty else { return text }

        var result = text
        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: result) else { continue }
            let effective = shouldSuppressDuplicate(in: text, range: match.range, replacement: replacement)
                ? ""
                : replacement
            result.replaceSubrange(matchRange, with: effective)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Avoids "??", "..", etc. when the model already emitted the same mark.
    private func shouldSuppressDuplicate(in text: String, range: NSRange, replacement: String) -> Bool {
        guard replacement.count == 1, let replacementCharacter = replacement.first else { return false }
        let start = text.index(text.startIndex, offsetBy: range.location)
        let end = text.index(start, offsetBy: range.length)
        let before = text[text.startIndex..<start].reversed().first { !$0.isWhitespace }
        let after = text[end...].first { !$0.isWhitespace }
        return before == replacementCharacter || after == replacementCharacter
    }

    private func normalizeSpacing(in text: String) -> String {
        let opening = CharacterSet(charactersIn: "([{")
        let closing = CharacterSet(charactersIn: ")]}")
        let inline = CharacterSet(charactersIn: ",.:;?!")

        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]

            if character.isWhitespace {
                let next = index < text.endIndex ? text[index] : nil
                _ = next
                let following = followingNonWhitespace(after: index, in: text)

                if let previous = result.last, isMember(previous, of: opening) {
                    index = text.index(after: index)
                    continue
                }
                if let following, isMember(following, of: closing) || isMember(following, of: inline) {
                    index = text.index(after: index)
                    continue
                }
                if !result.isEmpty, !result.last!.isWhitespace {
                    result.append(" ")
                }
                index = text.index(after: index)
                continue
            }

            if let behavior = behavior(for: character, opening: opening, closing: closing, inline: inline) {
                if behavior == .closing || behavior == .inline {
                    while result.last == " " { result.removeLast() }
                }
                result.append(character)
                index = text.index(after: index)
                continue
            }

            result.append(character)
            index = text.index(after: index)
        }
        return result
    }

    private func followingNonWhitespace(after index: String.Index, in text: String) -> Character? {
        var current = index
        while current < text.endIndex {
            let c = text[current]
            if !c.isWhitespace { return c }
            current = text.index(after: current)
        }
        return nil
    }

    private enum TokenBehavior { case opening, closing, inline }

    private func behavior(
        for character: Character,
        opening: CharacterSet,
        closing: CharacterSet,
        inline: CharacterSet
    ) -> TokenBehavior? {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first else { return nil }
        if opening.contains(scalar) { return .opening }
        if closing.contains(scalar) { return .closing }
        if inline.contains(scalar) { return .inline }
        return nil
    }

    private func isMember(_ character: Character, of set: CharacterSet) -> Bool {
        character.unicodeScalars.allSatisfy { set.contains($0) }
    }
}
