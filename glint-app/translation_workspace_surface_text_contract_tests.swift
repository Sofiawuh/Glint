import AppKit
import Foundation

// 正式 TranslationWorkspaceView 产品文本黑盒契约。
// 浏览器设计预览的连接状态文案不得泄漏到原生 AppKit 工作台。
//
// 预期最小运行命令：
//   swiftc -parse-as-library -o /tmp/glint_translation_workspace_surface_text_contract_test \
//     TranslationFormatting.swift TranslationDocument.swift TranslationWorkbench.swift \
//     RecentResults.swift TranslationClipboard.swift Markdown.swift TranslationWorkspaceView.swift \
//     TranslationAIService.swift TranslationBlockRenderer.swift Config.swift \
//     ScreenshotHotKey.swift TextCommandHotKey.swift HotKey.swift \
//     translation_workspace_surface_text_contract_tests.swift \
//     -framework AppKit -framework Carbon \
//     && /tmp/glint_translation_workspace_surface_text_contract_test

enum TranslationWorkspaceSurfaceTextContractTestSupport {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() {
            print("  ok  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
        }
    }

    static func descendants<T: NSView>(of view: NSView, as type: T.Type) -> [T] {
        var matches = view.subviews.compactMap { $0 as? T }
        for child in view.subviews {
            matches.append(contentsOf: descendants(of: child, as: type))
        }
        return matches
    }

    static func exposedStrings(in view: NSView) -> [String] {
        let textFields = descendants(of: view, as: NSTextField.self).map(\.stringValue)
        let textViews = descendants(of: view, as: NSTextView.self).map(\.string)
        let buttons = descendants(of: view, as: NSButton.self).flatMap { button in
            [button.title, button.toolTip ?? "", button.accessibilityLabel() ?? ""]
        }
        let popups = descendants(of: view, as: NSPopUpButton.self).flatMap { popup in
            popup.itemArray.map(\.title) + [popup.toolTip ?? "", popup.accessibilityLabel() ?? ""]
        }
        return textFields + textViews + buttons + popups
    }
}

final class TestTranslationWorkspaceProductText {
    static func test_formalAppKitSurface_neverContainsBrowserPreviewConnectedText() {
        let view = TranslationWorkspaceView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 600)
        )
        view.configure(
            sourceText: "Synthetic source text.",
            translatedText: "虚构译文。",
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            formattingMode: .smart,
            readOnly: false
        )
        view.setStatus("翻译完成")

        let leakedPreviewText = TranslationWorkspaceSurfaceTextContractTestSupport
            .exposedStrings(in: view)
            .contains { $0.localizedCaseInsensitiveContains("Connected") }

        TranslationWorkspaceSurfaceTextContractTestSupport.expect(
            !leakedPreviewText,
            "TestTranslationWorkspaceProductText.test_formalAppKitSurface_neverContainsBrowserPreviewConnectedText"
        )
    }
}

@main
enum TranslationWorkspaceSurfaceTextContractTests {
    static func main() {
        _ = NSApplication.shared
        TestTranslationWorkspaceProductText.test_formalAppKitSurface_neverContainsBrowserPreviewConnectedText()

        print(
            TranslationWorkspaceSurfaceTextContractTestSupport.failures == 0
                ? "ALL PASS"
                : "\(TranslationWorkspaceSurfaceTextContractTestSupport.failures) FAILURES"
        )
        exit(TranslationWorkspaceSurfaceTextContractTestSupport.failures == 0 ? 0 : 1)
    }
}
