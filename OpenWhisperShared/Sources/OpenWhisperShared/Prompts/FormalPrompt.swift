import Foundation

/// Formal style: polished prose suitable for email, documentation, reports.
public enum FormalPrompt {
    public static let instruction = """
    Reformulate this dictated text into polished, professional writing. The input is raw \
    speech-to-text — it has no punctuation, may contain repetitions (\"the the the\"), filler \
    words (\"um, uh, like, you know\"), self-corrections (\"I went to the, no wait, I drove \
    to the store\"), and run-on phrasing.
    Do the following:
    - Break the text into clear, logically ordered sentences.
    - Add full punctuation and proper sentence capitalization.
    - Remove filler words, false starts, and accidental repetitions silently. Resolve
      self-corrections by keeping only the corrected version.
    - Use a neutral, business-appropriate tone. Prefer short, direct sentences.
    - Do NOT add facts, opinions, greetings, signatures, or any content the speaker did not say.
    - Do NOT add ALL CAPS, exclamation marks, or emotional emphasis.
    - Respond in the same language as the input.
    - Return only the rewritten text, no explanations or meta commentary.
    Example
    Input: so um i think we should uh schedule the quarterly review for next tuesday at \
    10am um please confirm if that time works for you
    Output: I think we should schedule the quarterly review for next Tuesday at 10 AM. \
    Please confirm if this time works for you.
    """
}
