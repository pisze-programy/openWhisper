import Foundation

enum SpeechPunctuation {
    private static let sentenceTerminators: Set<Character> = [".", "!", "?"]
    private static let punctuation: Set<Character> = [".", ",", ";", ":", "!", "?"]

    static func normalize(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = ""
        result.reserveCapacity(text.count)
        var index = text.startIndex
        var shouldCapitalize = true

        while index < text.endIndex {
            let character = text[index]
            if punctuation.contains(character) {
                while result.last?.isWhitespace == true {
                    result.removeLast()
                }
                if sentenceTerminators.contains(character) {
                    while result.last.map(sentenceTerminators.contains) == true {
                        result.removeLast()
                    }
                    result.append(character)
                    var next = text.index(after: index)
                    while next < text.endIndex, sentenceTerminators.contains(text[next]) {
                        result.removeLast()
                        result.append(text[next])
                        next = text.index(after: next)
                    }
                    index = next
                    if index < text.endIndex, text[index].isWhitespace {
                        while index < text.endIndex, text[index].isWhitespace {
                            index = text.index(after: index)
                        }
                    }
                    if index < text.endIndex {
                        result.append(" ")
                    }
                    shouldCapitalize = true
                    continue
                } else {
                    result.append(character)
                }
            } else if character.isWhitespace {
                if result.last != " " {
                    result.append(" ")
                }
            } else {
                if shouldCapitalize {
                    result.append(character.uppercased())
                    shouldCapitalize = false
                } else {
                    result.append(character)
                }
            }
            index = text.index(after: index)
        }
        return result
    }
}
