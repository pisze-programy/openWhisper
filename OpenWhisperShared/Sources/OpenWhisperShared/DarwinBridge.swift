import Foundation

public enum DarwinBridge {

    public enum Signal: String, CaseIterable {

        case ping = "pl.piszeprogramy.openwhisper.ping"

        case pong = "pl.piszeprogramy.openwhisper.pong"

        case startRecording = "pl.piszeprogramy.openwhisper.rec.start"

        case stopRecording = "pl.piszeprogramy.openwhisper.rec.stop"

        case cancelRecording = "pl.piszeprogramy.openwhisper.rec.cancel"

        case resultReady = "pl.piszeprogramy.openwhisper.result"

        case stateChanged = "pl.piszeprogramy.openwhisper.state"

        case keepWarm = "pl.piszeprogramy.openwhisper.keepwarm"
    }

    private static var center: CFNotificationCenter {
        CFNotificationCenterGetDarwinNotifyCenter()
    }

    public static func post(_ signal: Signal) {
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(signal.rawValue as CFString),
            nil,
            nil,
            true
        )
    }

    public typealias Handler = @MainActor () -> Void

    private static var handlers: [String: [Handler]] = [:]
    private static let lock = NSLock()

    private static let callback: CFNotificationCallback = { _, _, name, _, _ in
        guard let raw = name?.rawValue as String? else { return }
        lock.lock()
        let fns = handlers[raw] ?? []
        lock.unlock()
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                fns.forEach { $0() }
            }
        }
    }

    public static func observe(_ signal: Signal, handler: @escaping Handler) {
        lock.lock()
        let alreadyRegistered = handlers[signal.rawValue] != nil
        handlers[signal.rawValue, default: []].append(handler)
        lock.unlock()

        guard !alreadyRegistered else { return }
        CFNotificationCenterAddObserver(
            center,
            nil,
            callback,
            signal.rawValue as CFString,
            nil,
            .deliverImmediately
        )
    }

    public static func removeAllObservers() {
        lock.lock()
        handlers.removeAll()
        lock.unlock()
        CFNotificationCenterRemoveEveryObserver(center, nil)
    }
}
