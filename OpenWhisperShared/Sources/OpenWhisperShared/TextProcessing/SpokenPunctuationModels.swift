import Foundation

/// Codable model for a single spoken-punctuation replacement rule loaded from a
/// per-language JSON bundle.
public struct SpokenPunctuationRule: Codable, Hashable, Sendable {
    public let phrase: String
    public let replacement: String
    public let category: SpokenPunctuationCategory

    public init(phrase: String, replacement: String, category: SpokenPunctuationCategory) {
        self.phrase = phrase
        self.replacement = replacement
        self.category = category
    }
}

public enum SpokenPunctuationCategory: String, Codable, Hashable, Sendable {
    case punctuation
    case brackets
    case quotes
    case structural
}

/// Codable per-language rule set.
public struct SpokenPunctuationRuleSet: Codable, Hashable, Sendable {
    public let language: String
    public let rules: [SpokenPunctuationRule]

    public init(language: String, rules: [SpokenPunctuationRule]) {
        self.language = language
        self.rules = rules
    }
}

/// How the punctuation pass should behave for a given engine + language.
public enum SpokenPunctuationStrategy: String, Codable, Sendable {
    /// The STT model already emits punctuation natively; skip the fallback.
    case nativeOnly
    /// Apply the rule-based fallback only when it changes nothing essential
    /// (selective), otherwise keep the model output.
    case automatic
    /// Apply the full rule-based fallback unconditionally.
    case fallbackOnly
}

/// A resolved, per-engine strategy with the language the rules should use.
public struct ResolvedPunctuationStrategy: Sendable {
    public let languageCode: String
    public let strategy: SpokenPunctuationStrategy

    public init(languageCode: String, strategy: SpokenPunctuationStrategy) {
        self.languageCode = languageCode
        self.strategy = strategy
    }
}

/// Normalizes language codes so rules and profiles match across dialects.
public enum PunctuationLanguageNormalizer {
    public static func normalize(_ code: String?) -> String? {
        guard let trimmed = code?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !trimmed.isEmpty else { return nil }
        let primary = trimmed.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init)
        return primary ?? trimmed
    }
}
