import Foundation

extension TranscriptionStyle {
    public var shortDescription: String {
        switch self {
        case .formal: return "Complete sentences, no filler words."
        case .casual: return "Natural conversation, light polish."
        case .veryCasual: return "Just fix speech artifacts, keep your words."
        case .excited: return "Condense to bullet points and key info."
        }
    }

    public var beforeExample: String {
        "hey so um are you free for lunch tomorrow lets do like 12 if that works"
    }

    public var afterExample: String {
        switch self {
        case .formal: return "Are you free for lunch tomorrow? Let's meet at 12 if that works for you."
        case .casual: return "Hey, are you free for lunch tomorrow? Let's do 12 if that works."
        case .veryCasual: return "hey are you free for lunch tomorrow lets do 12 if that works"
        case .excited: return "• Lunch tomorrow?\n• 12:00\n• Confirm availability"
        }
    }

    public var whenToUse: String {
        switch self {
        case .formal: return "Emails, reports, documentation"
        case .casual: return "Messages, chat, everyday notes"
        case .veryCasual: return "When you want your exact words, just cleaned up"
        case .excited: return "Meeting notes, action items, summaries"
        }
    }
}
