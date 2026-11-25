import Foundation

// Azure Translator 简单长度分片的纯值黑盒契约测试。
// 所有正文均为虚构样本；不读取配置、不访问网络、剪贴板或 Keychain。
//
// 预期最小运行命令：
//   swiftc -parse-as-library -o /tmp/glint_translation_text_batching_contract_test \
//     TranslationFormatting.swift TranslationDocument.swift TranslationContentValidator.swift \
//     Config.swift SecureCredentialStore.swift ScreenshotHotKey.swift TextCommandHotKey.swift HotKey.swift \
//     TranslationAIService.swift TranslationBlockRenderer.swift TranslationService.swift \
//     translation_text_batching_contract_tests.swift \
//     -framework AppKit -framework Carbon -framework Security \
//     && /tmp/glint_translation_text_batching_contract_test

enum TranslationTextBatchingContractTestSupport {
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

final class TestTranslationTextBatchingNormalDocument {
    static func test_textWithinBudget_staysInOneUnchangedChunk() {
        let input = "Fictional subject\r\n\r\nLine with CASE-2141.  \n"
        let chunks = translationTextChunks(input, maximumCharacters: 200)

        TranslationTextBatchingContractTestSupport.expect(
            chunks == [input],
            "TestTranslationTextBatchingNormalDocument.test_textWithinBudget_staysInOneUnchangedChunk"
        )
    }
}

final class TestTranslationTextBatchingLongDocument {
    static func test_textOverBudget_prefersLastBlankLineBeforeSingleNewline() {
        let input = "AAAA\n\nBBBBBBBB\nCCCCCCCC\nDDDD"
        let chunks = translationTextChunks(input, maximumCharacters: 20)

        TranslationTextBatchingContractTestSupport.expect(
            chunks.first == "AAAA\n\n"
                && chunks.joined() == input
                && chunks.allSatisfy { !$0.isEmpty && $0.count <= 20 },
            "TestTranslationTextBatchingLongDocument.test_textOverBudget_prefersLastBlankLineBeforeSingleNewline"
        )
    }

    static func test_textWithoutBlankLine_prefersLastNewlineBeforeHardLimit() {
        let input = "AAAAAA\nBBBBBB\nCCCCCC\nDDDDDD"
        let chunks = translationTextChunks(input, maximumCharacters: 15)

        TranslationTextBatchingContractTestSupport.expect(
            chunks.first == "AAAAAA\nBBBBBB\n"
                && chunks.joined() == input
                && chunks.allSatisfy { !$0.isEmpty && $0.count <= 15 },
            "TestTranslationTextBatchingLongDocument.test_textWithoutBlankLine_prefersLastNewlineBeforeHardLimit"
        )
    }

    static func test_textWithoutLineBreaks_hardSplitsAndReassemblesInOriginalOrder() {
        let input = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let chunks = translationTextChunks(input, maximumCharacters: 10)

        TranslationTextBatchingContractTestSupport.expect(
            chunks == ["ABCDEFGHIJ", "KLMNOPQRST", "UVWXYZ0123", "456789"]
                && chunks.joined() == input,
            "TestTranslationTextBatchingLongDocument.test_textWithoutLineBreaks_hardSplitsAndReassemblesInOriginalOrder"
        )
    }
}

@main
enum TranslationTextBatchingContractTests {
    static func main() {
        TestTranslationTextBatchingNormalDocument.test_textWithinBudget_staysInOneUnchangedChunk()
        TestTranslationTextBatchingLongDocument.test_textOverBudget_prefersLastBlankLineBeforeSingleNewline()
        TestTranslationTextBatchingLongDocument.test_textWithoutBlankLine_prefersLastNewlineBeforeHardLimit()
        TestTranslationTextBatchingLongDocument.test_textWithoutLineBreaks_hardSplitsAndReassemblesInOriginalOrder()

        print(
            TranslationTextBatchingContractTestSupport.failures == 0
                ? "ALL PASS"
                : "\(TranslationTextBatchingContractTestSupport.failures) FAILURES"
        )
        exit(TranslationTextBatchingContractTestSupport.failures == 0 ? 0 : 1)
    }
}
