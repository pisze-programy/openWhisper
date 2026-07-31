import Foundation

enum NumberNormalizer {
    private static let unitValues: [String: Int] = [
        "zero": 0,
        "one": 1, "two": 2, "three": 3, "four": 4,
        "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "jeden": 1, "jedna": 1, "jedno": 1,
        "dwa": 2, "dwie": 2,
        "trzy": 3,
        "cztery": 4,
        "pięć": 5,
        "sześć": 6,
        "siedem": 7,
        "osiem": 8,
        "dziewięć": 9,
    ]

    private static let teenValues: [String: Int] = [
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
        "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
        "dziesięć": 10, "jedenaście": 11, "dwanaście": 12, "trzynaście": 13, "czternaście": 14,
        "piętnaście": 15, "szesnaście": 16, "siedemnaście": 17, "osiemnaście": 18, "dziewiętnaście": 19,
    ]

    private static let tensValues: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
        "dwadzieścia": 20, "trzydzieści": 30, "czterdzieści": 40, "pięćdziesiąt": 50,
        "sześćdziesiąt": 60, "siedemdziesiąt": 70, "osiemdziesiąt": 80, "dziewięćdziesiąt": 90,
    ]

    private static let hundredValues: [String: Int] = [
        "sto": 100, "dwieście": 200, "trzysta": 300, "czterysta": 400,
        "pięćset": 500, "sześćset": 600, "siedemset": 700, "osiemset": 800, "dziewięćset": 900,
    ]

    private static let groupScaleValues: [String: Int] = [
        "thousand": 1_000,
        "tysiąc": 1_000, "tysiące": 1_000, "tysięcy": 1_000,
        "million": 1_000_000,
        "milion": 1_000_000, "miliony": 1_000_000, "milionów": 1_000_000,
    ]

    private enum TokenKind {
        case word
        case digit
        case other
    }

    private struct Token {
        let text: String
        let kind: TokenKind
    }

    private struct WordCandidate {
        let tokenIndex: Int
        let word: String
    }

    private struct ParsedNumber {
        let replacement: String
        let endIndex: Int
    }

    static func normalize(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let tokens = tokenize(text)
        var result = ""
        var index = 0
        while index < tokens.count {
            if tokens[index].kind == .word,
               let parsed = parseNumberSequence(startingAt: index, in: tokens) {
                result.append(parsed.replacement)
                index = parsed.endIndex
            } else {
                result.append(tokens[index].text)
                index += 1
            }
        }
        return result
    }

    private static func parseNumberSequence(startingAt index: Int, in tokens: [Token]) -> ParsedNumber? {
        let candidates = wordCandidates(startingAt: index, in: tokens)
        guard !candidates.isEmpty else { return nil }
        let words = candidates.map(\.word)
        guard let parsed = parseInteger(words),
              parsed.consumedWords > 0,
              parsed.consumedWords <= words.count else {
            return nil
        }
        let lastTokenIndex = candidates[parsed.consumedWords - 1].tokenIndex
        return ParsedNumber(replacement: "\(parsed.value)", endIndex: lastTokenIndex + 1)
    }

    private static func parseInteger(_ words: [String]) -> (value: Int, consumedWords: Int)? {
        var index = 0
        var total = 0
        var current = 0
        var consumed = false

        if let group = parseGroup(words, startingAt: index) {
            current = group.value
            index = group.nextIndex
            consumed = true
        }

        while index < words.count {
            guard let scale = groupScaleValues[words[index]] else { break }
            let base = current > 0 ? current : 1
            total += base * scale
            current = 0
            consumed = true
            index += 1

            if index < words.count, words[index] == "and" {
                index += 1
            }

            if let group = parseGroup(words, startingAt: index) {
                current = group.value
                index = group.nextIndex
            }
        }

        guard consumed else { return nil }
        return (total + current, index)
    }

    private static func parseGroup(_ words: [String], startingAt startIndex: Int) -> (value: Int, nextIndex: Int)? {
        var index = startIndex
        var value = 0
        var consumed = false

        if index + 1 < words.count,
           let base = smallValue(words[index]),
           words[index + 1] == "hundred" {
            value = base * 100
            index += 2
            consumed = true
            if index < words.count, words[index] == "and" {
                index += 1
            }
        } else if index < words.count, let hundred = hundredValues[words[index]] {
            value = hundred
            index += 1
            consumed = true
        }

        if index < words.count, let tens = tensValues[words[index]] {
            value += tens
            index += 1
            consumed = true
            if index < words.count, let unit = unitValues[words[index]], unit > 0 {
                value += unit
                index += 1
            }
        } else if index < words.count, let small = smallValue(words[index]) {
            value += small
            index += 1
            consumed = true
        }

        guard consumed else { return nil }
        return (value, index)
    }

    private static func smallValue(_ word: String) -> Int? {
        unitValues[word] ?? teenValues[word]
    }

    private static func wordCandidates(startingAt index: Int, in tokens: [Token]) -> [WordCandidate] {
        var candidates: [WordCandidate] = []
        var current = index
        while current < tokens.count, tokens[current].kind == .word {
            candidates.append(WordCandidate(tokenIndex: current, word: tokens[current].text.lowercased()))
            let separatorIndex = current + 1
            let nextIndex = current + 2
            guard separatorIndex < tokens.count,
                  nextIndex < tokens.count,
                  tokens[nextIndex].kind == .word,
                  isConnector(tokens[separatorIndex].text) else {
                break
            }
            current = nextIndex
        }
        return candidates
    }

    private static func isConnector(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar) || scalar == "-" || scalar == "\u{2011}"
        }
    }

    private static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var currentKind: TokenKind?
        for character in text {
            let kind = tokenKind(for: character)
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

    private static func tokenKind(for character: Character) -> TokenKind {
        if character.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) {
            return .digit
        }
        if character.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) {
            return .word
        }
        return .other
    }
}
