import AppKit
import Foundation

// “结构化报告”规范纯文本与 RTF 外在行为黑盒契约测试。
// 不访问系统剪贴板，只检查准备复制的纯值表示。
//
// 预期最小运行命令（生产契约存在后）：
//   swiftc -o /tmp/glint_translation_structured_report_contract_test \
//     TranslationFormatting.swift TranslationDocument.swift Config.swift \
//     ScreenshotHotKey.swift TextCommandHotKey.swift HotKey.swift \
//     TranslationAIService.swift TranslationBlockRenderer.swift TranslationClipboard.swift \
//     TranslationContentValidator.swift \
//     translation_structured_report_contract_tests.swift \
//     -framework AppKit \
//     && /tmp/glint_translation_structured_report_contract_test

enum TranslationStructuredReportContractTestSupport {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() {
            print("  ok  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
        }
    }

    static func decodedRTF(_ data: Data) -> NSAttributedString? {
        try? NSAttributedString(
            data: data,
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

final class TestTranslationStructuredReportPlainText {
    static let blocks: [TranslationBlock] = [
        .salutation("Hi Reviewer,"),
        .heading("Fictional case update"),
        .paragraph("CASE-2141 remains open."),
        .keyPoints(["Amount is USD 1,234.50", "Due date is 2026-12-01"]),
        .quote("This is a fictional explanatory note."),
        .code("let fictionalTotal = 1234.50"),
        .table("Name | Count\nWidget | 42"),
        .signature("Best regards,\nFictional Sender")
    ]

    static func test_plainText_preservesContentAndStructureWithoutDecorationLabels() {
        let report = TranslationBlockRenderer.render(blocks: blocks)

        TranslationStructuredReportContractTestSupport.expect(
            report.plainText.contains("Hi Reviewer,")
                && report.plainText.contains("Fictional case update")
                && report.plainText.contains("Amount is USD 1,234.50")
                && report.plainText.contains("Due date is 2026-12-01")
                && !report.plainText.contains("• Amount is USD 1,234.50")
                && !report.plainText.contains("1. Amount is USD 1,234.50")
                && report.plainText.contains("Best regards,\nFictional Sender")
                && !report.plainText.contains("重点清单")
                && !report.plainText.contains("邮件签名")
                && report.attributedText.string == report.plainText,
            "TestTranslationStructuredReportPlainText.test_plainText_preservesContentAndStructureWithoutDecorationLabels"
        )
    }
}

final class TestTranslationStructuredReportFaithfulKeyPoints {
    static func test_unmarkedKeyPoints_doNotGainMarkersAndPassSmartCharacterValidation() {
        let original = "Please approve CASE-2141\nReply by 2026-12-01"
        let report = TranslationBlockRenderer.render(blocks: [
            .keyPoints(original.components(separatedBy: "\n"))
        ])

        TranslationStructuredReportContractTestSupport.expect(
            report.plainText == original
                && report.attributedText.string == original
                && TranslationContentValidator.isFormattingFaithful(
                    original: original,
                    candidate: report.plainText
                ),
            "TestTranslationStructuredReportFaithfulKeyPoints.test_unmarkedKeyPoints_doNotGainMarkersAndPassSmartCharacterValidation"
        )
    }

    static func test_existingBulletAndNumberMarkers_remainExactlyUnchanged() {
        let original = "• Keep CASE-2141\n2) Reply by 2026-12-01"
        let report = TranslationBlockRenderer.render(blocks: [
            .keyPoints(original.components(separatedBy: "\n"))
        ])

        TranslationStructuredReportContractTestSupport.expect(
            report.plainText == original
                && report.attributedText.string == original
                && TranslationContentValidator.isFormattingFaithful(
                    original: original,
                    candidate: report.plainText
                ),
            "TestTranslationStructuredReportFaithfulKeyPoints.test_existingBulletAndNumberMarkers_remainExactlyUnchanged"
        )
    }
}

final class TestTranslationStructuredReportRTF {
    static func test_rtfCopy_preservesNativeHeadingKeyPointsAndSignatureHierarchy() {
        let report = TranslationBlockRenderer.render(blocks: TestTranslationStructuredReportPlainText.blocks)
        let payload = TranslationClipboardPayload.make(currentAttributedText: report.attributedText)
        guard let decoded = TranslationStructuredReportContractTestSupport.decodedRTF(payload.rtf),
              let heading = TranslationStructuredReportContractTestSupport.attributes(
                containing: "Fictional case update",
                in: decoded
              ),
              let point = TranslationStructuredReportContractTestSupport.attributes(
                containing: "Amount is USD 1,234.50",
                in: decoded
              ),
              let signature = TranslationStructuredReportContractTestSupport.attributes(
                containing: "Fictional Sender",
                in: decoded
              ),
              let headingFont = heading[.font] as? NSFont,
              let pointStyle = point[.paragraphStyle] as? NSParagraphStyle,
              let signatureStyle = signature[.paragraphStyle] as? NSParagraphStyle else {
            TranslationStructuredReportContractTestSupport.expect(
                false,
                "TestTranslationStructuredReportRTF.test_rtfCopy_preservesNativeHeadingKeyPointsAndSignatureHierarchy"
            )
            return
        }

        let contentMatches = payload.plainText == report.plainText
            && decoded.string == report.plainText
            && !decoded.string.contains("重点清单")
        let hierarchyMatches = headingFont.fontDescriptor.symbolicTraits.contains(.bold)
            && pointStyle.headIndent > 0
            && point[.backgroundColor] is NSColor
            && signatureStyle.paragraphSpacingBefore > 0
            && signature[.foregroundColor] is NSColor

        TranslationStructuredReportContractTestSupport.expect(
            contentMatches && hierarchyMatches,
            "TestTranslationStructuredReportRTF.test_rtfCopy_preservesNativeHeadingKeyPointsAndSignatureHierarchy"
        )
    }
}

@main
enum TranslationStructuredReportContractTests {
    static func main() {
        TestTranslationStructuredReportPlainText.test_plainText_preservesContentAndStructureWithoutDecorationLabels()
        TestTranslationStructuredReportFaithfulKeyPoints.test_unmarkedKeyPoints_doNotGainMarkersAndPassSmartCharacterValidation()
        TestTranslationStructuredReportFaithfulKeyPoints.test_existingBulletAndNumberMarkers_remainExactlyUnchanged()
        TestTranslationStructuredReportRTF.test_rtfCopy_preservesNativeHeadingKeyPointsAndSignatureHierarchy()

        print(
            TranslationStructuredReportContractTestSupport.failures == 0
                ? "ALL PASS"
                : "\(TranslationStructuredReportContractTestSupport.failures) FAILURES"
        )
        exit(TranslationStructuredReportContractTestSupport.failures == 0 ? 0 : 1)
    }
}
