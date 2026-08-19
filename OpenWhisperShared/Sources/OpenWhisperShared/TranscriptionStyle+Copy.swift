import Foundation

extension TranscriptionStyle {
    public var shortDescription: String {
        switch self {
        case .none: return "No AI rewrite — fast, local, no API."
        case .formal: return "Complete sentences, no filler words."
        case .casual: return "Natural conversation, light polish."
        case .veryCasual: return "A fast text to a close friend — no caps, no punctuation, no apostrophes."
        case .brief: return "Condense into a tight, key-point summary."
        }
    }

    public var beforeExample: String {
        "hey so um are you free for lunch tomorrow lets do like 12 if that works"
    }

    public var afterExample: String {
        switch self {
        case .none: return "hey so um are you free for lunch tomorrow lets do like 12 if that works"
        case .formal: return "Are you free for lunch tomorrow? Let's meet at 12 if that works for you."
        case .casual: return "Hey, are you free for lunch tomorrow? Let's do 12 if that works."
        case .veryCasual: return "hey are you free for lunch tomorrow lets do 12 if that works"
        case .brief: return "• Lunch tomorrow?\n• 12:00\n• Confirm availability"
        }
    }

    public var whenToUse: String {
        switch self {
        case .none: return "Fast, local, no AI — raw transcript"
        case .formal: return "Emails, reports, documentation"
        case .casual: return "Chats, emails to people you don't know well"
        case .veryCasual: return "Texting close friends — fast, no caps, no punctuation"
        case .brief: return "Meeting notes, action items, summaries"
        }
    }
}
