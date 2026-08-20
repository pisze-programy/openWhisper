import XCTest
@testable import OpenWhisperShared

final class TextProcessingTests: XCTestCase {

    func testInputBoundaryWrapAndSanitize() {
        let text = "Hello world"
        let wrapped = DictationInputBoundary.wrap(text)
        XCTAssertTrue(wrapped.contains("BEGIN DICTATED TEXT"))
        XCTAssertTrue(wrapped.contains("END DICTATED TEXT"))

        // Scaffold-free response passes through unchanged.
        let clean = DictationInputBoundary.sanitize("Hi there", originalText: text)
        XCTAssertEqual(clean, "Hi there")

        // Model echoing the boundary back gets cleaned.
        let echoed = """
        BEGIN DICTATED TEXT
        Hello
        END DICTATED TEXT
        """
        let cleaned = DictationInputBoundary.sanitize(echoed, originalText: text)
        XCTAssertEqual(cleaned, "Hello")
    }

    func testPromptComposerIncludesBoundaryAndStyle() {
        let prompt = PromptComposer.formatPrompt(style: .formal)
        XCTAssertTrue(prompt.contains("source text to transform"))
        XCTAssertTrue(prompt.contains("raw speech-to-text"))
        XCTAssertTrue(prompt.contains("Return only the"))
        XCTAssertFalse(prompt.isEmpty)
    }

    func testFormatPromptWithTranslationOverridesSourceLanguage() {
        let options = PromptComposer.Options(
            languageCode: "pl",
            targetLanguageCode: "en"
        )
        let prompt = PromptComposer.formatPrompt(style: .formal, options: options)
        XCTAssertTrue(prompt.contains("Detected source language: pl"))
        XCTAssertTrue(prompt.contains("Translate the source text into en"))
        XCTAssertTrue(prompt.contains("overriding any instruction to respond in the source language"))
    }

    func testTranslatePromptIsTranslateOnly() {
        let prompt = PromptComposer.translatePrompt(
            sourceLanguageCode: "pl",
            targetLanguageCode: "en"
        )
        XCTAssertTrue(prompt.contains("Translate the following dictated text into en"))
        XCTAssertTrue(prompt.contains("faithful translation"))
        XCTAssertFalse(prompt.contains("Reformulate"))
        XCTAssertFalse(prompt.contains("polish"))
        XCTAssertTrue(prompt.contains("source text to transform"))
    }

    func testTranslatePromptNoTargetFallback() {
        let prompt = PromptComposer.translatePrompt(targetLanguageCode: nil)
        XCTAssertTrue(prompt.contains("Translate the following dictated text into the requested language"))
    }

    func testNumberNormalizationEnglish() {
        XCTAssertEqual(NumberWordNormalizer.normalize(text: "twenty five", language: "en"), "25")
        XCTAssertEqual(NumberWordNormalizer.normalize(text: "one hundred and five", language: "en"), "105")
    }

    func testNumberNormalizationPolish() {
        XCTAssertEqual(NumberWordNormalizer.normalize(text: "dwadzieścia pięć", language: "pl"), "25")
    }

    func testNumberNormalizationUnknownLanguagePassthrough() {
        XCTAssertEqual(NumberWordNormalizer.normalize(text: "twenty five", language: "xx"), "twenty five")
    }

    func testPunctuationEnglish() async {
        let service = await MainActor.run { SpokenPunctuationService() }
        let result = await MainActor.run {
            service.normalize(text: "hello comma world", language: "en", mode: .fallbackOnly)
        }
        XCTAssertEqual(result, "hello, world")
    }

    func testMarkerStrippingRemovesKnownMarkers() {
        XCTAssertEqual(MarkerStripper.strip("hello [NOISE] world"), "hello world")
        XCTAssertEqual(MarkerStripper.strip("hello [MUSIC]"), "hello")
        XCTAssertEqual(MarkerStripper.strip("[LAUGHTER] hello"), "hello")
        XCTAssertEqual(MarkerStripper.strip("a (cough) b"), "a b")
        XCTAssertEqual(MarkerStripper.strip("[BLANK_AUDIO] hello [APPLAUSE]"), "hello")
    }

