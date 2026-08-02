import Foundation

/// Writing style applied by the AI formatting step to a finished transcript.
/// Each case maps to a prompt in the app's Prompts/ folder, so the LLM call gets
/// the instruction that matches the style selected at recording time.
public enum TranscriptionStyle: String, CaseIterable, Identifiable, Sendable {
    case formal
    case casual
    case veryCasual
    case excited

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .formal: return "Formal"
        case .casual: return "Casual"
        case .veryCasual: return "Very Casual"
        case .excited: return "Excited"
        }
    }

    public var systemImage: String {
        switch self {
        case .formal: return "textformat"
        case .casual: return "bubble.left"
        case .veryCasual: return "ellipsis.message"
        case .excited: return "bolt.fill"
        }
    }
}
