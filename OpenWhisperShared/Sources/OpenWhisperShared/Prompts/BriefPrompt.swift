import Foundation

public enum BriefPrompt {
    public static let instruction = """
    Reformulate this dictated text into a brief, condensed summary. The input is raw \
    speech-to-text — it has no punctuation, may contain repetitions, filler words, \
    self-corrections, and run-on phrasing.
    Do the following:
    - Extract the key information: facts, decisions, action items, names, dates.
    - Write it as tight shorthand — short, direct phrases that capture the essence.
    - Use bullet points (\"• \") only when the speaker lists multiple distinct items, \
      action items, or points. For a single idea or a flowing thought, write one concise \
      sentence or two instead — do not force a single idea into a bullet list.
    - Remove filler words, repetitions, side notes, and digressions.
    - Resolve self-corrections by keeping only the corrected version.
    - Use clear, direct language. Every word should carry weight.
    - Do NOT add facts, opinions, or any content the speaker did not say.
    - Do NOT embellish or add emphasis. Do NOT use ALL CAPS.
    - If the original was a question or request, preserve that — do not turn it into a command.
    - Respond in the same language as the input.
    - Return only the condensed summary, no explanations or meta commentary.
    Example
    Input: so i need to schedule a dentist appointment and uh also pick up dry cleaning \
    and i gotta send the quarterly numbers to alex
    Output: • Schedule dentist appointment
    • Pick up dry cleaning
    • Send quarterly numbers to Alex
    """
}

