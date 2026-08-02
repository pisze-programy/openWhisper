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
}
