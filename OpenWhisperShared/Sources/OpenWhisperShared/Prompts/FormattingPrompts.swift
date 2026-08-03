import Foundation
import OpenWhisperShared

/// Resolves the prompt for a given style. Each style's instruction lives in its
/// own file under Prompts/ so prompts are easy to find and tweak.
public enum FormattingPrompts {
    public static func instruction(for style: TranscriptionStyle) -> String {
        switch style {
        case .none: return ""
        case .formal: return FormalPrompt.instruction
        case .casual: return CasualPrompt.instruction
        case .veryCasual: return VeryCasualPrompt.instruction
        case .excited: return ExcitedPrompt.instruction
        }
    }
}
