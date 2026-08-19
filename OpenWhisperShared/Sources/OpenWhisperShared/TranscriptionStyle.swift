import Foundation

/// Writing style applied by the AI formatting step to a finished transcript.
/// Each case maps to a prompt in the app's Prompts/ folder, so the LLM call gets
/// the instruction that matches the style selected at recording time.
public enum TranscriptionStyle: String, CaseIterable, Identifiable, Sendable {
    case none
    case formal
    case casual
    case veryCasual
    case brief

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: return "None"
        case .formal: return "Formal"
        case .casual: return "Casual"
        case .veryCasual: return "Minimal"
        case .brief: return "Brief"
        }
    }

    public var systemImage: String {
        switch self {
        case .none: return "circle.slash"
        case .formal: return "textformat"
        case .casual: return "bubble.left"
        case .veryCasual: return "scissors"
        case .brief: return "list.bullet"
        }
    }
}
