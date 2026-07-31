import Foundation

public struct Language: Identifiable, Hashable {
    public let code: String
    public let name: String
    public var id: String { code }

    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }

    public static let all: [Language] = [
        Language(code: "bg", name: "Bulgarian"),
        Language(code: "hr", name: "Croatian"),
        Language(code: "cs", name: "Czech"),
        Language(code: "da", name: "Danish"),
        Language(code: "nl", name: "Dutch"),
        Language(code: "en", name: "English"),
        Language(code: "et", name: "Estonian"),
        Language(code: "fi", name: "Finnish"),
        Language(code: "fr", name: "French"),
        Language(code: "de", name: "German"),
        Language(code: "el", name: "Greek"),
        Language(code: "hu", name: "Hungarian"),
        Language(code: "it", name: "Italian"),
        Language(code: "lv", name: "Latvian"),
        Language(code: "lt", name: "Lithuanian"),
        Language(code: "mt", name: "Maltese"),
        Language(code: "pl", name: "Polish"),
        Language(code: "pt", name: "Portuguese"),
        Language(code: "ro", name: "Romanian"),
        Language(code: "sk", name: "Slovak"),
        Language(code: "sl", name: "Slovenian"),
        Language(code: "es", name: "Spanish"),
        Language(code: "sv", name: "Swedish"),
        Language(code: "ru", name: "Russian"),
        Language(code: "uk", name: "Ukrainian"),
    ]

    public static func language(for code: String?) -> Language? {
        guard let code else { return nil }
        return all.first { $0.code == code }
    }
}
