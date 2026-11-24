import Foundation

// TranslationService 的 Translator + 可选 Azure GPT 后处理编排黑盒契约测试。
// 所有依赖均为进程内闭包，不读取 AppConfig、不创建 URLRequest、不访问网络。
// 测试只观察调用次数、最终文本和公开回退状态，不依赖网络实现或 JSON 解析细节。
//
// 预期最小运行命令（生产契约存在后）：
//   swiftc -parse-as-library -o /tmp/glint_translation_service_orchestration_contract_test \
//     TranslationFormatting.swift TranslationDocument.swift TranslationContentValidator.swift \
//     Config.swift ScreenshotHotKey.swift TextCommandHotKey.swift HotKey.swift \
//     TranslationAIService.swift TranslationBlockRenderer.swift TranslationService.swift \
//     translation_service_orchestration_contract_tests.swift \
//     -framework AppKit -framework Carbon \
//     && /tmp/glint_translation_service_orchestration_contract_test

enum TranslationServiceOrchestrationContractTestSupport {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() {
            print("  ok  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
        }
    }

    static func successfulValue(
        _ result: Result<TranslationServiceResult, TranslationServiceError>
    ) -> TranslationServiceResult? {
        guard case .success(let value) = result else { return nil }
        return value
    }
}

final class TestTranslationServiceStrictOrchestration {
    static func test_strictMode_translatesOnceAndNeverCallsAIPostprocessor() async {
        var translatorCalls = 0
        var aiCalls = 0
        var translatorInput: (text: String, target: String)?
        let result = await translateDocument(
            "Line one.  \r\nLine two.\t\n",
            targetLanguage: "zh-Hans",
            formattingMode: .strict,
            translator: { text, targetLanguage in
                translatorCalls += 1
                translatorInput = (text, targetLanguage)
                return (
                    translatedText: "基础译文。  \r\n第二行。",
                    detectedSourceLanguage: "en"
                )
            },
            aiPostprocessor: { _, _, _ in
                aiCalls += 1
                return (
                    sourceText: "不应采用的 AI 原文",
                    translatedText: "不应采用的 AI 译文"
                )
            }
        )
        let value = TranslationServiceOrchestrationContractTestSupport.successfulValue(result)

        TranslationServiceOrchestrationContractTestSupport.expect(
            translatorCalls == 1
                && aiCalls == 0
                && translatorInput?.text == "Line one.\nLine two.\n"
                && translatorInput?.target == "zh-Hans"
                && value?.sourceText == "Line one.\nLine two.\n"
                && value?.translatedText == "基础译文。\n第二行。"
                && value?.detectedSourceLanguage == "en"
                && value?.aiProcessingState == .notRequested,
            "TestTranslationServiceStrictOrchestration.test_strictMode_translatesOnceAndNeverCallsAIPostprocessor"
        )
    }
}

final class TestTranslationServiceTranslatorFirstOrchestration {
    static func test_smartMode_defaultTranslation_callsTranslatorOnceAndNeverCallsAI() async {
        let source = "Hi Reviewer,\n\n• Keep CASE-2141."
        let translatorText = "你好，审核人：\n\n• 保留 CASE-2141。"
        var translatorCalls = 0
        var aiCalls = 0
        let result = await translateDocument(
            source,
            targetLanguage: "zh-Hans",
            formattingMode: .smart,
            translator: { _, _ in
                translatorCalls += 1
                return (translatedText: translatorText, detectedSourceLanguage: "en")
            },
            aiPostprocessor: { _, _, _ in
                aiCalls += 1
                return (
                    sourceText: "不应采用的 AI 原文",
                    translatedText: "不应采用的 AI 译文"
                )
            }
        )
        let value = TranslationServiceOrchestrationContractTestSupport.successfulValue(result)

        TranslationServiceOrchestrationContractTestSupport.expect(
            translatorCalls == 1
                && aiCalls == 0
                && value?.sourceText == source
                && value?.translatedText == translatorText
                && value?.aiProcessingState == .notRequested,
            "TestTranslationServiceTranslatorFirstOrchestration.test_smartMode_defaultTranslation_callsTranslatorOnceAndNeverCallsAI"
        )
    }

    static func test_polishMode_defaultTranslation_callsTranslatorOnceAndNeverCallsAI() async {
        let source = "CASE-2141 costs USD 1,234.50 on 2026-12-01."
        let translatorText = "CASE-2141 在 2026-12-01 的费用为 USD 1,234.50。"
        var translatorCalls = 0
        var aiCalls = 0
        let result = await translateDocument(
            source,
            targetLanguage: "zh-Hans",
            formattingMode: .polish,
            translator: { _, _ in
                translatorCalls += 1
                return (translatedText: translatorText, detectedSourceLanguage: "en")
            },
            aiPostprocessor: { _, _, _ in
                aiCalls += 1
                return (
                    sourceText: "不应采用的 AI 原文",
                    translatedText: "不应采用的 AI 译文"
                )
            }
        )
        let value = TranslationServiceOrchestrationContractTestSupport.successfulValue(result)

        TranslationServiceOrchestrationContractTestSupport.expect(
            translatorCalls == 1
                && aiCalls == 0
                && value?.sourceText == source
                && value?.translatedText == translatorText
                && value?.aiProcessingState == .notRequested,
            "TestTranslationServiceTranslatorFirstOrchestration.test_polishMode_defaultTranslation_callsTranslatorOnceAndNeverCallsAI"
        )
    }
}

@main
enum TranslationServiceOrchestrationContractTests {
    static func main() async {
        await TestTranslationServiceStrictOrchestration.test_strictMode_translatesOnceAndNeverCallsAIPostprocessor()
        await TestTranslationServiceTranslatorFirstOrchestration.test_smartMode_defaultTranslation_callsTranslatorOnceAndNeverCallsAI()
        await TestTranslationServiceTranslatorFirstOrchestration.test_polishMode_defaultTranslation_callsTranslatorOnceAndNeverCallsAI()

        print(
            TranslationServiceOrchestrationContractTestSupport.failures == 0
                ? "ALL PASS"
                : "\(TranslationServiceOrchestrationContractTestSupport.failures) FAILURES"
        )
        exit(TranslationServiceOrchestrationContractTestSupport.failures == 0 ? 0 : 1)
    }
}
