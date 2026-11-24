import Foundation

// Azure GPT 长文本分批的纯值黑盒契约测试。
// 不读取 AppConfig、不创建 URLRequest、不访问网络或真实正文。
//
// 预期最小运行命令（生产契约存在后）：
//   swiftc -parse-as-library -o /tmp/glint_translation_ai_batching_contract_test \
//     TranslationFormatting.swift TranslationDocument.swift TranslationContentValidator.swift \
//     Config.swift ScreenshotHotKey.swift TextCommandHotKey.swift HotKey.swift \
//     TranslationAIService.swift TranslationBlockRenderer.swift TranslationService.swift \
//     translation_ai_batching_contract_tests.swift \
//     -framework AppKit -framework Carbon \
//     && /tmp/glint_translation_ai_batching_contract_test

enum TranslationAIBatchingContractTestSupport {
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

final class TestTranslationAISingleTextBatching {
    static func test_singleParagraphLargerThanManualBudget_isHardSplitWithoutLoss() {
        let input = String(repeating: "甲乙ABC", count: 3_000)
        let batches = singleTextBatches(input, maximumCharacters: 12_000)

        TranslationAIBatchingContractTestSupport.expect(
            batches.count > 1
                && batches.allSatisfy { !$0.isEmpty && $0.count <= 12_000 }
                && batches.joined() == input,
            "TestTranslationAISingleTextBatching.test_singleParagraphLargerThanManualBudget_isHardSplitWithoutLoss"
        )
    }

    static func test_artificialSplitInsideOneParagraph_reassemblesWithoutAddingBlankLines() {
        let input = String(repeating: "A", count: 12_001)
        let batches = singleTextBatches(input, maximumCharacters: 12_000)
        let processed = batches.map {
            TranslationAIProcessedBatch(inputText: $0, blocks: [.paragraph($0)])
        }
        let assembled = assembleAIProcessedText(
            originalText: input,
            batches: processed,
            mode: .smart
        )

        TranslationAIBatchingContractTestSupport.expect(
            batches.count == 2
                && assembled?.text == input
                && assembled?.text.contains("\n\n") == false,
            "TestTranslationAISingleTextBatching.test_artificialSplitInsideOneParagraph_reassemblesWithoutAddingBlankLines"
        )
    }
}

final class TestTranslationAIPairedTextBatching {
    static func test_twoSingleParagraphSidesLargerThanAutomaticBudget_areHardSplitAndStayAligned() {
        let source = String(repeating: "Source", count: 3_000)
        let translation = String(repeating: "译文", count: 9_000)
        let batches = pairedTextBatches(
            source: source,
            translation: translation,
            maximumCombinedCharacters: 16_000
        )

        TranslationAIBatchingContractTestSupport.expect(
            batches.count > 1
                && batches.allSatisfy {
                    !$0.source.isEmpty
                        && !$0.translation.isEmpty
                        && $0.source.count + $0.translation.count <= 16_000
                }
                && batches.map(\.source).joined() == source
                && batches.map(\.translation).joined() == translation,
            "TestTranslationAIPairedTextBatching.test_twoSingleParagraphSidesLargerThanAutomaticBudget_areHardSplitAndStayAligned"
        )
    }

    static func test_artificialPairSplits_reassembleBothSidesWithoutAddingBlankLines() {
        let source = String(repeating: "S", count: 12_001)
        let translation = String(repeating: "译", count: 12_001)
        let batches = pairedTextBatches(
            source: source,
            translation: translation,
            maximumCombinedCharacters: 16_000
        )
        let sourceResult = assembleAIProcessedText(
            originalText: source,
            batches: batches.map {
                TranslationAIProcessedBatch(inputText: $0.source, blocks: [.paragraph($0.source)])
            },
            mode: .smart
        )
        let translationResult = assembleAIProcessedText(
            originalText: translation,
            batches: batches.map {
                TranslationAIProcessedBatch(inputText: $0.translation, blocks: [.paragraph($0.translation)])
            },
            mode: .smart
        )

        TranslationAIBatchingContractTestSupport.expect(
            batches.count > 1
                && sourceResult?.text == source
                && translationResult?.text == translation
                && sourceResult?.text.contains("\n\n") == false
                && translationResult?.text.contains("\n\n") == false,
            "TestTranslationAIPairedTextBatching.test_artificialPairSplits_reassembleBothSidesWithoutAddingBlankLines"
        )
    }
}

@main
enum TranslationAIBatchingContractTests {
    static func main() {
        TestTranslationAISingleTextBatching.test_singleParagraphLargerThanManualBudget_isHardSplitWithoutLoss()
        TestTranslationAISingleTextBatching.test_artificialSplitInsideOneParagraph_reassemblesWithoutAddingBlankLines()
        TestTranslationAIPairedTextBatching.test_twoSingleParagraphSidesLargerThanAutomaticBudget_areHardSplitAndStayAligned()
        TestTranslationAIPairedTextBatching.test_artificialPairSplits_reassembleBothSidesWithoutAddingBlankLines()

        print(
            TranslationAIBatchingContractTestSupport.failures == 0
                ? "ALL PASS"
                : "\(TranslationAIBatchingContractTestSupport.failures) FAILURES"
        )
        exit(TranslationAIBatchingContractTestSupport.failures == 0 ? 0 : 1)
    }
}
