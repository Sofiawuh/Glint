import Foundation

// 已有邮件结构、Unicode 项目符号与签名边界黑盒契约测试。
// 所有正文均为虚构样本，不读取剪贴板。
//
// 预期最小运行命令：
//   swiftc -o /tmp/glint_translation_structure_preservation_contract_test \
//     TranslationFormatting.swift translation_structure_preservation_contract_tests.swift \
//     -framework Foundation \
//     && /tmp/glint_translation_structure_preservation_contract_test

enum TranslationStructurePreservationContractTestSupport {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() {
            print("  ok  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
        }
    }
}

final class TestExistingMailStructurePreservation {
    static func test_standardMailWithBlankLinesAndSignature_preservesExistingReadingHierarchy() {
        let mail = """
        From: sender@example.invalid
        To: reviewer@example.invalid
        Subject: Fictional migration CASE-2141

        Hi Reviewer,

        The first paragraph is already complete.

        The second paragraph is also already complete.

        Best regards,
        Fictional Sender
        """

        let formatted = SmartTranslationFormatter.format(mail, mode: .smart)

        TranslationStructurePreservationContractTestSupport.expect(
            formatted == mail,
            "TestExistingMailStructurePreservation.test_standardMailWithBlankLinesAndSignature_preservesExistingReadingHierarchy"
        )
    }
}

final class TestUnicodeListStructurePreservation {
    static func test_consecutiveUnicodeBullets_remainIndependentFromParagraphsAndEachOther() {
        let source = """
        Fictional action items:

        • Keep case CASE-2141 unchanged
        ◦ Keep nested note 42 unchanged
        ▪ Keep USD 1,234.50 unchanged
        ‣ Keep 2026-12-01 unchanged
        – Keep https://example.invalid/cases/2141 unchanged

        Best regards,
        Fictional Sender
        """

        let formatted = SmartTranslationFormatter.format(source, mode: .smart)

        TranslationStructurePreservationContractTestSupport.expect(
            formatted == source
                && formatted.components(separatedBy: "\n").filter { line in
                    ["•", "◦", "▪", "‣", "–"].contains { line.hasPrefix($0) }
                }.count == 5,
            "TestUnicodeListStructurePreservation.test_consecutiveUnicodeBullets_remainIndependentFromParagraphsAndEachOther"
        )
    }

    static func test_strictMode_onlyNormalizesLineEndingsAndTrailingWhitespace() {
        let source = "Hi Reviewer,  \r\n\r\n• First item  \r\n◦ Nested item\t\r\n\r\nBest regards,\r\nFictional Sender"
        let expected = "Hi Reviewer,\n\n• First item\n◦ Nested item\n\nBest regards,\nFictional Sender"

        let formatted = SmartTranslationFormatter.format(source, mode: .strict)

        TranslationStructurePreservationContractTestSupport.expect(
            formatted == expected,
            "TestUnicodeListStructurePreservation.test_strictMode_onlyNormalizesLineEndingsAndTrailingWhitespace"
        )
    }
}

@main
enum TranslationStructurePreservationContractTests {
    static func main() {
        TestExistingMailStructurePreservation.test_standardMailWithBlankLinesAndSignature_preservesExistingReadingHierarchy()
        TestUnicodeListStructurePreservation.test_consecutiveUnicodeBullets_remainIndependentFromParagraphsAndEachOther()
        TestUnicodeListStructurePreservation.test_strictMode_onlyNormalizesLineEndingsAndTrailingWhitespace()

        print(
            TranslationStructurePreservationContractTestSupport.failures == 0
                ? "ALL PASS"
                : "\(TranslationStructurePreservationContractTestSupport.failures) FAILURES"
        )
        exit(TranslationStructurePreservationContractTestSupport.failures == 0 ? 0 : 1)
    }
}
