import AppKit
import Foundation

// TranslationWorkspaceView 不拥有实际 frame 的黑盒契约。
// 所有正文均为完全虚构样本；不读取屏幕、用户配置、Keychain、邮件或剪贴板。
//
// 本机没有仓库要求的 harness 命令，使用 perl alarm 提供等价总超时：
//   perl -e 'alarm 120; exec @ARGV' -- \
//     swiftc -parse-as-library -o /tmp/glint_translation_workspace_frame_ownership_contract_test \
//       TranslationFormatting.swift TranslationDocument.swift TranslationWorkbench.swift \
//       RecentResults.swift TranslationClipboard.swift Markdown.swift TranslationWorkspaceView.swift \
//       TranslationAIService.swift TranslationBlockRenderer.swift \
//       Config.swift ScreenshotHotKey.swift TextCommandHotKey.swift HotKey.swift \
//       translation_workspace_frame_ownership_contract_tests.swift \
//       -framework AppKit -framework Carbon
//   perl -e 'alarm 30; exec @ARGV' -- /tmp/glint_translation_workspace_frame_ownership_contract_test

enum TranslationWorkspaceFrameOwnershipContractTestSupport {
    static var failures = 0

    static func longText(prefix: String) -> String {
        (1...80).map { "\(prefix) \($0)." }.joined(separator: "\n")
    }

    static func expectUnchanged(_ actual: NSRect, expected: NSRect, _ name: String) {
        if actual == expected {
            print("  ok  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name) — expected \(NSStringFromRect(expected)), actual \(NSStringFromRect(actual))")
        }
    }

    static func makeView(frame: NSRect) -> TranslationWorkspaceView {
        TranslationWorkspaceView(frame: frame)
    }

    static func report(_ text: String) -> TranslationRenderedReport {
        TranslationRenderedReport(
            plainText: text,
            attributedText: NSAttributedString(string: text)
        )
    }
}

final class TestTranslationWorkspaceViewFrameOwnership {
    static func test_configureWithShortContent_preservesCallerProvidedFrame() {
        let expected = NSRect(x: 17, y: 29, width: 812, height: 613)
        let view = TranslationWorkspaceFrameOwnershipContractTestSupport.makeView(frame: expected)

        view.configure(
            sourceText: "Synthetic short source.",
            translatedText: "虚构短译文。",
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            formattingMode: .smart,
            readOnly: false
        )

        TranslationWorkspaceFrameOwnershipContractTestSupport.expectUnchanged(
            view.frame,
            expected: expected,
            "TestTranslationWorkspaceViewFrameOwnership.test_configureWithShortContent_preservesCallerProvidedFrame"
        )
    }

    static func test_updateTextsFromLongToShort_preservesCurrentFrame() {
        let view = TranslationWorkspaceFrameOwnershipContractTestSupport.makeView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 760)
        )
        view.configure(
            sourceText: TranslationWorkspaceFrameOwnershipContractTestSupport.longText(prefix: "Synthetic source line"),
            translatedText: TranslationWorkspaceFrameOwnershipContractTestSupport.longText(prefix: "虚构译文行"),
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            formattingMode: .smart,
            readOnly: false
        )
        let expected = NSRect(x: 31, y: 47, width: 777, height: 642)
        view.frame = expected

        view.updateTexts(
            source: "Synthetic replacement.",
            translation: "虚构替换译文。",
            sourceLanguage: "en"
        )

        TranslationWorkspaceFrameOwnershipContractTestSupport.expectUnchanged(
            view.frame,
            expected: expected,
            "TestTranslationWorkspaceViewFrameOwnership.test_updateTextsFromLongToShort_preservesCurrentFrame"
        )
    }

    static func test_updateReportsFromLongToShort_preservesCurrentFrame() {
        let view = TranslationWorkspaceFrameOwnershipContractTestSupport.makeView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 760)
        )
        view.configure(
            sourceText: TranslationWorkspaceFrameOwnershipContractTestSupport.longText(prefix: "Synthetic source line"),
            translatedText: TranslationWorkspaceFrameOwnershipContractTestSupport.longText(prefix: "虚构译文行"),
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            formattingMode: .smart,
            readOnly: false
        )
        let expected = NSRect(x: 53, y: 71, width: 744, height: 688)
        view.frame = expected

        view.updateReports(
            source: TranslationWorkspaceFrameOwnershipContractTestSupport.report("Synthetic report."),
            translation: TranslationWorkspaceFrameOwnershipContractTestSupport.report("虚构报告译文。"),
            sourceLanguage: "en"
        )

        TranslationWorkspaceFrameOwnershipContractTestSupport.expectUnchanged(
            view.frame,
            expected: expected,
            "TestTranslationWorkspaceViewFrameOwnership.test_updateReportsFromLongToShort_preservesCurrentFrame"
        )
    }
}

@main
enum TranslationWorkspaceFrameOwnershipContractTests {
    static func main() {
        _ = NSApplication.shared
        TestTranslationWorkspaceViewFrameOwnership.test_configureWithShortContent_preservesCallerProvidedFrame()
        TestTranslationWorkspaceViewFrameOwnership.test_updateTextsFromLongToShort_preservesCurrentFrame()
        TestTranslationWorkspaceViewFrameOwnership.test_updateReportsFromLongToShort_preservesCurrentFrame()

        print(
            TranslationWorkspaceFrameOwnershipContractTestSupport.failures == 0
                ? "ALL PASS"
                : "\(TranslationWorkspaceFrameOwnershipContractTestSupport.failures) FAILURES"
        )
        exit(TranslationWorkspaceFrameOwnershipContractTestSupport.failures == 0 ? 0 : 1)
    }
}
