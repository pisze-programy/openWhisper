import Foundation
#if os(iOS)
import ActivityKit

public struct DictationActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public enum Phase: String, Codable, Hashable {
            case recording
            case transcribing
            case done
        }
        public var phase: Phase
        public var elapsed: TimeInterval
        public var note: String?

        public init(phase: Phase, elapsed: TimeInterval, note: String? = nil) {
            self.phase = phase
            self.elapsed = elapsed
            self.note = note
        }
    }

    public init() {}
}
#endif
