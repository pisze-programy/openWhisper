import Foundation
import Observation

@MainActor @Observable
public final class ToastCenter {
    public private(set) var message: String?
    private var hideTask: Task<Void, Never>?

    public init() {}

    public func present(_ text: String) {
        message = text
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }
}
