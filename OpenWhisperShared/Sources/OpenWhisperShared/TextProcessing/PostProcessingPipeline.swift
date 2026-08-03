import Foundation

/// Priority-ordered post-processing applied to a finished transcript before it
/// is inserted or saved. Steps are pure and deterministic where possible; only
/// the LLM step is fallible and aborts the pipeline on error.
///
/// Order: number normalization → speech punctuation → LLM polish → corrections.
@MainActor
public final class PostProcessingPipeline {

    public struct Context: Sendable {
        public var languageCode: String?
        public var engineId: String?
        public var formattingStyle: TranscriptionStyle?
        public var formattingEnabled: Bool

        public init(
            languageCode: String? = nil,
            engineId: String? = nil,
            formattingStyle: TranscriptionStyle? = nil,
            formattingEnabled: Bool = true
        ) {
            self.languageCode = languageCode
            self.engineId = engineId
            self.formattingStyle = formattingStyle
            self.formattingEnabled = formattingEnabled
        }
    }

    public struct Result: Sendable {
        public let text: String
        public let appliedSteps: [String]

        public init(text: String, appliedSteps: [String]) {
            self.text = text
            self.appliedSteps = appliedSteps
        }
    }

    private let punctuationService: SpokenPunctuationService

    public init(punctuationService: SpokenPunctuationService? = nil) {
        self.punctuationService = punctuationService ?? SpokenPunctuationService()
    }

    /// Runs the transcript through the pipeline.
    ///
    /// - Parameters:
    ///   - text: the raw transcript text.
    ///   - context: language, engine and formatting preferences.
    ///   - corrections: user dictionary corrections applied last (optional).
    ///   - llmHandler: optional async rewrite step (LLM polish). When nil or the
    ///     style is disabled, the LLM step is skipped.
    /// - Returns: the processed text plus the names of steps that changed it.
    public func process(
        text: String,
        context: Context,
        corrections: CorrectionsStore? = nil,
        llmHandler: ((String) async throws -> String)? = nil
    ) async throws -> Result {
        var result = text
        var applied: [String] = []

        // 050 — engine marker stripping (e.g. [NOISE], [MUSIC])
        let beforeMarkers = result
        result = MarkerStripper.strip(result)
        if result != beforeMarkers { applied.append("Marker stripping") }

        // 100 — number normalization
        let beforeNumbers = result
        result = NumberWordNormalizer.normalize(text: result, language: context.languageCode)
        if result != beforeNumbers { applied.append("Number normalization") }

        // 200 — spoken punctuation
        let beforePunctuation = result
        let strategy = SpokenPunctuationStrategyResolver.resolve(
            engineId: context.engineId, languageCode: context.languageCode
        )?.strategy ?? .automatic
        result = punctuationService.normalize(text: result, language: context.languageCode, mode: strategy)
        if result != beforePunctuation { applied.append("Punctuation") }

        // 300 — LLM polish (the only fallible step)
        if let llmHandler, context.formattingEnabled, context.formattingStyle != nil {
            result = try await llmHandler(result)
            applied.append("AI polish")
        }

        // 600 — user corrections
        if let corrections {
            let beforeCorrections = result
            result = corrections.apply(to: result)
            if result != beforeCorrections { applied.append("Corrections") }
        }

        return Result(text: result, appliedSteps: applied)
    }
}
