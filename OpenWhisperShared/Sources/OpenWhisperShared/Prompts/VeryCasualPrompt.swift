import Foundation

/// Minimal style: rewrite as a fast, casual text — lowercase, no punctuation, no apostrophes.
public enum VeryCasualPrompt {
    public static let instruction = """
    Reformulate this dictated text to read like a quick, casual message someone typed fast \
    to a close friend. The input is raw speech-to-text — it has no punctuation, may contain \
    repetitions (\"the the the\"), filler words (\"um, uh, like, you know\"), \
    self-corrections (\"I went to the, no wait, I drove to the store\"), and run-on phrasing.
    Do the following:
    - Remove filler words (\"um\", \"uh\", \"you know\", \"like\") and repeated words/phrases
      caused by stuttering or hesitation.
    - Resolve self-corrections: keep only the corrected version, drop the abandoned start.
      Self-correction markers vary by language (e.g. English \"no wait\", \"I mean\"; Polish
      \"a nie\", \"czekaj\", \"no nie\") — identify them by their corrective function in
      context, not by matching one fixed phrase.
    - Write everything in lowercase — no capital letter at the start of a sentence, no
      capitalized \"I\", no capitalized names — the way people type when they're moving fast
      and not touching Shift.
    - Do NOT add periods, commas, question marks, or exclamation marks. Only keep a piece of
      punctuation if leaving it out would make the text genuinely unreadable or flip its
      meaning (e.g. a decimal number, a time like \"12:30\").
    - Write contractions without the apostrophe, the way people type them fast (\"lets\" not
      \"let's\", \"dont\" not \"don't\", \"im\" not \"I'm\", \"youre\" not \"you're\").
    - Do NOT rephrase or rewrite sentences unless they are grammatically broken beyond
      comprehension. Preserve the speaker's exact word choices, idioms, and sentence
      structure wherever possible.
    - Do NOT change the tone or register beyond this formatting. Do NOT make it more formal,
      and do NOT invent slang or abbreviations the speaker did not use.
    - Do NOT add facts, opinions, or any content the speaker did not say.
    - Respond in the same language as the input.
    - Return only the cleaned text, no explanations or meta commentary.
    Example
    Input: Hey, um are you free for lunch tomorrow uh let's do 12 if that works for you.
    Output: hey are you free for lunch tomorrow lets do 12 if that works
    """
}

