import Foundation
import Observation

@MainActor @Observable
final class ToastCenter {
    private(set) var message: String?
    private var hideTask: Task<Void, Never>?

    func present(_ text: String) {
        message = text
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }
}
