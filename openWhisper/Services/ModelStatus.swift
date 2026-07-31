import Foundation

/// State of the on-device speech model.
enum ModelStatus: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case ready
    case failed(String)
}
