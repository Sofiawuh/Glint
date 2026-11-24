import AppKit
import Foundation

// 翻译工作台推荐高度的公开纯值黑盒契约。
// 所有正文均为完全虚构样本；不读取屏幕、用户配置、Keychain、邮件或剪贴板。
//
// 本机没有仓库要求的 harness 命令，使用 perl alarm 提供等价总超时：
//   perl -e 'alarm 120; exec @ARGV' -- \
//     swiftc -parse-as-library -o /tmp/glint_translation_workspace_layout_policy_contract_test \
//       TranslationFormatting.swift TranslationDocument.swift TranslationWorkbench.swift \
//       RecentResults.swift TranslationClipboard.swift Markdown.swift TranslationWorkspaceView.swift \
//       TranslationAIService.swift TranslationBlockRenderer.swift \
//       Config.swift ScreenshotHotKey.swift TextCommandHotKey.swift HotKey.swift \
//       translation_workspace_layout_policy_contract_tests.swift \
//       -framework AppKit -framework Carbon
//   perl -e 'alarm 30; exec @ARGV' -- /tmp/glint_translation_workspace_layout_policy_contract_test

enum TranslationWorkspaceLayoutPolicyContractTestSupport {
    static var failures = 0

    static func lines(_ count: Int, prefix: String) -> String {
        (1...count)
            .map { "\(prefix) \($0)." }
            .joined(separator: "\n")
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ name: String, detail: String = "") {
        if condition() {
            print("  ok  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        }
    }

    static func preferred(source: String, translation: String) -> CGFloat {
        TranslationWorkspaceView.preferredHeight(source: source, translation: translation)
    }
}

final class TestTranslationWorkspaceRecommendedHeight {
    static func test_shortMediumAndLongContent_produceContinuousBoundedHeights() {
        let short = TranslationWorkspaceLayoutPolicyContractTestSupport.preferred(
            source: "Synthetic short note.",
            translation: "虚构短译文。"
        )
        let medium = TranslationWorkspaceLayoutPolicyContractTestSupport.preferred(
            source: TranslationWorkspaceLayoutPolicyContractTestSupport.lines(24, prefix: "Synthetic medium line"),
            translation: TranslationWorkspaceLayoutPolicyContractTestSupport.lines(18, prefix: "虚构中等译文行")
        )
        let long = TranslationWorkspaceLayoutPolicyContractTestSupport.preferred(
            source: TranslationWorkspaceLayoutPolicyContractTestSupport.lines(80, prefix: "Synthetic long line"),
            translation: TranslationWorkspaceLayoutPolicyContractTestSupport.lines(72, prefix: "虚构长译文行")
        )

        TranslationWorkspaceLayoutPolicyContractTestSupport.expect(
            short == 430 && medium == 510 && long == 760,
            "TestTranslationWorkspaceRecommendedHeight.test_shortMediumAndLongContent_produceContinuousBoundedHeights",
            detail: "expected [430, 510, 760], actual [\(short), \(medium), \(long)]"
        )
    }

    static func test_adjacentVisualLineDemand_quantizesUpwardInTenPointSteps() {
        let twentyFiveLines = TranslationWorkspaceLayoutPolicyContractTestSupport.preferred(
            source: TranslationWorkspaceLayoutPolicyContractTestSupport.lines(25, prefix: "Synthetic line"),
            translation: "虚构译文。"
        )
        let twentySixLines = TranslationWorkspaceLayoutPolicyContractTestSupport.preferred(
            source: TranslationWorkspaceLayoutPolicyContractTestSupport.lines(26, prefix: "Synthetic line"),
            translation: "虚构译文。"
        )

        TranslationWorkspaceLayoutPolicyContractTestSupport.expect(
            twentyFiveLines == 520
                && twentySixLines == 530
                && twentyFiveLines.truncatingRemainder(dividingBy: 10) == 0
                && twentySixLines.truncatingRemainder(dividingBy: 10) == 0,
            "TestTranslationWorkspaceRecommendedHeight.test_adjacentVisualLineDemand_quantizesUpwardInTenPointSteps",
            detail: "expected [520, 530], actual [\(twentyFiveLines), \(twentySixLines)]"
        )
    }

    static func test_longContentOnSmallScreen_respectsTwentyFourPointSafetyMargin() {
        let source = TranslationWorkspaceLayoutPolicyContractTestSupport.lines(80, prefix: "Synthetic constrained line")
        let translation = TranslationWorkspaceLayoutPolicyContractTestSupport.lines(80, prefix: "虚构受限译文行")
        let height = TranslationWorkspaceView.initialPresentationHeight(
            source: source,
            translation: translation,
            savedHeight: 430,
            availableHeight: 500
        )

        TranslationWorkspaceLayoutPolicyContractTestSupport.expect(
            height == 476,
            "TestTranslationWorkspaceRecommendedHeight.test_longContentOnSmallScreen_respectsTwentyFourPointSafetyMargin",
            detail: "expected 476, actual \(height)"
        )
    }

    static func test_newShortTranslation_doesNotInheritUnrelatedSavedPopupHeight() {
        let height = TranslationWorkspaceView.initialPresentationHeight(
            source: "Synthetic short note.",
            translation: "虚构短译文。",
            savedHeight: 700,
            availableHeight: 900
        )

        TranslationWorkspaceLayoutPolicyContractTestSupport.expect(
            height == 430,
            "TestTranslationWorkspaceRecommendedHeight.test_newShortTranslation_doesNotInheritUnrelatedSavedPopupHeight",
            detail: "expected 430, actual \(height)"
        )
    }
}

@main
enum TranslationWorkspaceLayoutPolicyContractTests {
    static func main() {
        _ = NSApplication.shared
        TestTranslationWorkspaceRecommendedHeight.test_shortMediumAndLongContent_produceContinuousBoundedHeights()
        TestTranslationWorkspaceRecommendedHeight.test_adjacentVisualLineDemand_quantizesUpwardInTenPointSteps()
        TestTranslationWorkspaceRecommendedHeight.test_longContentOnSmallScreen_respectsTwentyFourPointSafetyMargin()
        TestTranslationWorkspaceRecommendedHeight.test_newShortTranslation_doesNotInheritUnrelatedSavedPopupHeight()

        print(
            TranslationWorkspaceLayoutPolicyContractTestSupport.failures == 0
                ? "ALL PASS"
                : "\(TranslationWorkspaceLayoutPolicyContractTestSupport.failures) FAILURES"
        )
        exit(TranslationWorkspaceLayoutPolicyContractTestSupport.failures == 0 ? 0 : 1)
    }
}
