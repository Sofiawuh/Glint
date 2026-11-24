import Foundation

// Azure GPT 结构化排版 / 润色请求响应黑盒契约测试。
// 不发起网络请求；Endpoint、Key、部署名和正文均为虚构样本。
//
// 预期最小运行命令（生产契约存在后）：
//   swiftc -o /tmp/glint_translation_ai_protocol_contract_test \
//     TranslationFormatting.swift TranslationDocument.swift Config.swift \
//     ScreenshotHotKey.swift TextCommandHotKey.swift HotKey.swift \
//     TranslationAIService.swift translation_ai_protocol_contract_tests.swift \
//     -framework Foundation -framework Carbon \
//     && /tmp/glint_translation_ai_protocol_contract_test

enum TranslationAIProtocolContractTestSupport {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() {
            print("  ok  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
        }
    }

    static func responseEnvelope(content: String) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": content]]]
        ])
    }

    static func jsonBody(_ request: URLRequest?) -> [String: Any]? {
        guard let data = request?.httpBody else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func automaticJSON(
        sourceBlocks: [[String: Any]],
        translationBlocks: [[String: Any]]
    ) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [
            "source_blocks": sourceBlocks,
            "translation_blocks": translationBlocks
        ], options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}

final class TestTranslationAIStructuredRequest {
    static func test_automaticSmartRequest_isOneNonStreamingChatCompletionContainingBothSidesAndMode() {
        let config = AzureOpenAIConfig(
            endpoint: "https://fictional-resource.openai.azure.invalid/openai/v1",
            apiKey: "fictional-gpt-key",
            deploymentName: "fictional-deployment",
            supportsVision: false
        )
        let service = TranslationAIService(config: config)
        let source = "Hi Reviewer,\n\n• Keep CASE-2141."
        let translation = "你好，审核人：\n\n• 保留 CASE-2141。"
        let request = service.buildAutomaticRequest(
            sourceText: source,
            translatedText: translation,
            mode: .smart
        )
        let body = TranslationAIProtocolContractTestSupport.jsonBody(request)
        let messages = body?["messages"] as? [[String: Any]]
        let messageText = messages?
            .compactMap { $0["content"] as? String }
            .joined(separator: "\n") ?? ""

        TranslationAIProtocolContractTestSupport.expect(
            request?.url?.absoluteString == "https://fictional-resource.openai.azure.invalid/openai/v1/chat/completions"
                && request?.httpMethod == "POST"
                && request?.value(forHTTPHeaderField: "api-key") == "fictional-gpt-key"
                && body?["model"] as? String == "fictional-deployment"
                && body?["stream"] as? Bool == false
                && messageText.contains(source)
                && messageText.contains(translation)
                && messageText.lowercased().contains("smart")
                && messageText.contains("source_blocks")
                && messageText.contains("translation_blocks"),
            "TestTranslationAIStructuredRequest.test_automaticSmartRequest_isOneNonStreamingChatCompletionContainingBothSidesAndMode"
        )
    }
}

final class TestTranslationAIStructuredResponse {
    static func test_validSourceAndTranslationBlocks_decodeInOrder() {
        let service = TranslationAIService(config: AzureOpenAIConfig(
            endpoint: "https://fictional-resource.openai.azure.invalid/openai/v1",
            apiKey: "fictional-gpt-key",
            deploymentName: "fictional-deployment"
        ))
        let inner = #"{"source_blocks":[{"type":"salutation","text":"Hi Reviewer,"},{"type":"key_points","items":["Keep CASE-2141","Keep USD 1,234.50"]},{"type":"signature","text":"Best regards,\nFictional Sender"}],"translation_blocks":[{"type":"salutation","text":"你好，审核人："},{"type":"key_points","items":["保留 CASE-2141","保留 USD 1,234.50"]},{"type":"signature","text":"此致\nFictional Sender"}]}"#
        let data = TranslationAIProtocolContractTestSupport.responseEnvelope(content: inner)

        let result = service.parseAutomaticResponse(data: data)
        let expectedSource: [TranslationBlock] = [
            .salutation("Hi Reviewer,"),
            .keyPoints(["Keep CASE-2141", "Keep USD 1,234.50"]),
            .signature("Best regards,\nFictional Sender")
        ]
        let expectedTranslation: [TranslationBlock] = [
            .salutation("你好，审核人："),
            .keyPoints(["保留 CASE-2141", "保留 USD 1,234.50"]),
            .signature("此致\nFictional Sender")
        ]

        TranslationAIProtocolContractTestSupport.expect(
            result?.sourceBlocks == expectedSource
                && result?.translationBlocks == expectedTranslation,
            "TestTranslationAIStructuredResponse.test_validSourceAndTranslationBlocks_decodeInOrder"
        )
    }

