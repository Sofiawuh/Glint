import AppKit

struct TranslationClipboardPayload {
    let plainText: String
    let rtf: Data

    static func make(currentText: String) -> TranslationClipboardPayload {
        let attributed = NSMutableAttributedString(
            string: currentText,
            attributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.textColor,
                .paragraphStyle: bodyStyle()
            ]
        )
        let ns = currentText as NSString
        var location = 0
        var inCode = false
        for line in currentText.components(separatedBy: "\n") {
            let length = (line as NSString).length
            let range = NSRange(location: location, length: length)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inCode.toggle()
                if length > 0 { attributed.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), range: range) }
            } else if inCode {
                if length > 0 { attributed.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), range: range) }
            } else if trimmed.hasPrefix("#") {
                if length > 0 { attributed.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 18), range: range) }
            } else if trimmed.range(of: #"^(?:[-*+]\s+|\d+[.)]\s+)"#, options: .regularExpression) != nil {
                let style = bodyStyle(); style.headIndent = 22; style.firstLineHeadIndent = 6
                if length > 0 { attributed.addAttribute(.paragraphStyle, value: style, range: range) }
            } else if trimmed.hasPrefix(">") {
                let style = bodyStyle(); style.headIndent = 24; style.firstLineHeadIndent = 12
                if length > 0 { attributed.addAttribute(.paragraphStyle, value: style, range: range) }
            }
            location += length
            if location < ns.length { location += 1 }
        }
        let fullRange = NSRange(location: 0, length: attributed.length)
        let rtf = (try? attributed.data(
            from: fullRange,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )) ?? Data()
        return TranslationClipboardPayload(plainText: currentText, rtf: rtf)
    }

    static func make(currentAttributedText: NSAttributedString) -> TranslationClipboardPayload {
        let fullRange = NSRange(location: 0, length: currentAttributedText.length)
        let rtf = (try? currentAttributedText.data(
            from: fullRange,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )) ?? Data()
        return TranslationClipboardPayload(plainText: currentAttributedText.string, rtf: rtf)
    }

    private static func bodyStyle() -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        style.paragraphSpacing = 8
        return style
    }
}
