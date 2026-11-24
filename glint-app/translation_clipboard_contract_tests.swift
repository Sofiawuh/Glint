import AppKit
import Foundation

// 翻译编辑内容的纯文本 / RTF 剪贴板表示黑盒契约测试。
// 不访问 NSPasteboard，只验证准备写入剪贴板的纯值表示。
//
// 预期最小运行命令（生产契约存在后）：
//   swiftc -o /tmp/glint_translation_clipboard_contract_test \
//     TranslationClipboard.swift translation_clipboard_contract_tests.swift \
//     -framework AppKit && /tmp/glint_translation_clipboard_contract_test

enum TranslationClipboardContractTestSupport {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() {
            print("  ok  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
        }
    }

    static func attributedString(from rtf: Data) -> NSAttributedString? {
        try? NSAttributedString(
            data: rtf,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
    }

    static func attributes(containing needle: String, in text: NSAttributedString) -> [NSAttributedString.Key: Any]? {
        let range = (text.string as NSString).range(of: needle)
        guard range.location != NSNotFound else { return nil }
        return text.attributes(at: range.location, effectiveRange: nil)
    }
}

final class TestTranslationClipboardCurrentContent {
    static func test_editedContent_buildsBothRepresentationsWithoutFallingBackToCapturedText() {
        let captured = "Original captured text that must not be copied"
        let edited = "Edited first paragraph.\n\nEdited second paragraph."
        let payload = TranslationClipboardPayload.make(currentText: edited)
        let richText = TranslationClipboardContractTestSupport.attributedString(from: payload.rtf)

        TranslationClipboardContractTestSupport.expect(
            payload.plainText == edited
                && richText?.string == edited
                && !payload.plainText.contains(captured)
                && !(richText?.string.contains(captured) ?? true),
            "TestTranslationClipboardCurrentContent.test_editedContent_buildsBothRepresentationsWithoutFallingBackToCapturedText"
        )
    }
}

final class TestTranslationClipboardRichTextStructure {
    static func test_structuredCurrentText_preservesHeadingListQuoteParagraphAndMonospacedCodeInRTF() {
        let current = """
        # Synthetic Heading

        First paragraph.

        - List item

        > Quoted sentence

        ```swift
        let fictionalValue = 42
        ```
        """
        let payload = TranslationClipboardPayload.make(currentText: current)
        guard let richText = TranslationClipboardContractTestSupport.attributedString(from: payload.rtf),
              let heading = TranslationClipboardContractTestSupport.attributes(containing: "Synthetic Heading", in: richText),
              let list = TranslationClipboardContractTestSupport.attributes(containing: "List item", in: richText),
              let quote = TranslationClipboardContractTestSupport.attributes(containing: "Quoted sentence", in: richText),
              let code = TranslationClipboardContractTestSupport.attributes(containing: "fictionalValue", in: richText),
              let headingFont = heading[.font] as? NSFont,
              let codeFont = code[.font] as? NSFont,
              let listStyle = list[.paragraphStyle] as? NSParagraphStyle,
              let quoteStyle = quote[.paragraphStyle] as? NSParagraphStyle else {
            TranslationClipboardContractTestSupport.expect(
                false,
                "TestTranslationClipboardRichTextStructure.test_structuredCurrentText_preservesHeadingListQuoteParagraphAndMonospacedCodeInRTF"
            )
            return
        }

        TranslationClipboardContractTestSupport.expect(
            payload.plainText == current
                && richText.string == current
                && headingFont.fontDescriptor.symbolicTraits.contains(.bold)
                && headingFont.pointSize > NSFont.systemFontSize
                && listStyle.headIndent > 0
                && quoteStyle.headIndent > 0
                && codeFont.fontDescriptor.symbolicTraits.contains(.monoSpace),
            "TestTranslationClipboardRichTextStructure.test_structuredCurrentText_preservesHeadingListQuoteParagraphAndMonospacedCodeInRTF"
        )
    }
}

@main
enum TranslationClipboardContractTests {
    static func main() {
        TestTranslationClipboardCurrentContent.test_editedContent_buildsBothRepresentationsWithoutFallingBackToCapturedText()
        TestTranslationClipboardRichTextStructure.test_structuredCurrentText_preservesHeadingListQuoteParagraphAndMonospacedCodeInRTF()

        print(
            TranslationClipboardContractTestSupport.failures == 0
                ? "ALL PASS"
                : "\(TranslationClipboardContractTestSupport.failures) FAILURES"
        )
        exit(TranslationClipboardContractTestSupport.failures == 0 ? 0 : 1)
    }
}