    static func test_markdownFencesWithOrWithoutLanguageTag_extractCompleteJSONObject() {
        let service = TranslationAIService(config: AzureOpenAIConfig(
            endpoint: "https://fictional-resource.openai.azure.invalid/openai/v1",
            apiKey: "fictional-gpt-key",
            deploymentName: "fictional-deployment"
        ))
        let inner = TranslationAIProtocolContractTestSupport.automaticJSON(
            sourceBlocks: [["type": "paragraph", "text": "Fictional source."]],
            translationBlocks: [["type": "paragraph", "text": "虚构译文。"]]
        )
        let wrapped = [
            "```json\n\(inner)\n```",
            "```\n\(inner)\n```"
        ]

        TranslationAIProtocolContractTestSupport.expect(
            wrapped.allSatisfy {
                service.parseAutomaticResponse(
                    data: TranslationAIProtocolContractTestSupport.responseEnvelope(content: $0)
                ) != nil
            },
            "TestTranslationAIStructuredResponse.test_markdownFencesWithOrWithoutLanguageTag_extractCompleteJSONObject"
        )
    }

    static func test_explanatoryTextAndLaterObject_extractFirstCompleteJSONObject() {
        let service = TranslationAIService(config: AzureOpenAIConfig(
            endpoint: "https://fictional-resource.openai.azure.invalid/openai/v1",
            apiKey: "fictional-gpt-key",
            deploymentName: "fictional-deployment"
        ))
        let sourceText = "Literal } before {stage} says \"ready\"."
        let translationText = "字面量 } 位于 {stage} 前，并表示 \"ready\"。"
        let inner = TranslationAIProtocolContractTestSupport.automaticJSON(
            sourceBlocks: [["type": "paragraph", "text": sourceText]],
            translationBlocks: [["type": "paragraph", "text": translationText]]
        )
        let content = "Here is the requested object:\n\(inner)\nAdditional metadata: {\"ignored\":true}"
        let result = service.parseAutomaticResponse(
            data: TranslationAIProtocolContractTestSupport.responseEnvelope(content: content)
        )

        TranslationAIProtocolContractTestSupport.expect(
            result?.sourceBlocks == [.paragraph(sourceText)]
                && result?.translationBlocks == [.paragraph(translationText)],
            "TestTranslationAIStructuredResponse.test_explanatoryTextAndLaterObject_extractFirstCompleteJSONObject"
        )
    }

    static func test_unknownBlockType_isRejectedInsteadOfRenderedAsGenericContent() {
        let service = TranslationAIService(config: AzureOpenAIConfig(
            endpoint: "https://fictional-resource.openai.azure.invalid/openai/v1",
            apiKey: "fictional-gpt-key",
            deploymentName: "fictional-deployment"
        ))
        let inner = #"{"source_blocks":[{"type":"html","text":"<b>CASE-2141</b>"}],"translation_blocks":[{"type":"paragraph","text":"CASE-2141"}]}"#
        let data = TranslationAIProtocolContractTestSupport.responseEnvelope(content: inner)

        TranslationAIProtocolContractTestSupport.expect(
            service.parseAutomaticResponse(data: data) == nil,
            "TestTranslationAIStructuredResponse.test_unknownBlockType_isRejectedInsteadOfRenderedAsGenericContent"
        )
    }