    func testMarkerStrippingCaseInsensitive() {
        XCTAssertEqual(MarkerStripper.strip("hello [noise] and [MUSIC]"), "hello and")
    }

    func testMarkerStrippingPreservesArbitraryBrackets() {
        XCTAssertEqual(MarkerStripper.strip("use [Ctrl+C] here"), "use [Ctrl+C] here")
        XCTAssertEqual(MarkerStripper.strip("note [1] and (2)"), "note [1] and (2)")
        XCTAssertEqual(MarkerStripper.strip("plain text"), "plain text")
    }

    func testSilencePadder() {
        let short = [Float](repeating: 0, count: 4000) // 0.25s
        let padded = SilencePadder.pad(short, rawDuration: 0.25)
        XCTAssertEqual(padded.count, Int(0.75 * 16000))

        let longer = [Float](repeating: 0.1, count: 20000) // 1.25s
        let tailPadded = SilencePadder.pad(longer, rawDuration: 1.25)
        XCTAssertEqual(tailPadded.count, 20000 + Int(0.3 * 16000))
    }

    func testShortSpeechClassifier() {
        XCTAssertEqual(
            ShortSpeechClassifier.classify(rawDuration: 0.01, peakLevel: 0.1, hasConfirmedText: false),
            .discardTooShort
        )
        XCTAssertEqual(
            ShortSpeechClassifier.classify(rawDuration: 0.5, peakLevel: 0.01, hasConfirmedText: false),
            .transcribe
        )
        XCTAssertEqual(
            ShortSpeechClassifier.classify(rawDuration: 2.0, peakLevel: 0.0001, hasConfirmedText: false),
            .discardNoSpeech
        )
    }

    @MainActor
    func testPostProcessingPipeline() async throws {
        let pipeline = PostProcessingPipeline()
        let context = PostProcessingPipeline.Context(
            languageCode: "en",
            engineId: "parakeet",
            formattingEnabled: false
        )
        let result = try await pipeline.process(
            text: "twenty five and a question mark",
            context: context,
            corrections: nil
        )
        XCTAssertTrue(result.text.contains("25"))
    }

    @MainActor
    func testTranslationCycleWrapsThroughNoneAndTargets() {
        let settings = SettingsStore()
        settings.translationTargets = ["pl", "en"]
        settings.translationTargetCode = nil

        settings.cycleTranslationTarget()
        XCTAssertEqual(settings.translationTargetCode, "pl")

        settings.cycleTranslationTarget()
        XCTAssertEqual(settings.translationTargetCode, "en")

        settings.cycleTranslationTarget()
        XCTAssertNil(settings.translationTargetCode) // wraps back to NONE
    }

    @MainActor
    func testTranslationCycleKeepsNoneWhenAllLanguagesRemoved() {
        let settings = SettingsStore()
        settings.translationTargets = []
        settings.translationTargetCode = nil

        settings.cycleTranslationTarget()
        XCTAssertNil(settings.translationTargetCode)
    }

    @MainActor
    func testRemovingSelectedTargetResetsToNone() {
        let settings = SettingsStore()
        settings.translationTargets = ["pl", "en"]
        settings.translationTargetCode = "pl"

        settings.translationTargets.removeAll { $0 == "pl" }
        XCTAssertEqual(settings.translationTargets, ["en"])
        XCTAssertNil(settings.translationTargetCode)
    }

    @MainActor
    func testTranslationCyclePreviewDoesNotPersist() {
        let settings = SettingsStore()
        settings.translationTargets = ["pl", "en"]
        settings.translationTargetCode = nil

        settings.cycleTranslationTarget(preview: true)
        XCTAssertEqual(settings.translationTargetCode, "pl")
        XCTAssertNil(SettingsStore.suite.string(forKey: "settings.translationTargetCode"))

        settings.persistTranslationTarget()
        XCTAssertEqual(SettingsStore.suite.string(forKey: "settings.translationTargetCode"), "pl")
    }
}
