import Foundation

public enum ModelStatus: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case ready
    case failed(String)
}