    static func test_modelVisualParameters_areRejectedInsteadOfInfluencingNativeRendering() {
        let service = TranslationAIService(config: AzureOpenAIConfig(
            endpoint: "https://fictional-resource.openai.azure.invalid/openai/v1",
            apiKey: "fictional-gpt-key",
            deploymentName: "fictional-deployment"
        ))
        let inner = #"{"source_blocks":[{"type":"paragraph","text":"CASE-2141","color":"red","font_size":72}],"translation_blocks":[{"type":"paragraph","text":"CASE-2141"}]}"#
        let data = TranslationAIProtocolContractTestSupport.responseEnvelope(content: inner)

        TranslationAIProtocolContractTestSupport.expect(
            service.parseAutomaticResponse(data: data) == nil,
            "TestTranslationAIStructuredResponse.test_modelVisualParameters_areRejectedInsteadOfInfluencingNativeRendering"
        )
    }

    static func test_differentBlockCountsBetweenSourceAndTranslation_areAcceptedIndependently() {
        let service = TranslationAIService(config: AzureOpenAIConfig(
            endpoint: "https://fictional-resource.openai.azure.invalid/openai/v1",
            apiKey: "fictional-gpt-key",
            deploymentName: "fictional-deployment"
        ))
        let mismatchedCount = #"{"source_blocks":[{"type":"heading","text":"Status"},{"type":"paragraph","text":"CASE-2141"}],"translation_blocks":[{"type":"heading","text":"状态 CASE-2141"}]}"#
        let result = service.parseAutomaticResponse(
            data: TranslationAIProtocolContractTestSupport.responseEnvelope(content: mismatchedCount)
        )

        TranslationAIProtocolContractTestSupport.expect(
            result?.sourceBlocks == [.heading("Status"), .paragraph("CASE-2141")]
                && result?.translationBlocks == [.heading("状态 CASE-2141")],
            "TestTranslationAIStructuredResponse.test_differentBlockCountsBetweenSourceAndTranslation_areAcceptedIndependently"
        )
    }

    static func test_differentBlockTypesBetweenSourceAndTranslation_areAcceptedIndependently() {
        let service = TranslationAIService(config: AzureOpenAIConfig(
            endpoint: "https://fictional-resource.openai.azure.invalid/openai/v1",
            apiKey: "fictional-gpt-key",
            deploymentName: "fictional-deployment"
        ))
        let mismatchedType = #"{"source_blocks":[{"type":"paragraph","text":"CASE-2141"}],"translation_blocks":[{"type":"heading","text":"CASE-2141"}]}"#
        let result = service.parseAutomaticResponse(
            data: TranslationAIProtocolContractTestSupport.responseEnvelope(content: mismatchedType)
        )

        TranslationAIProtocolContractTestSupport.expect(
            result?.sourceBlocks == [.paragraph("CASE-2141")]
                && result?.translationBlocks == [.heading("CASE-2141")],
            "TestTranslationAIStructuredResponse.test_differentBlockTypesBetweenSourceAndTranslation_areAcceptedIndependently"
        )
    }
}

@main
enum TranslationAIProtocolContractTests {
    static func main() {
        TestTranslationAIStructuredRequest.test_automaticSmartRequest_isOneNonStreamingChatCompletionContainingBothSidesAndMode()
        TestTranslationAIStructuredResponse.test_validSourceAndTranslationBlocks_decodeInOrder()
        TestTranslationAIStructuredResponse.test_markdownFencesWithOrWithoutLanguageTag_extractCompleteJSONObject()
        TestTranslationAIStructuredResponse.test_explanatoryTextAndLaterObject_extractFirstCompleteJSONObject()
        TestTranslationAIStructuredResponse.test_unknownBlockType_isRejectedInsteadOfRenderedAsGenericContent()
        TestTranslationAIStructuredResponse.test_modelVisualParameters_areRejectedInsteadOfInfluencingNativeRendering()
        TestTranslationAIStructuredResponse.test_differentBlockCountsBetweenSourceAndTranslation_areAcceptedIndependently()
        TestTranslationAIStructuredResponse.test_differentBlockTypesBetweenSourceAndTranslation_areAcceptedIndependently()

        print(
            TranslationAIProtocolContractTestSupport.failures == 0
                ? "ALL PASS"
                : "\(TranslationAIProtocolContractTestSupport.failures) FAILURES"
        )
        exit(TranslationAIProtocolContractTestSupport.failures == 0 ? 0 : 1)
    }
}
