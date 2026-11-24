import AppKit
import Foundation

// 翻译工作台初始面板高度选择的纯值黑盒契约测试。
// 所有正文均为虚构样本；不读取屏幕、用户配置、Keychain、邮件或剪贴板。
//
// 预期最小运行命令（生产契约存在后）：
//   swiftc -parse-as-library -o /tmp/glint_translation_workspace_layout_policy_contract_test \
//     TranslationFormatting.swift TranslationDocument.swift TranslationWorkbench.swift \
//     RecentResults.swift TranslationClipboard.swift Markdown.swift TranslationWorkspaceView.swift \
//     TranslationAIService.swift TranslationBlockRenderer.swift \
//     Config.swift ScreenshotHotKey.swift TextCommandHotKey.swift HotKey.swift \
//     translation_workspace_layout_policy_contract_tests.swift \
//     -framework AppKit -framework Carbon \
//     && /tmp/glint_translation_workspace_layout_policy_contract_test

enum TranslationWorkspaceLayoutPolicyContractTestSupport {
    static var failures = 0

    static let longSource = (1...80)
        .map { "Synthetic source paragraph \($0) for layout verification." }
        .joined(separator: "\n")
    static let longTranslation = (1...80)
        .map { "虚构译文段落 \($0)，仅用于布局验证。" }
        .joined(separator: "\n")

    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() {
            print("  ok  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
        }
    }

    static func initialHeight(savedHeight: CGFloat, availableHeight: CGFloat) -> CGFloat {
        TranslationWorkspaceView.initialPresentationHeight(
            source: longSource,
            translation: longTranslation,
            savedHeight: savedHeight,
            availableHeight: availableHeight
        )
    }
}

final class TestTranslationWorkspaceInitialPresentationHeight {
    static func test_longContentWithShallowSavedHeight_uses760PointTarget() {
        let height = TranslationWorkspaceLayoutPolicyContractTestSupport.initialHeight(
            savedHeight: 570,
            availableHeight: 900
        )

        TranslationWorkspaceLayoutPolicyContractTestSupport.expect(
            height == 760,
            "TestTranslationWorkspaceInitialPresentationHeight.test_longContentWithShallowSavedHeight_uses760PointTarget"
        )
    }

    static func test_longContentWithLargerSavedHeight_preservesUserHeight() {
        let height = TranslationWorkspaceLayoutPolicyContractTestSupport.initialHeight(
            savedHeight: 820,
            availableHeight: 900
        )

        TranslationWorkspaceLayoutPolicyContractTestSupport.expect(
            height == 820,
            "TestTranslationWorkspaceInitialPresentationHeight.test_longContentWithLargerSavedHeight_preservesUserHeight"
        )
    }

    static func test_longContentOnSmallScreen_capsHeightAt24PointSafetyMargin() {
        let height = TranslationWorkspaceLayoutPolicyContractTestSupport.initialHeight(
            savedHeight: 820,
            availableHeight: 700
        )

        TranslationWorkspaceLayoutPolicyContractTestSupport.expect(
            height == 676,
            "TestTranslationWorkspaceInitialPresentationHeight.test_longContentOnSmallScreen_capsHeightAt24PointSafetyMargin"
        )
    }
}

@main
enum TranslationWorkspaceLayoutPolicyContractTests {
    static func main() {
        _ = NSApplication.shared
        TestTranslationWorkspaceInitialPresentationHeight.test_longContentWithShallowSavedHeight_uses760PointTarget()
        TestTranslationWorkspaceInitialPresentationHeight.test_longContentWithLargerSavedHeight_preservesUserHeight()
        TestTranslationWorkspaceInitialPresentationHeight.test_longContentOnSmallScreen_capsHeightAt24PointSafetyMargin()

        print(
            TranslationWorkspaceLayoutPolicyContractTestSupport.failures == 0
                ? "ALL PASS"
                : "\(TranslationWorkspaceLayoutPolicyContractTestSupport.failures) FAILURES"
        )
        exit(TranslationWorkspaceLayoutPolicyContractTestSupport.failures == 0 ? 0 : 1)
    }
}
