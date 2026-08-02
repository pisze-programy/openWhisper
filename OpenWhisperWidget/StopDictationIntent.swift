import Foundation
import AppIntents
import OpenWhisperShared

struct StopDictationIntent: AppIntent {
    static var title: LocalizedStringResource { "Stop dictation" }
    static var description: IntentDescription { "Stops the current OpenWhisper dictation." }
    static var openAppWhenRun: Bool { false }

    func perform() async throws -> some IntentResult {
        DarwinBridge.post(.stopRecording)
        return .result()
    }
}
