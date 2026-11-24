import AppKit
import Foundation

// 翻译工作台目标语言 / 文本处理唯一入口及最后选择黑盒契约测试。
// 使用临时配置文件，不读取真实配置，不触发网络请求或系统剪贴板。
//
// 预期最小运行命令（生产契约存在后）：
//   swiftc -o /tmp/glint_translation_workbench_controls_contract_test \
//     TranslationFormatting.swift TranslationDocument.swift TranslationWorkbench.swift \
//     RecentResults.swift TranslationClipboard.swift Markdown.swift TranslationWorkspaceView.swift \
//     TranslationAIService.swift TranslationContentValidator.swift TranslationBlockRenderer.swift \
//     Config.swift ScreenshotHotKey.swift TextCommandHotKey.swift HotKey.swift \
//     translation_workbench_controls_contract_tests.swift \
//     -framework AppKit -framework Carbon \
//     && /tmp/glint_translation_workbench_controls_contract_test

enum TranslationWorkbenchControlsContractTestSupport {
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

    static func itemTitles(_ popup: NSPopUpButton) -> [String] {
        popup.itemArray.map(\.title)
    }

    static func temporaryConfigURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("glint-workbench-choice-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("config.json")
    }
}

final class TestTranslationWorkbenchControlSurface {
    static func test_footerExposesOneTargetSelectorAndOneThreeModeProcessingSelector() {
        let view = TranslationWorkspaceView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        let popups = TranslationWorkbenchControlsContractTestSupport.descendants(
            of: view,
            as: NSPopUpButton.self
        )
        let titleSets = popups.map(TranslationWorkbenchControlsContractTestSupport.itemTitles)
        let targetTitles = titleSets.first { $0.contains("简体中文") && $0.contains("英语") }
        let processingTitles = titleSets.first { $0.contains("智能排版") || $0.contains("严格保留") }

        TranslationWorkbenchControlsContractTestSupport.expect(
            popups.count == 2
                && targetTitles?.first == "自动识别（中文 → 英语，其他 → 简体中文）"
                && processingTitles == ["严格保留", "智能排版", "智能润色"],
            "TestTranslationWorkbenchControlSurface.test_footerExposesOneTargetSelectorAndOneThreeModeProcessingSelector"
        )
    }

    static func test_footerOneClickAIButton_followsModeWhileSingleSideActionsRemainAvailable() {
        func configuredView(mode: TranslationFormattingMode) -> TranslationWorkspaceView {
            let view = TranslationWorkspaceView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
            view.configure(
                sourceText: "Synthetic source CASE-2141.",
                translatedText: "虚构译文 CASE-2141。",
                sourceLanguage: "en",
                targetLanguage: "zh-Hans",
                formattingMode: mode,
                readOnly: false
            )
            return view
        }

        let smartButtons = TranslationWorkbenchControlsContractTestSupport.descendants(
            of: configuredView(mode: .smart),
            as: NSButton.self
        )
        let polishButtons = TranslationWorkbenchControlsContractTestSupport.descendants(
            of: configuredView(mode: .polish),
            as: NSButton.self
        )
        let strictButtons = TranslationWorkbenchControlsContractTestSupport.descendants(
            of: configuredView(mode: .strict),
            as: NSButton.self
        )

        let smartOneClick = smartButtons.first { $0.title == "一键智能排版" }
        let polishOneClick = polishButtons.first { $0.title == "一键智能润色" }
        let strictOneClick = strictButtons.first {
            $0.title == "一键智能排版" || $0.title == "一键智能润色"
        }
        let smartTitles = smartButtons.map(\.title)

        TranslationWorkbenchControlsContractTestSupport.expect(
            smartOneClick?.isEnabled == true
                && polishOneClick?.isEnabled == true
                && (strictOneClick == nil || strictOneClick?.isEnabled == false || strictOneClick?.isHidden == true)
                && smartTitles.filter { $0 == "排版" }.count >= 2
                && smartTitles.filter { $0 == "润色" }.count >= 2
                && smartTitles.contains("重新翻译"),
            "TestTranslationWorkbenchControlSurface.test_footerOneClickAIButton_followsModeWhileSingleSideActionsRemainAvailable"
        )
    }
}

final class TestTranslationWorkbenchLastSelection {
    static func test_selectionChange_roundTripsAsTheNextWorkbenchDefaultWithoutTouchingServices() {
        let url = TranslationWorkbenchControlsContractTestSupport.temporaryConfigURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var keychainValues: [AzureAPIKeySlot: String] = [:]
        AppConfig.installRuntimeKeychain(
            AzureKeychainClient(
                read: { keychainValues[$0] },
                write: { value, slot in
                    keychainValues[slot] = value
                    return true
                }
            )
        )
        defer { AppConfig.installRuntimeKeychain(.unavailable) }
        let config = AppConfig(
            translator: AzureTranslatorConfig(
                endpoint: "https://translator.example.invalid",
                apiKey: "fictional-translator-key",
                region: "fictional-region"
            ),
            azureOpenAI: AzureOpenAIConfig(
                endpoint: "https://openai.example.invalid/openai/v1",
                apiKey: "fictional-openai-key",
                deploymentName: "fictional-deployment"
            ),
            translationPreferences: TranslationPreferences()
        )
        let selected = TranslationPreferences(
            targetMode: .fixed,
            fixedTargetLanguage: "ja",
            formattingMode: .polish
        )

        let saved = config.setTranslationPreferences(selected, to: url)
        let loaded = AppConfig.load(from: url)

        TranslationWorkbenchControlsContractTestSupport.expect(
            saved
                && loaded?.translationPreferences == selected
                && loaded?.translator.endpoint == "https://translator.example.invalid"
                && loaded?.translator.apiKey == "fictional-translator-key"
                && loaded?.azureOpenAI.deploymentName == "fictional-deployment",
            "TestTranslationWorkbenchLastSelection.test_selectionChange_roundTripsAsTheNextWorkbenchDefaultWithoutTouchingServices"
        )
    }
}

@main
enum TranslationWorkbenchControlsContractTests {
    static func main() {
        _ = NSApplication.shared
        TestTranslationWorkbenchControlSurface.test_footerExposesOneTargetSelectorAndOneThreeModeProcessingSelector()
        TestTranslationWorkbenchControlSurface.test_footerOneClickAIButton_followsModeWhileSingleSideActionsRemainAvailable()
        TestTranslationWorkbenchLastSelection.test_selectionChange_roundTripsAsTheNextWorkbenchDefaultWithoutTouchingServices()

        print(
            TranslationWorkbenchControlsContractTestSupport.failures == 0
                ? "ALL PASS"
                : "\(TranslationWorkbenchControlsContractTestSupport.failures) FAILURES"
        )
        exit(TranslationWorkbenchControlsContractTestSupport.failures == 0 ? 0 : 1)
    }
}
