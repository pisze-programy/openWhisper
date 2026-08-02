import Foundation

/// Normalizes spoken number words into digits ("twenty five" → "25") across the
/// supported OpenWhisper languages. Each language implements a `NumberWordParser`;
/// `NumberWordNormalizer` tokenizes and dispatches to the best matching parser.
public enum NumberWordNormalizer {

    /// Languages with a shipped word parser.
    public static let supportedLanguageCodes: Set<String> = [
        "en", "de", "fr", "es", "nl", "pl", "it",
        "pt", "ru", "uk", "cs", "sk", "sl", "hr", "lt", "lv",
        "et", "fi", "sv", "da", "el", "ro", "bg", "mt",
        "hu",
    ]

    public static func normalize(text: String, language: String?) -> String {
        guard let code = PunctuationLanguageNormalizer.normalize(language),
              supportedLanguageCodes.contains(code),
              !text.isEmpty else { return text }

        let tokens = tokenize(text)
        guard tokens.contains(where: \.isWord) else { return text }

        guard let parser = parser(for: code) else { return text }

        var result = ""
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token.isWord,
               let parsed = Self.parseNumberSequence(startingAt: index, in: tokens, parser: parser) {
                result.append(parsed.replacement)
                index = parsed.endIndex
            } else {
                result.append(token.text)
                index += 1
            }
        }
        return result
    }

    // MARK: - Tokens

    public struct Token: Sendable {
        public let text: String
        public let kind: TokenKind

        public enum TokenKind: Sendable {
            case word
            case digit
            case other
        }

        public var isWord: Bool { kind == .word }
    }

    public static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var currentKind: Token.TokenKind?
        for character in text {
            let kind = kind(for: character)
            if kind == currentKind {
                current.append(character)
            } else {
                if let currentKind, !current.isEmpty {
                    tokens.append(Token(text: current, kind: currentKind))
                }
                current = String(character)
                currentKind = kind
            }
        }
        if let currentKind, !current.isEmpty {
            tokens.append(Token(text: current, kind: currentKind))
        }
        return tokens
    }

    private static func kind(for character: Character) -> Token.TokenKind {
        if character.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) {
            return .digit
        }
        if character.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) {
            return .word
        }
        return .other
    }

    // MARK: - Parsers

    /// A parsed number: the digit string and the index just past the last
    /// consumed token.
    public struct ParsedNumber: Sendable {
        public let replacement: String
        public let endIndex: Int
        public init(replacement: String, endIndex: Int) {
            self.replacement = replacement
            self.endIndex = endIndex
        }
    }

    /// A single language's number-word vocabulary and grammar.
    public protocol NumberWordParser: Sendable {
        var languageCode: String { get }
        /// Maps a number word (lowercased) to its small integer value (0..100).
        func smallValue(_ word: String) -> Int?
        /// Maps scale words (hundred, thousand, million) to their factor.
        func scaleValue(_ word: String) -> Int?
        /// Separators that join words into a single number ("-", " and ", spaces).
        func isConnector(_ text: String) -> Bool
        /// Extra words that should be skipped inside a number sequence ("and").
        func isParticle(_ word: String) -> Bool
        /// How words are combined: additive for German/French/English teens etc.
        func add(_ value: Int, to base: Int) -> Int
    }

    private static var registry: [String: any NumberWordParser] = [
        "en": EnglishNumberWordParser(),
        "de": GermanNumberWordParser(),
        "pl": PolishNumberWordParser(),
    ]

    static func register(_ parser: any NumberWordParser) {
        registry[parser.languageCode] = parser
    }

    static func parser(for code: String) -> (any NumberWordParser)? {
        registry[code]
    }

    /// Shared sequence-parsing used by every language parser.
    public static func parseNumberSequence(startingAt index: Int, in tokens: [Token], parser: any NumberWordParser) -> ParsedNumber? {
        let candidates = wordCandidates(startingAt: index, in: tokens, parser: parser)
        guard !candidates.isEmpty else { return nil }
        let words = candidates.map(\.word)

        guard let parsed = parseInteger(words, parser: parser), parsed.consumedWords > 0,
              parsed.consumedWords <= words.count else { return nil }

        let lastTokenIndex = candidates[parsed.consumedWords - 1].tokenIndex
        return ParsedNumber(replacement: "\(parsed.value)", endIndex: lastTokenIndex + 1)
    }

    private static func wordCandidates(
        startingAt index: Int,
        in tokens: [Token],
        parser: any NumberWordParser
    ) -> [WordCandidate] {
        var candidates: [WordCandidate] = []
        var current = index
        while current < tokens.count, tokens[current].isWord {
            candidates.append(WordCandidate(tokenIndex: current, word: tokens[current].text.lowercased()))
            let separatorIndex = current + 1
            let nextIndex = current + 2
            guard separatorIndex < tokens.count,
                  nextIndex < tokens.count,
                  tokens[nextIndex].isWord,
                  parser.isConnector(tokens[separatorIndex].text) else { break }
            current = nextIndex
        }
        return candidates
    }

    private struct WordCandidate {
        let tokenIndex: Int
        let word: String
    }

    private static func parseInteger(_ words: [String], parser: any NumberWordParser) -> (value: Int, consumedWords: Int)? {
        var index = 0
        var total = 0
        var current = 0
        var consumed = false

        if let group = parseGroup(words, startingAt: index, parser: parser) {
            current = group.value
            index = group.nextIndex
            consumed = true
        }

        while index < words.count {
            if parser.isParticle(words[index]) {
                index += 1
                continue
            }
            guard let scale = parser.scaleValue(words[index]) else { break }
            let base = current > 0 ? current : 1
            total = parser.add(base * scale, to: total)
            current = 0
            consumed = true
            index += 1

            if index < words.count, parser.isParticle(words[index]) {
                index += 1
            }
            if index < words.count,
               let group = parseGroup(words, startingAt: index, parser: parser) {
                current = group.value
                index = group.nextIndex
            }
        }

        guard consumed else { return nil }
        let final = parser.add(current, to: total)
        return (final, index)
    }

    private static func parseGroup(
        _ words: [String],
        startingAt startIndex: Int,
        parser: any NumberWordParser
    ) -> (value: Int, nextIndex: Int)? {
        var index = startIndex
        var value = 0
        var consumed = false

        if index + 1 < words.count,
           let base = parser.smallValue(words[index]),
           let hundred = parser.scaleValue(words[index + 1]), hundred == 100 {
            value = parser.add(base * 100, to: 0)
            index += 2
            consumed = true
            if index < words.count, parser.isParticle(words[index]) {
                index += 1
            }
        } else if index < words.count,
                  let hundred = parser.scaleValue(words[index]), hundred == 100 {
            value = 100
            index += 1
            consumed = true
        }

        if index < words.count, let tens = parser.smallValue(words[index]), tens >= 10 {
            value = parser.add(tens, to: value)
            index += 1
            consumed = true
            if index < words.count,
               let unit = parser.smallValue(words[index]), unit > 0, unit < 10 {
                value = parser.add(unit, to: value)
                index += 1
            }
        } else if index < words.count,
                  let small = parser.smallValue(words[index]), small > 0 {
            value = parser.add(small, to: value)
            index += 1
            consumed = true
        }

        guard consumed else { return nil }
        return (value, index)
    }
}
