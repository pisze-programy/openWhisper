import Foundation

public extension AppGroup {

    enum BridgeKey {
        public static let hostHeartbeat = "bridge.hostHeartbeat"
        public static let engineState = "bridge.engineState"
        public static let engineLevel = "bridge.engineLevel"
        public static let engineError = "bridge.engineError"
        public static let returnBundleId = "bridge.returnBundleId"
        public static let lastInsertedStamp = "bridge.lastInsertedStamp"
        public static let inPlaceReady = "bridge.inPlaceReady"
    }

    enum EngineState: String {
        case unknown
        case loading
        case ready
        case recording
        case transcribing
        case error
    }

    private static var bridgeDir: URL {
        let dir = containerURL.appendingPathComponent("bridge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func jsonURL(_ name: String) -> URL {
        bridgeDir.appendingPathComponent(name)
    }

    private static func writeJSON<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: jsonURL(name), options: .atomic)
    }

    private static func readJSON<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: jsonURL(name)),
              let value = try? JSONDecoder().decode(type, from: data)
        else { return nil }
        return value
    }

    public static var commandFileURL: URL { jsonURL("command.json") }

    public struct Command: Codable {
        public enum Action: String, Codable { case start, stop, cancel }
        public let action: Action
        public let stamp: TimeInterval
        public init(action: Action, stamp: TimeInterval = Date().timeIntervalSince1970) {
            self.action = action
            self.stamp = stamp
        }
    }

    public static func writeCommand(_ action: Command.Action) {
        writeJSON(Command(action: action), to: "command.json")
    }

    public static func readCommand() -> Command? {
        readJSON(Command.self, from: "command.json")
    }

    public static var dictationFileURL: URL { jsonURL("last-dictation.json") }

    public struct DictationPayload: Codable {
        public let text: String
        public let stamp: TimeInterval

        public var note: String?
        public init(text: String, stamp: TimeInterval, note: String? = nil) {
            self.text = text
            self.stamp = stamp
            self.note = note
        }
    }

    public static func writeDictation(text: String, note: String? = nil) {
        let payload = DictationPayload(
            text: text,
            stamp: Date().timeIntervalSince1970,
            note: note
        )
        writeJSON(payload, to: "last-dictation.json")
    }

    public static func clearDictation() {
        try? FileManager.default.removeItem(at: dictationFileURL)
    }

    public static func readDictation() -> DictationPayload? {
        readJSON(DictationPayload.self, from: "last-dictation.json")
    }

    public static var lastDictationStamp: TimeInterval {
        readDictation()?.stamp ?? 0
    }

    private struct InsertedBox: Codable { let stamp: TimeInterval }

    public static var lastInsertedStamp: TimeInterval {
        readJSON(InsertedBox.self, from: "inserted.json")?.stamp ?? 0
    }

    public static func setLastInsertedStamp(_ stamp: TimeInterval) {
        writeJSON(InsertedBox(stamp: stamp), to: "inserted.json")
    }

    private struct HeartbeatBox: Codable { let beat: TimeInterval }

    public static func stampHostHeartbeat() {
        writeJSON(HeartbeatBox(beat: Date().timeIntervalSince1970), to: "heartbeat.json")
    }

    public static func isHostAlive(window: TimeInterval = 3.0) -> Bool {
        guard let box = readJSON(HeartbeatBox.self, from: "heartbeat.json") else { return false }
        return Date().timeIntervalSince1970 - box.beat < window
    }

    private struct StateBox: Codable {
        let state: String
        var error: String?
    }

    public static func publishEngineState(_ state: EngineState, error: String? = nil) {
        writeJSON(StateBox(state: state.rawValue, error: error), to: "state.json")
    }

    public static func currentEngineState() -> EngineState {
        let raw = readJSON(StateBox.self, from: "state.json")?.state ?? ""
        return EngineState(rawValue: raw) ?? .unknown
    }

    public static var currentEngineError: String? {
        readJSON(StateBox.self, from: "state.json")?.error
    }

    private struct LevelBox: Codable { let level: Double }

    public static func publishLevel(_ level: Float) {
        writeJSON(LevelBox(level: Double(level)), to: "level.json")
    }

    public static func currentLevel() -> Float {
        Float(readJSON(LevelBox.self, from: "level.json")?.level ?? 0)
    }

    private struct ReadyBox: Codable { let ready: Bool }

    public static func setInPlaceReady(_ ready: Bool) {
        writeJSON(ReadyBox(ready: ready), to: "ready.json")
    }

    public static var isInPlaceReady: Bool {
        readJSON(ReadyBox.self, from: "ready.json")?.ready ?? false
    }
}
