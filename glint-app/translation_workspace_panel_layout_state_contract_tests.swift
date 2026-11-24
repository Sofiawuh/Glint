import AppKit
import Foundation

// PopupController 所需的翻译工作台面板布局与状态纯值契约。
// 测试不创建窗口、不读取 NSScreen，也不访问用户配置、Keychain、剪贴板或真实正文。
//
// 预期公开生产契约：
// - TranslationWorkspacePanelLayoutPolicy.activeBodyLayout(paperBounds:event:)
// - TranslationWorkspacePanelLayoutState.recordProgrammaticResize / recordUserResize / resetForNewTranslation
// - TranslationWorkspacePanelLayoutState.resolvedHeight(current:recommended:)
//
// 本机没有仓库要求的 harness 命令，使用 perl alarm 提供等价总超时：
//   perl -e 'alarm 120; exec @ARGV' -- \
//     swiftc -parse-as-library -o /tmp/glint_translation_workspace_panel_layout_state_contract_test \
//       TranslationFormatting.swift TranslationDocument.swift TranslationWorkbench.swift \
//       RecentResults.swift PopupLifecycle.swift TranslationClipboard.swift Markdown.swift TranslationWorkspaceView.swift \
//       TranslationAIService.swift TranslationBlockRenderer.swift \
//       Config.swift ScreenshotHotKey.swift TextCommandHotKey.swift HotKey.swift \
//       translation_workspace_panel_layout_state_contract_tests.swift \
//       -framework AppKit -framework Carbon
//   perl -e 'alarm 30; exec @ARGV' -- /tmp/glint_translation_workspace_panel_layout_state_contract_test

enum TranslationWorkspacePanelLayoutStateContractTestSupport {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ name: String, detail: String = "") {
        if condition() {
            print("  ok  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        }
    }

    static func isFullSizeMask(_ mask: NSView.AutoresizingMask) -> Bool {
        mask.contains(.width) && mask.contains(.height)
    }
}

final class TestTranslationWorkspaceActiveBodyLayout {
    static func test_outerPanelExpansionAndContraction_makeBodyFillPaperBounds() {
        let expandedBounds = NSRect(x: 0, y: 0, width: 900, height: 760)
        let contractedBounds = NSRect(x: 0, y: 0, width: 900, height: 430)
        let expanded = TranslationWorkspacePanelLayoutPolicy.activeBodyLayout(
            paperBounds: expandedBounds,
            event: .outerBoundsChanged
        )
        let contracted = TranslationWorkspacePanelLayoutPolicy.activeBodyLayout(
            paperBounds: contractedBounds,
            event: .outerBoundsChanged
        )

        TranslationWorkspacePanelLayoutStateContractTestSupport.expect(
            expanded.frame == expandedBounds
                && contracted.frame == contractedBounds
                && TranslationWorkspacePanelLayoutStateContractTestSupport.isFullSizeMask(expanded.autoresizingMask)
                && TranslationWorkspacePanelLayoutStateContractTestSupport.isFullSizeMask(contracted.autoresizingMask),
            "TestTranslationWorkspaceActiveBodyLayout.test_outerPanelExpansionAndContraction_makeBodyFillPaperBounds"
        )
    }

    static func test_animationCompletionAndRestore_reinstateWidthAndHeightAutoresizing() {
        let bounds = NSRect(x: 0, y: 0, width: 840, height: 680)
        let animation = TranslationWorkspacePanelLayoutPolicy.activeBodyLayout(
            paperBounds: bounds,
            event: .animationCompleted
        )
        let restore = TranslationWorkspacePanelLayoutPolicy.activeBodyLayout(
            paperBounds: bounds,
            event: .restored
        )

        TranslationWorkspacePanelLayoutStateContractTestSupport.expect(
            animation.frame == bounds
                && restore.frame == bounds
                && TranslationWorkspacePanelLayoutStateContractTestSupport.isFullSizeMask(animation.autoresizingMask)
                && TranslationWorkspacePanelLayoutStateContractTestSupport.isFullSizeMask(restore.autoresizingMask),
            "TestTranslationWorkspaceActiveBodyLayout.test_animationCompletionAndRestore_reinstateWidthAndHeightAutoresizing"
        )
    }
}

final class TestTranslationWorkspacePanelLayoutState {
    static func test_programmaticResize_keepsAutomaticContentHeightEnabled() {
        var state = TranslationWorkspacePanelLayoutState()
        state.recordProgrammaticResize()

        TranslationWorkspacePanelLayoutStateContractTestSupport.expect(
            !state.userResized && state.resolvedHeight(current: 430, recommended: 620) == 620,
            "TestTranslationWorkspacePanelLayoutState.test_programmaticResize_keepsAutomaticContentHeightEnabled"
        )
    }

    static func test_userResize_preservesManualHeightUntilNextTranslation() {
        var state = TranslationWorkspacePanelLayoutState()
        state.recordUserResize()
        let heightAfterLongerContent = state.resolvedHeight(current: 590, recommended: 720)
        let heightAfterShorterContent = state.resolvedHeight(current: 590, recommended: 430)
        state.resetForNewTranslation()
        let heightForNextTranslation = state.resolvedHeight(current: 590, recommended: 520)

        TranslationWorkspacePanelLayoutStateContractTestSupport.expect(
            heightAfterLongerContent == 590
                && heightAfterShorterContent == 590
                && !state.userResized
                && heightForNextTranslation == 520,
            "TestTranslationWorkspacePanelLayoutState.test_userResize_preservesManualHeightUntilNextTranslation"
        )
    }
}

@main
enum TranslationWorkspacePanelLayoutStateContractTests {
    static func main() {
        TestTranslationWorkspaceActiveBodyLayout.test_outerPanelExpansionAndContraction_makeBodyFillPaperBounds()
        TestTranslationWorkspaceActiveBodyLayout.test_animationCompletionAndRestore_reinstateWidthAndHeightAutoresizing()
        TestTranslationWorkspacePanelLayoutState.test_programmaticResize_keepsAutomaticContentHeightEnabled()
        TestTranslationWorkspacePanelLayoutState.test_userResize_preservesManualHeightUntilNextTranslation()

        print(
            TranslationWorkspacePanelLayoutStateContractTestSupport.failures == 0
                ? "ALL PASS"
                : "\(TranslationWorkspacePanelLayoutStateContractTestSupport.failures) FAILURES"
        )
        exit(TranslationWorkspacePanelLayoutStateContractTestSupport.failures == 0 ? 0 : 1)
    }
}
