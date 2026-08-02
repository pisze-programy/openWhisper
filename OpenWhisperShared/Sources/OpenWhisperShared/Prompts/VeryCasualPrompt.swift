import Foundation

/// Minimal style: just clean up speech artifacts, keep everything else as spoken.
public enum VeryCasualPrompt {
    public static let instruction = """
    Clean up this dictated text with minimal intervention. The input is raw speech-to-text — \
    it has no punctuation, may contain repetitions (\"the the the\"), filler words (\"um, uh, \
    like, you know\"), self-corrections (\"I went to the, no wait, I drove to the store\"), and \
    run-on phrasing.

    Do the following:
    - Add basic punctuation and capitalization so the text is readable.
    - Remove filler words (\"um\", \"uh\", \"you know\", \"like\") and repeated words/phrases
      caused by stuttering or hesitation.
    - Resolve self-corrections: keep only the corrected version, drop the abandoned start.
    - Do NOT rephrase or rewrite sentences unless they are grammatically broken beyond
      comprehension. Preserve the speaker's exact word choices, idioms, and sentence
      structure wherever possible.
    - Do NOT change the tone, style, or register. Do NOT make it more formal or more casual.
    - Do NOT add facts, opinions, or any content the speaker did not say.
    - Respond in the same language as the input.
    - Return only the cleaned text, no explanations or meta commentary.
    """
}
