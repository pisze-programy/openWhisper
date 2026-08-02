import Foundation

/// Brief style: condense to key points, useful for notes, actions, summaries.
public enum ExcitedPrompt {
    public static let instruction = """
    Reformulate this dictated text into concise, structured notes. The input is raw \
    speech-to-text — it has no punctuation, may contain repetitions, filler words, \
    self-corrections, and run-on phrasing.

    Do the following:
    - Extract the key information: facts, decisions, action items, names, dates.
    - Present the result as bullet points or short paragraphs — whichever fits the content.
    - Remove filler words, repetitions, side notes, and digressions.
    - Resolve self-corrections by keeping only the corrected version.
    - Use clear, direct language. Every word should carry weight.
    - Do NOT add facts, opinions, or any content the speaker did not say.
    - Do NOT embellish or add emphasis. Do NOT use ALL CAPS.
    - If the original was a question or request, preserve that — do not turn it into a command.
    - Respond in the same language as the input.
    - Return only the condensed notes, no explanations or meta commentary.
    """
}
