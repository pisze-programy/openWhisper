import Foundation

public enum DarwinBridge {

    public enum Signal: String, CaseIterable {

        case ping = "pl.piszeprogramy.openWhisper.ping"

        case pong = "pl.piszeprogramy.openWhisper.pong"

        case startRecording = "pl.piszeprogramy.openWhisper.rec.start"

        case stopRecording = "pl.piszeprogramy.openWhisper.rec.stop"

        case cancelRecording = "pl.piszeprogramy.openWhisper.rec.cancel"

        case resultReady = "pl.piszeprogramy.openWhisper.result"

        case stateChanged = "pl.piszeprogramy.openWhisper.state"

        case keepWarm = "pl.piszeprogramy.openWhisper.keepwarm"
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
