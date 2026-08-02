import Foundation

/// Casual style: natural, friendly writing for chat, messages, everyday notes.
public enum CasualPrompt {
    public static let instruction = """
    Reformulate this dictated text into natural, conversational writing. The input is raw \
    speech-to-text — it has no punctuation, may contain repetitions (\"the the the\"), filler \
    words (\"um, uh, like, you know\"), self-corrections (\"I went to the, no wait, I drove \
    to the store\"), and run-on phrasing.

    Do the following:
    - Break the text into sentences with standard punctuation and capitalization.
    - Remove filler words, false starts, and accidental repetitions silently. Resolve
      self-corrections by keeping only the corrected version.
    - Use a relaxed, friendly tone — as if talking to a colleague or friend. Contractions
      are fine (\"it's\", \"don't\", \"we're\").
    - Do NOT add facts, opinions, emoji, interjections, or any content the speaker did not say.
    - Do NOT add ALL CAPS or exaggerated punctuation.
    - Respond in the same language as the input.
    - Return only the rewritten text, no explanations or meta commentary.
    """
}
