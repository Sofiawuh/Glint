import Foundation

// AI 排版字符忠实与智能润色事实保护黑盒契约测试。
// 正文、标识符、URL、邮箱、IP 和路径均为虚构样本。
//
// 预期最小运行命令（生产契约存在后）：
//   swiftc -parse-as-library -o /tmp/glint_translation_content_validation_contract_test \
//     TranslationContentValidator.swift translation_content_validation_contract_tests.swift \
//     -framework Foundation \
//     && /tmp/glint_translation_content_validation_contract_test

enum TranslationContentValidationContractTestSupport {
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

final class TestTranslationFormattingFaithfulness {
    static func test_onlyUnicodeWhitespaceChanged_isAccepted() {
        let original = "Fictional customer.In addition CASE-2141 costs USD 1,234.50."
        let candidate = "Fictional customer.\nIn\u{00A0}addition CASE-2141 costs USD 1,234.50."

        TranslationContentValidationContractTestSupport.expect(
            TranslationContentValidator.isFormattingFaithful(
                original: original,
                candidate: candidate
            ),
            "TestTranslationFormattingFaithfulness.test_onlyUnicodeWhitespaceChanged_isAccepted"
        )
    }

    static func test_nonWhitespaceCharacterAddedRemovedChangedOrReordered_isRejected() {
        let original = "CASE-2141 costs USD 1,234.50 on 2026-12-01."
        let candidates = [
            "CASE-2142 costs USD 1,234.50 on 2026-12-01.",
            "CASE-2141 costs USD 1,234.50.",
            "CASE-2141 costs only USD 1,234.50 on 2026-12-01.",
            "USD 1,234.50 costs CASE-2141 on 2026-12-01."
        ]

        TranslationContentValidationContractTestSupport.expect(
            candidates.allSatisfy {
                !TranslationContentValidator.isFormattingFaithful(original: original, candidate: $0)
            },
            "TestTranslationFormattingFaithfulness.test_nonWhitespaceCharacterAddedRemovedChangedOrReordered_isRejected"
        )
    }
}

final class TestTranslationPolishFactProtection {
    static let original = """
    Fictional Sender at Fictional Labs opened CASE-2141 on 2026-12-01 09:30.
    Amount: USD 1,234.50 (42%). Contact sender@example.invalid.
    URL: https://example.invalid/cases/CASE-2141
    Host: 192.0.2.42 Path: /tmp/FictionalReport.swift Variable: fictionalTotal
    • First fact remains first
    • Second fact remains second
    """

    static func test_rewordedTextKeepingProtectedFactsCountsAndListOrder_isAccepted() {
        let candidate = """
        On 2026-12-01 09:30, Fictional Sender of Fictional Labs opened CASE-2141.
        The amount is USD 1,234.50 (42%); contact sender@example.invalid.
        See https://example.invalid/cases/CASE-2141 on 192.0.2.42.
        Use /tmp/FictionalReport.swift and fictionalTotal.
        • First fact remains first
        • Second fact remains second
        """

        TranslationContentValidationContractTestSupport.expect(
            TranslationContentValidator.preservesProtectedFacts(
                original: original,
                candidate: candidate
            ),
            "TestTranslationPolishFactProtection.test_rewordedTextKeepingProtectedFactsCountsAndListOrder_isAccepted"
        )
    }

    static func test_missingChangedDuplicatedFactsOrReorderedList_isRejected() {
        let candidates = [
            original.replacingOccurrences(of: "USD 1,234.50", with: "USD 1,234.00"),
            original.replacingOccurrences(of: "sender@example.invalid", with: ""),
            original.replacingOccurrences(of: "CASE-2141", with: "CASE-2142"),
            original.replacingOccurrences(
                of: "• First fact remains first\n• Second fact remains second",
                with: "• Second fact remains second\n• First fact remains first"
            )
        ]

        TranslationContentValidationContractTestSupport.expect(
            candidates.allSatisfy {
                !TranslationContentValidator.preservesProtectedFacts(original: original, candidate: $0)
            },
            "TestTranslationPolishFactProtection.test_missingChangedDuplicatedFactsOrReorderedList_isRejected"
        )
    }

