import Foundation

// 智能排版纯文本输入输出黑盒契约测试（不进入 App 打包）。
//
// 预期最小运行命令（生产契约存在后）：
//   swiftc -o /tmp/glint_translation_formatting_contract_test \
//     TranslationFormatting.swift translation_formatting_contract_tests.swift \
//     -framework Foundation && /tmp/glint_translation_formatting_contract_test

enum TranslationFormattingContractTestSupport {
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

final class TestSmartTranslationFormatting {
    static func test_existingOrdinaryLineBreaks_preserveSourceStructureWordsNumbersAndURL() {
        let input = """
        The fictional invoice total is USD 1,234.50 and the details are
        available at https://example.invalid/invoices/42 for review before
        2026-12-01.
        """

        let formatted = SmartTranslationFormatter.format(input, mode: .smart)

        TranslationFormattingContractTestSupport.expect(
            formatted == input,
            "TestSmartTranslationFormatting.test_existingOrdinaryLineBreaks_preserveSourceStructureWordsNumbersAndURL"
        )
    }

    static func test_sourceAndTranslation_smartAndPolishPreserveEachSidesExistingLines() {
        let source = "A synthetic paragraph wraps\nacross two visual lines."
        let translation = "这是一个虚构段落，因视觉宽度而\n被分成了两行。"

        let smartSource = SmartTranslationFormatter.format(source, mode: .smart)
        let smartTranslation = SmartTranslationFormatter.format(translation, mode: .smart)
        let polishSource = SmartTranslationFormatter.format(source, mode: .polish)
        let polishTranslation = SmartTranslationFormatter.format(translation, mode: .polish)

        TranslationFormattingContractTestSupport.expect(
            smartSource == source
                && smartTranslation == translation
                && polishSource == source
                && polishTranslation == translation,
            "TestSmartTranslationFormatting.test_sourceAndTranslation_smartAndPolishPreserveEachSidesExistingLines"
        )
    }

    static func test_structuredBlocks_preserveBlankLinesMailHeadersSignatureHeadingListQuoteCodeAndTable() {
        let input = """
        # Synthetic Release Notes

        From: alice@example.invalid
        To: team@example.invalid
        Subject: Fictional rollout

        The first prose line already has
        a source-provided line boundary.

        • Keep the first item
        ◦ Keep the nested item
        ▪ Keep the third item
        ‣ Keep the fourth item
        – Keep the fifth item

        > Quoted line one
        > Quoted line two

        | Name | Count |
        | --- | --- |
        | Widget | 2 |

        ```swift
        let fictionalKey = "not-a-real-key"
        print(fictionalKey)
        ```

        --\u{20}
        Alice Example
        """
        let expected = """
        # Synthetic Release Notes

        From: alice@example.invalid
        To: team@example.invalid
        Subject: Fictional rollout

        The first prose line already has
        a source-provided line boundary.

        • Keep the first item
        ◦ Keep the nested item
        ▪ Keep the third item
        ‣ Keep the fourth item
        – Keep the fifth item

        > Quoted line one
        > Quoted line two

        | Name | Count |
        | --- | --- |
        | Widget | 2 |

        ```swift
        let fictionalKey = "not-a-real-key"
        print(fictionalKey)
        ```

        --
        Alice Example
        """

        let formatted = SmartTranslationFormatter.format(input, mode: .smart)

        TranslationFormattingContractTestSupport.expect(
            formatted == expected,
            "TestSmartTranslationFormatting.test_structuredBlocks_preserveBlankLinesMailHeadersSignatureHeadingListQuoteCodeAndTable"
        )
    }
}

final class TestStrictTranslationFormatting {
    static func test_strictMode_normalizesNewlinesAndTrailingSpacesWithoutMergingOrRestructuring() {
        let input = "Title  \r\nFirst hard-wrapped line   \r\ncontinues here\t\r\n\r\n- item one  \r\n- item two\r\n"
        let formatted = SmartTranslationFormatter.format(input, mode: .strict)

        TranslationFormattingContractTestSupport.expect(
            formatted == "Title\nFirst hard-wrapped line\ncontinues here\n\n- item one\n- item two\n",
            "TestStrictTranslationFormatting.test_strictMode_normalizesNewlinesAndTrailingSpacesWithoutMergingOrRestructuring"
        )
    }
}

@main
enum TranslationFormattingContractTests {
    static func main() {
        TestSmartTranslationFormatting.test_existingOrdinaryLineBreaks_preserveSourceStructureWordsNumbersAndURL()
        TestSmartTranslationFormatting.test_sourceAndTranslation_smartAndPolishPreserveEachSidesExistingLines()
        TestSmartTranslationFormatting.test_structuredBlocks_preserveBlankLinesMailHeadersSignatureHeadingListQuoteCodeAndTable()
        TestStrictTranslationFormatting.test_strictMode_normalizesNewlinesAndTrailingSpacesWithoutMergingOrRestructuring()

        print(
            TranslationFormattingContractTestSupport.failures == 0
                ? "ALL PASS"
                : "\(TranslationFormattingContractTestSupport.failures) FAILURES"
        )
        exit(TranslationFormattingContractTestSupport.failures == 0 ? 0 : 1)
    }
}
