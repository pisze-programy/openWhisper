import Foundation

extension TimeInterval {
    var clockString: String {
        let total = Int(self)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
