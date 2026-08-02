import Foundation

/// Resolves which punctuation strategy applies for a given engine + language.
/// Engines that emit punctuation natively (Parakeet on both platforms) default
/// to `.automatic` — the rule-based pass stays a safety net instead of fighting
/// the model output.
public enum SpokenPunctuationStrategyResolver {

    public static func resolve(
        engineId: String?,
        languageCode: String?
    ) -> ResolvedPunctuationStrategy? {
        guard let language = PunctuationLanguageNormalizer.normalize(languageCode) else {
            return nil
        }
        let strategy: SpokenPunctuationStrategy
        switch engineId?.lowercased() {
        case "parakeet", "fluidaudio", "fluidaudio":
            // Native punctuation; keep the fallback as a selective safety net.
            strategy = .automatic
        default:
            strategy = .automatic
        }
        return ResolvedPunctuationStrategy(languageCode: language, strategy: strategy)
    }
}
