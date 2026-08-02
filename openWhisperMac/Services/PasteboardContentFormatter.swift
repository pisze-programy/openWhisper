import AppKit
import Foundation

/// Builds pasteboard payloads for a formatted paste. Converts Markdown-ish text
/// (bold/italic/code/lists) into RTF so rich-text apps keep the formatting; the
/// plain-text representation stays available as a fallback.
enum PasteboardContentFormatter {

    struct Payload {
        let plainText: String
        let additionalRepresentations: [NSPasteboard.PasteboardType: Data]

        var requiresPasteboardPayload: Bool { !additionalRepresentations.isEmpty }

        func write(to pasteboard: NSPasteboard, markerTypes: [NSPasteboard.PasteboardType] = []) {
            guard !additionalRepresentations.isEmpty || !markerTypes.isEmpty else {
                pasteboard.setString(plainText, forType: .string)
                return
            }
            let item = NSPasteboardItem()
            item.setString(plainText, forType: .string)
            for (type, data) in additionalRepresentations {
                item.setData(data, forType: type)
            }
            for marker in markerTypes {
                item.setData(Data(), forType: marker)
            }
            pasteboard.writeObjects([item])
        }
    }

    /// Returns an RTF payload when `format` is a rich format, else nil (plain
    /// text only).
    static func payload(for text: String, format: String?) -> Payload? {
        let normalized = OutputFormatResolver.normalized(format)
        guard normalized == "rtf" || normalized == "richtext" || normalized == "rich text" else {
            return nil
        }
        guard let rtfData = rtfData(fromMarkdown: text) else { return nil }
        return Payload(
            plainText: text,
            additionalRepresentations: [.rtf: rtfData]
        )
    }

    private static func rtfData(fromMarkdown text: String) -> Data? {
        let markdown = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let attributed: NSAttributedString
        do {
            attributed = try NSAttributedString(
                markdown: markdown,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
        } catch {
            attributed = NSAttributedString(string: text)
        }
        let range = NSRange(location: 0, length: attributed.length)
        guard range.length > 0,
              let data = try? attributed.data(
                  from: range,
                  documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
              ) else {
            return nil
        }
        return data
    }
}
