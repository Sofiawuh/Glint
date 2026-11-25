import Foundation

// Azure GPT 手动排版 / 润色的普通文本协议黑盒契约测试。
// 不发起网络请求；Endpoint、Key、部署名和正文均为虚构样本。
//
// 预期最小运行命令：
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

    static func requestMessages(_ request: URLRequest?) -> [[String: Any]] {
        guard let data = request?.httpBody,
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = body["messages"] as? [[String: Any]] else { return [] }
        return messages
    }
}

final class TestTranslationAIPlainTextRequest {
    private static func service() -> TranslationAIService {
        TranslationAIService(config: AzureOpenAIConfig(
            endpoint: "https://fictional-resource.openai.azure.invalid/openai/v1",
            apiKey: "fictional-gpt-key",
            deploymentName: "fictional-deployment",
            supportsVision: false
        ))
    }

    static func test_smartRequest_asksForCompletePlainTextWithoutJSONOrBlockSchema() {
        let input = "Subject: Fictional status\n\n1. CASE-2141 is ready.\n2. Visit https://example.invalid/status."
        let request = service().buildSingleRequest(text: input, mode: .smart)
        let messageText = TranslationAIProtocolContractTestSupport.requestMessages(request)
            .compactMap { $0["content"] as? String }
            .joined(separator: "\n")
        let lowercased = messageText.lowercased()

        TranslationAIProtocolContractTestSupport.expect(
            request?.httpMethod == "POST"
                && messageText.contains(input)
                && lowercased.contains("smart")
                && !lowercased.contains("json")
                && !lowercased.contains("source_blocks")
                && !lowercased.contains("translation_blocks")
                && !lowercased.contains("allowed block types")
                && !lowercased.contains("exactly one key")
                && !lowercased.contains("named blocks"),
            "TestTranslationAIPlainTextRequest.test_smartRequest_asksForCompletePlainTextWithoutJSONOrBlockSchema"
        )
    }

    static func test_polishRequest_allowsLanguageImprovementWithoutProtectedTokenInstructions() {
        let input = "Fictional customer asks whether CASE-2141 costs USD 1,234.50."
        let request = service().buildSingleRequest(text: input, mode: .polish)
        let messageText = TranslationAIProtocolContractTestSupport.requestMessages(request)
            .compactMap { $0["content"] as? String }
            .joined(separator: "\n")
        let lowercased = messageText.lowercased()

        TranslationAIProtocolContractTestSupport.expect(
            messageText.contains(input)
                && lowercased.contains("polish")
                && !lowercased.contains("json")
                && !lowercased.contains("factual token")
                && !lowercased.contains("list fact count")
                && !lowercased.contains("list order")
                && !lowercased.contains("preserve every person")
                && !lowercased.contains("preserve each non-whitespace character"),
            "TestTranslationAIPlainTextRequest.test_polishRequest_allowsLanguageImprovementWithoutProtectedTokenInstructions"
        )
    }
}

final class TestTranslationAIPlainTextResponse {
    private static let service = TranslationAIService(config: AzureOpenAIConfig(
        endpoint: "https://fictional-resource.openai.azure.invalid/openai/v1",
        apiKey: "fictional-gpt-key",
        deploymentName: "fictional-deployment"
    ))

    static func test_nonJSONText_isAcceptedAsOneCompleteResult() {
        let output = "Fictional status\n\n• The identifier was rewritten for readability.\n• The date was expressed naturally."
        let parsed = service.parseSingleResponse(
            data: TranslationAIProtocolContractTestSupport.responseEnvelope(content: output)
        )

        TranslationAIProtocolContractTestSupport.expect(
            parsed == [.paragraph(output)],
            "TestTranslationAIPlainTextResponse.test_nonJSONText_isAcceptedAsOneCompleteResult"
        )
    }

    static func test_whitespaceOnlyText_isRejectedButAnyTrimmedTextIsAccepted() {
        let whitespace = service.parseSingleResponse(
            data: TranslationAIProtocolContractTestSupport.responseEnvelope(content: "  \n\t  ")
        )
        let shortText = service.parseSingleResponse(
            data: TranslationAIProtocolContractTestSupport.responseEnvelope(content: "  OK  ")
        )

        TranslationAIProtocolContractTestSupport.expect(
            whitespace == nil && shortText == [.paragraph("OK")],
            "TestTranslationAIPlainTextResponse.test_whitespaceOnlyText_isRejectedButAnyTrimmedTextIsAccepted"
        )
    }
}

@main
enum TranslationAIProtocolContractTests {
    static func main() {
        TestTranslationAIPlainTextRequest.test_smartRequest_asksForCompletePlainTextWithoutJSONOrBlockSchema()
        TestTranslationAIPlainTextRequest.test_polishRequest_allowsLanguageImprovementWithoutProtectedTokenInstructions()
        TestTranslationAIPlainTextResponse.test_nonJSONText_isAcceptedAsOneCompleteResult()
        TestTranslationAIPlainTextResponse.test_whitespaceOnlyText_isRejectedButAnyTrimmedTextIsAccepted()

        print(
            TranslationAIProtocolContractTestSupport.failures == 0
                ? "ALL PASS"
                : "\(TranslationAIProtocolContractTestSupport.failures) FAILURES"
        )
        exit(TranslationAIProtocolContractTestSupport.failures == 0 ? 0 : 1)
    }
}
