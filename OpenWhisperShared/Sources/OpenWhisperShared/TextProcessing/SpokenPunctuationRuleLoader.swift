import Foundation

/// Loads per-language spoken-punctuation rule sets from the app bundle
/// (`<code>.json` under `PunctuationRules`), caching parsed results.
public final class SpokenPunctuationRuleLoader: @unchecked Sendable {
    private let bundle: Bundle
    private var cache: [String: SpokenPunctuationRuleSet] = [:]

    public init(bundle: Bundle? = nil) {
        // SPM packages resolve resources through Bundle.module; app targets
        // carrying the rules in their own bundle can pass one explicitly.
        self.bundle = bundle ?? Self.resourceBundle()
    }

    /// Finds the bundle that actually carries the PunctuationRules directory.
    /// `Bundle.module` works inside a regular target but can point at the wrong
    /// bundle under some test configurations, so we fall back to scanning.
    private static func resourceBundle() -> Bundle {
        if Bundle.module.url(forResource: "en", withExtension: "json", subdirectory: "PunctuationRules") != nil {
            return Bundle.module
        }
        for candidate in Bundle.allBundles where
            candidate.url(forResource: "en", withExtension: "json", subdirectory: "PunctuationRules") != nil {
            return candidate
        }
        return Bundle.module
    }

    public func ruleSet(for languageCode: String?) -> SpokenPunctuationRuleSet? {
        guard let normalized = PunctuationLanguageNormalizer.normalize(languageCode) else {
            return nil
        }
        if let cached = cache[normalized] { return cached }
        guard let url = bundle.url(forResource: normalized, withExtension: "json",
                                   subdirectory: "PunctuationRules"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        guard let set = try? JSONDecoder().decode(SpokenPunctuationRuleSet.self, from: data) else {
            return nil
        }
        cache[normalized] = set
        return set
    }
}
