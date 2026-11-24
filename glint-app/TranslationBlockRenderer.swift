import AppKit

struct TranslationRenderedReport {
    let plainText: String
    let attributedText: NSAttributedString
}

enum TranslationBlockRenderer {
    static func render(blocks: [TranslationBlock]) -> TranslationRenderedReport {
        let output = NSMutableAttributedString()
        for (index, block) in blocks.enumerated() {
            if index > 0 { output.append(NSAttributedString(string: "\n\n", attributes: bodyAttributes())) }
            append(block, to: output)
        }
        return TranslationRenderedReport(plainText: output.string, attributedText: output)
    }

    private static func append(_ block: TranslationBlock, to output: NSMutableAttributedString) {
        switch block {
        case .salutation(let text):
            output.append(NSAttributedString(string: text, attributes: bodyAttributes(weight: .medium)))
        case .heading(let text):
            output.append(NSAttributedString(string: text, attributes: headingAttributes()))
        case .paragraph(let text):
            output.append(NSAttributedString(string: text, attributes: bodyAttributes()))
        case .keyPoints(let items):
            output.append(NSAttributedString(
                string: items.joined(separator: "\n"),
                attributes: keyPointAttributes()
            ))
        case .quote(let text):
            output.append(NSAttributedString(string: text, attributes: quoteAttributes()))
        case .code(let text), .table(let text):
            output.append(NSAttributedString(string: text, attributes: codeAttributes()))
        case .signature(let text):
            output.append(NSAttributedString(string: text, attributes: signatureAttributes()))
        }
    }

    private static func paragraphStyle(
        lineSpacing: CGFloat = 4,
        paragraphSpacing: CGFloat = 10,
        paragraphSpacingBefore: CGFloat = 0,
        headIndent: CGFloat = 0,
        firstLineHeadIndent: CGFloat = 0
    ) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = paragraphSpacing
        style.paragraphSpacingBefore = paragraphSpacingBefore
        style.headIndent = headIndent
        style.firstLineHeadIndent = firstLineHeadIndent
        return style
    }

    private static func bodyAttributes(weight: NSFont.Weight = .regular) -> [NSAttributedString.Key: Any] {
        return [
            .font: NSFont.systemFont(ofSize: 14.5, weight: weight),
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraphStyle()
        ]
    }

    private static func headingAttributes() -> [NSAttributedString.Key: Any] {
        return [
            .font: NSFont.systemFont(ofSize: 16.5, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle(paragraphSpacing: 12, paragraphSpacingBefore: 4)
        ]
    }

    private static func keyPointAttributes() -> [NSAttributedString.Key: Any] {
        let style = paragraphStyle(
            lineSpacing: 3,
            paragraphSpacing: 6,
            headIndent: 24,
            firstLineHeadIndent: 8
        )
        let block = NSTextBlock()
        block.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.075)
        block.setBorderColor(NSColor.systemBlue.withAlphaComponent(0.55), for: .minX)
        block.setWidth(3, type: .absoluteValueType, for: .border, edge: .minX)
        block.setWidth(8, type: .absoluteValueType, for: .padding, edge: .minX)
        block.setWidth(5, type: .absoluteValueType, for: .padding, edge: .maxX)
        block.setWidth(4, type: .absoluteValueType, for: .padding, edge: .minY)
        block.setWidth(4, type: .absoluteValueType, for: .padding, edge: .maxY)
        style.textBlocks = [block]
        return [
            .font: NSFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .backgroundColor: NSColor.systemBlue.withAlphaComponent(0.09),
            .paragraphStyle: style
        ]
    }

    private static func quoteAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle(headIndent: 18, firstLineHeadIndent: 18)
        ]
    }

    private static func codeAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.textColor,
            .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.10),
            .paragraphStyle: paragraphStyle(lineSpacing: 2, paragraphSpacing: 8, headIndent: 10, firstLineHeadIndent: 10)
        ]
    }

    private static func signatureAttributes() -> [NSAttributedString.Key: Any] {
        let style = paragraphStyle(lineSpacing: 3, paragraphSpacing: 0, paragraphSpacingBefore: 14)
        let block = NSTextBlock()
        block.setBorderColor(NSColor.separatorColor.withAlphaComponent(0.75), for: .maxY)
        block.setWidth(1, type: .absoluteValueType, for: .border, edge: .maxY)
        block.setWidth(8, type: .absoluteValueType, for: .padding, edge: .maxY)
        style.textBlocks = [block]
        return [
            .font: NSFont.systemFont(ofSize: 13.5, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: style
        ]
    }

}