    static func test_plainNamesOrganizationsAndResourceNames_areProtectedWithoutIdentifiers() {
        let cases = [
            (
                original: "Alice will notify Orbit about the Redwood migration.",
                candidate: "Bob will notify Orbit about the Redwood migration."
            ),
            (
                original: "张伟将联系星河数据平台的李娜。",
                candidate: "王强将联系星河数据平台的李娜。"
            ),
            (
                original: "请由李娜检查星河数据平台和北辰网关。",
                candidate: "请由李娜检查云海数据平台和北辰网关。"
            )
        ]

        TranslationContentValidationContractTestSupport.expect(
            cases.allSatisfy {
                !TranslationContentValidator.preservesProtectedFacts(
                    original: $0.original,
                    candidate: $0.candidate
                )
            },
            "TestTranslationPolishFactProtection.test_plainNamesOrganizationsAndResourceNames_areProtectedWithoutIdentifiers"
        )
    }

    static func test_plainLanguageListItems_reorderedWithoutProtectedTokens_areRejected() {
        let original = """
        • Restart the service
        • Notify the owner
        • Archive the report
        """
        let reordered = """
        • Notify the owner
        • Restart the service
        • Archive the report
        """

        TranslationContentValidationContractTestSupport.expect(
            !TranslationContentValidator.preservesProtectedFacts(
                original: original,
                candidate: reordered
            ),
            "TestTranslationPolishFactProtection.test_plainLanguageListItems_reorderedWithoutProtectedTokens_areRejected"
        )
    }

    static func test_chineseCopulaNamesChanged_areRejected() {
        let original = "张伟是项目负责人，李娜是客户代表。"
        let changed = "王强是项目负责人，赵敏是客户代表。"

        TranslationContentValidationContractTestSupport.expect(
            !TranslationContentValidator.preservesProtectedFacts(
                original: original,
                candidate: changed
            ),
            "TestTranslationPolishFactProtection.test_chineseCopulaNamesChanged_areRejected"
        )
    }

    static func test_listItemsSharingGenericWords_reorderedFactsAreRejected() {
        let original = """
        • Restart production service
        • Restart staging service
        """
        let reordered = """
        • Restart staging service
        • Restart production service
        """

        TranslationContentValidationContractTestSupport.expect(
            !TranslationContentValidator.preservesProtectedFacts(
                original: original,
                candidate: reordered
            ),
            "TestTranslationPolishFactProtection.test_listItemsSharingGenericWords_reorderedFactsAreRejected"
        )
    }

    static func test_ordinarySentenceOpeningWord_canBePolishedWithoutFalseEntityRejection() {
        let original = "Customers expect faster service."
        let candidate = "Clients expect faster service."

        TranslationContentValidationContractTestSupport.expect(
            TranslationContentValidator.preservesProtectedFacts(
                original: original,
                candidate: candidate
            ),
            "TestTranslationPolishFactProtection.test_ordinarySentenceOpeningWord_canBePolishedWithoutFalseEntityRejection"
        )
    }
}

@main
enum TranslationContentValidationContractTests {
    static func main() {
        TestTranslationFormattingFaithfulness.test_onlyUnicodeWhitespaceChanged_isAccepted()
        TestTranslationFormattingFaithfulness.test_nonWhitespaceCharacterAddedRemovedChangedOrReordered_isRejected()
        TestTranslationPolishFactProtection.test_rewordedTextKeepingProtectedFactsCountsAndListOrder_isAccepted()
        TestTranslationPolishFactProtection.test_missingChangedDuplicatedFactsOrReorderedList_isRejected()
        TestTranslationPolishFactProtection.test_plainNamesOrganizationsAndResourceNames_areProtectedWithoutIdentifiers()
        TestTranslationPolishFactProtection.test_plainLanguageListItems_reorderedWithoutProtectedTokens_areRejected()
        TestTranslationPolishFactProtection.test_chineseCopulaNamesChanged_areRejected()
        TestTranslationPolishFactProtection.test_listItemsSharingGenericWords_reorderedFactsAreRejected()
        TestTranslationPolishFactProtection.test_ordinarySentenceOpeningWord_canBePolishedWithoutFalseEntityRejection()

        print(
            TranslationContentValidationContractTestSupport.failures == 0
                ? "ALL PASS"
                : "\(TranslationContentValidationContractTestSupport.failures) FAILURES"
        )
        exit(TranslationContentValidationContractTestSupport.failures == 0 ? 0 : 1)
    }
}
