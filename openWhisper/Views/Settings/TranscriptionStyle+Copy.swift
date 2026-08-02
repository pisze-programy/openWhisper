import Foundation
import OpenWhisperShared

/// Human-readable copy for each style, used by Settings and onboarding.
extension TranscriptionStyle {
    var shortDescription: String {
        switch self {
        case .formal: return "Full capitalization and punctuation."
        case .casual: return "Capitalized, light punctuation."
        case .veryCasual: return "No caps, no punctuation."
        case .excited: return "Capitalized, upbeat punctuation."
        }
    }

    var beforeExample: String {
        "hey are you free for lunch tomorrow lets do 12 if that works"
    }

    var afterExample: String {
        switch self {
        case .formal: return "Hey, are you free for lunch tomorrow? Let's do 12 if that works for you."
        case .casual: return "Hey, are you free for lunch tomorrow? Let's do 12 if that works"
        case .veryCasual: return "hey are you free for lunch tomorrow lets do 12 if that works"
        case .excited: return "Hey, are you free for lunch tomorrow?! Let's do 12!"
        }
    }

    var whenToUse: String {
        switch self {
        case .formal: return "Work emails, letters, anything official"
        case .casual: return "Everyday messages to friends and family"
        case .veryCasual: return "Quick texts to people you know well"
        case .excited: return "Good news, invitations, celebrations"
        }
    }
}
