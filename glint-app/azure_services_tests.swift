import Foundation

// Azure 专用配置与协议层黑盒契约测试（不进入 App 打包）。
// 运行：swiftc -o /tmp/glint_azure_services_test Config.swift azure_services_tests.swift -framework Foundation
//      && /tmp/glint_azure_services_test

enum AzureTestSupport {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() {
            print("  ok  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
        }
    }

    static func jsonObject(_ data: Data?) -> Any? {
        guard let data else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    static func jsonDictionary(_ data: Data?) -> [String: Any]? {
        jsonObject(data) as? [String: Any]
    }

    static func queryItems(_ request: URLRequest?) -> [String: String] {
        guard let url = request?.url,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    static func permissions(at url: URL) -> Int? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.posixPermissions] as? NSNumber)?.intValue
    }
}

final class TestAzureTranslatorTargetLanguage {
    static func test_textContainingChineseCharacter_targetsEnglish() {
        AzureTestSupport.expect(
            AzureTranslatorConfig.targetLanguage(for: "Release notes 包含中文") == "en"
                && AzureTranslatorConfig.targetLanguage(for: "繁體中文測試") == "en",
            "TestAzureTranslatorTargetLanguage.test_textContainingChineseCharacter_targetsEnglish"
        )
    }

    static func test_textWithoutChineseCharacter_targetsSimplifiedChinese() {
        AzureTestSupport.expect(
            AzureTranslatorConfig.targetLanguage(for: "Hello, Glint!") == "zh-Hans"
                && AzureTranslatorConfig.targetLanguage(for: "123 😀") == "zh-Hans",
            "TestAzureTranslatorTargetLanguage.test_textWithoutChineseCharacter_targetsSimplifiedChinese"
        )
    }
}

final class TestAzureTranslatorRequest {
    static let endpoint = "https://api.cognitive.microsofttranslator.com/"
    static let key = "translator-test-key"

    static func test_textWithRegion_buildsTranslateV3Request() {
        let config = AzureTranslatorConfig(endpoint: endpoint, apiKey: key, region: "eastasia")
        let request = config.buildRequest(text: "Hello")
        let query = AzureTestSupport.queryItems(request)
        let body = AzureTestSupport.jsonObject(request?.httpBody) as? [[String: Any]]

        AzureTestSupport.expect(
            request?.url?.scheme == "https"
                && request?.url?.host == "api.cognitive.microsofttranslator.com"
                && request?.url?.path == "/translate"
                && query["api-version"] == "3.0"
                && query["to"] == "zh-Hans"
                && request?.httpMethod == "POST"
                && request?.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Key") == key
                && request?.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Region") == "eastasia"
                && request?.value(forHTTPHeaderField: "Content-Type") == "application/json"
                && body?.count == 1
                && body?.first?["Text"] as? String == "Hello",
            "TestAzureTranslatorRequest.test_textWithRegion_buildsTranslateV3Request"
        )
    }

    static func test_emptyRegion_omitsRegionHeader() {
        let config = AzureTranslatorConfig(endpoint: endpoint, apiKey: key, region: "  ")
        let request = config.buildRequest(text: "你好")

        AzureTestSupport.expect(
            AzureTestSupport.queryItems(request)["to"] == "en"
                && request?.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Key") == key
                && request?.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Region") == nil,
            "TestAzureTranslatorRequest.test_emptyRegion_omitsRegionHeader"
        )
    }
}

final class TestAzureOpenAIRequest {
    static let key = "gpt-test-key"
    static let messages: [[String: Any]] = [
        ["role": "system", "content": "Be concise."],
        ["role": "user", "content": "Explain this code."]
    ]

    static func makeConfig(endpoint: String) -> AzureOpenAIConfig {
        AzureOpenAIConfig(
            endpoint: endpoint,
            apiKey: key,
            deploymentName: "gpt-5-deployment",
            supportsVision: true
        )
    }

    static func test_v1EndpointVariants_normalizeToChatCompletions() {
        let endpoints = [
            "https://sample-resource.openai.azure.com/openai/v1",
            "https://sample-resource.openai.azure.com/openai/v1/",
            "https://sample-resource.openai.azure.com/openai/v1/chat/completions"
        ]
        let urls = endpoints.compactMap {
            makeConfig(endpoint: $0)
                .buildRequest(messages: messages, maxTokens: 256, stream: false)?
                .url?.absoluteString
        }

        AzureTestSupport.expect(
            urls.count == endpoints.count
                && Set(urls) == ["https://sample-resource.openai.azure.com/openai/v1/chat/completions"],
            "TestAzureOpenAIRequest.test_v1EndpointVariants_normalizeToChatCompletions"
        )
    }

    static func test_messagesAndDeployment_buildAzureChatBodyWithoutThinking() {
        let request = makeConfig(endpoint: "https://sample-resource.openai.azure.com/openai/v1")
            .buildRequest(messages: messages, maxTokens: 256, stream: true)
        let body = AzureTestSupport.jsonDictionary(request?.httpBody)
        let encodedBody = request?.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let requestMessages = body?["messages"] as? [[String: Any]]

        AzureTestSupport.expect(
            request?.httpMethod == "POST"
                && request?.value(forHTTPHeaderField: "api-key") == key
                && request?.value(forHTTPHeaderField: "Authorization") == nil
                && request?.value(forHTTPHeaderField: "Content-Type") == "application/json"
                && request?.value(forHTTPHeaderField: "Accept") == "text/event-stream"
                && body?["model"] as? String == "gpt-5-deployment"
                && requestMessages?.count == 2
                && requestMessages?.last?["content"] as? String == "Explain this code."
                && body?["stream"] as? Bool == true
                && body?["max_completion_tokens"] as? Int == 256
                && body?["temperature"] == nil
                && body?["thinking"] == nil
                && !encodedBody.contains("\"temperature\"")
                && !encodedBody.contains("\"thinking\""),
            "TestAzureOpenAIRequest.test_messagesAndDeployment_buildAzureChatBodyWithoutThinking"
        )
    }
}

final class TestAzureServiceResponseParsing {
    static let translator = AzureTranslatorConfig(
        endpoint: "https://api.cognitive.microsofttranslator.com",
        apiKey: "translator-test-key",
        region: ""
    )
    static let gpt = AzureOpenAIConfig(
        endpoint: "https://sample-resource.openai.azure.com/openai/v1",
        apiKey: "gpt-test-key",
        deploymentName: "gpt-5-deployment",
        supportsVision: false
    )

    static func test_translatorAndChatResponses_returnVisibleText() {
        let translatorData = #"[{"translations":[{"text":"你好","to":"zh-Hans"}]}]"#.data(using: .utf8)!
        let chatData = #"{"choices":[{"message":{"role":"assistant","content":"可见回答"}}]}"#.data(using: .utf8)!

        AzureTestSupport.expect(
            translator.parseResponse(data: translatorData) == "你好"
                && gpt.parseResponse(data: chatData) == "可见回答",
            "TestAzureServiceResponseParsing.test_translatorAndChatResponses_returnVisibleText"
        )
    }

    static func test_sseDeltaDoneAndError_returnTypedEvents() {
        let delta = gpt.parseStreamLine(#"data: {"choices":[{"delta":{"content":"增量"}}]}"#)
        let done = gpt.parseStreamLine("data: [DONE]")
        let error = gpt.parseStreamLine(
            #"data: {"error":{"code":"rate_limit_exceeded","message":"gpt-test-key has been throttled"}}"#
        )
        let errorIsRedacted: Bool
        if case .error(let message) = error {
            errorIsRedacted = message.contains("rate_limit_exceeded")
                && message.contains("throttled")
                && !message.contains("gpt-test-key")
        } else {
            errorIsRedacted = false
        }

        AzureTestSupport.expect(
            delta == .delta("增量") && done == .done && errorIsRedacted,
            "TestAzureServiceResponseParsing.test_sseDeltaDoneAndError_returnTypedEvents"
        )
    }
}

final class TestAzureErrorParsing {
    static func test_jsonError_includesCodeAndMessageButRedactsCredentials() {
        let translatorKey = "translator-test-key"
        let gptKey = "gpt-test-key"
        let translator = AzureTranslatorConfig(
            endpoint: "https://api.cognitive.microsofttranslator.com",
            apiKey: translatorKey,
            region: "eastasia"
        )
        let gpt = AzureOpenAIConfig(
            endpoint: "https://sample-resource.openai.azure.com/openai/v1",
            apiKey: gptKey,
            deploymentName: "gpt-5-deployment",
            supportsVision: false
        )
        let translatorError = #"{"error":{"code":"401000","message":"The request is not authorized: translator-test-key"}}"#
            .data(using: .utf8)!
        let gptError = #"{"error":{"code":"DeploymentNotFound","message":"gpt-test-key cannot access this deployment"}}"#
            .data(using: .utf8)!
        let translatorMessage = translator.parseError(statusCode: 401, data: translatorError)
        let gptMessage = gpt.parseError(statusCode: 404, data: gptError)

        AzureTestSupport.expect(
            translatorMessage.contains("401000")
                && translatorMessage.contains("not authorized")
                && !translatorMessage.contains(translatorKey)
                && gptMessage.contains("DeploymentNotFound")
                && gptMessage.contains("cannot access")
                && !gptMessage.contains(gptKey),
            "TestAzureErrorParsing.test_jsonError_includesCodeAndMessageButRedactsCredentials"
        )
    }

    static func test_nonJsonError_reportsStatusWithoutLeakingResponseHeadersOrKey() {
        let key = "gpt-test-key"
        let gpt = AzureOpenAIConfig(
            endpoint: "https://sample-resource.openai.azure.com/openai/v1",
            apiKey: key,
            deploymentName: "gpt-5-deployment",
            supportsVision: false
        )
        let message = gpt.parseError(
            statusCode: 503,
            data: "upstream unavailable; api-key: gpt-test-key".data(using: .utf8)!
        )

        AzureTestSupport.expect(
            message.contains("503") && !message.contains(key) && !message.lowercased().contains("api-key:"),
            "TestAzureErrorParsing.test_nonJsonError_reportsStatusWithoutLeakingResponseHeadersOrKey"
        )
    }
}

final class TestAzureAppConfigPersistence {
    static func test_azureConfigs_codableRoundTripPreservesBothServices() {
        let original = AppConfig(
            translator: AzureTranslatorConfig(
                endpoint: "https://api.cognitive.microsofttranslator.com",
                apiKey: "translator-test-key",
                region: "eastasia"
            ),
            azureOpenAI: AzureOpenAIConfig(
                endpoint: "https://sample-resource.openai.azure.com/openai/v1",
                apiKey: "gpt-test-key",
                deploymentName: "gpt-5-deployment",
                supportsVision: true
            )
        )
        let encoded = try? JSONEncoder().encode(original)
        let decoded = encoded.flatMap { try? JSONDecoder().decode(AppConfig.self, from: $0) }

        AzureTestSupport.expect(
            decoded?.translator.endpoint == original.translator.endpoint
                && decoded?.translator.apiKey == original.translator.apiKey
                && decoded?.translator.region == original.translator.region
                && decoded?.azureOpenAI.endpoint == original.azureOpenAI.endpoint
                && decoded?.azureOpenAI.apiKey == original.azureOpenAI.apiKey
                && decoded?.azureOpenAI.deploymentName == original.azureOpenAI.deploymentName
                && decoded?.azureOpenAI.supportsVision == true,
            "TestAzureAppConfigPersistence.test_azureConfigs_codableRoundTripPreservesBothServices"
        )
    }

    static func test_saveThenLoad_restoresAzureConfigsFromKeychainAndSanitizedFile() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("glint-azure-config-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("config.json")
        defer { try? FileManager.default.removeItem(at: directory) }
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

        let original = AppConfig(
            translator: AzureTranslatorConfig(
                endpoint: "https://api.cognitive.microsofttranslator.com",
                apiKey: "translator-test-key",
                region: "eastasia"
            ),
            azureOpenAI: AzureOpenAIConfig(
                endpoint: "https://sample-resource.openai.azure.com/openai/v1/",
                apiKey: "gpt-test-key",
                deploymentName: "gpt-5-deployment",
                supportsVision: true
            )
        )
        let saved = original.save(to: url)
        let loaded = AppConfig.load(from: url)
        let persistedText = (try? String(contentsOf: url, encoding: .utf8)) ?? ""

        AzureTestSupport.expect(
            saved
                && loaded?.translator.region == "eastasia"
                && loaded?.translator.apiKey == "translator-test-key"
                && loaded?.azureOpenAI.deploymentName == "gpt-5-deployment"
                && loaded?.azureOpenAI.apiKey == "gpt-test-key"
                && loaded?.azureOpenAI.supportsVision == true
                && !persistedText.contains("apiKey"),
            "TestAzureAppConfigPersistence.test_saveThenLoad_restoresAzureConfigsFromKeychainAndSanitizedFile"
        )
    }
}

final class TestAzureAppConfigLegacyBackup {
    static func test_unknownOrUndecodableConfig_createsRedactedBackupWithoutOverwritingExistingSafeBackup() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("glint-azure-config-backup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let firstDirectory = root.appendingPathComponent("first-migration", isDirectory: true)
        let firstConfigURL = firstDirectory.appendingPathComponent("config.json")
        let firstBackupURL = firstDirectory.appendingPathComponent("config.pre-azure-backup.json")
        let legacyData = #"""
{
  "active": "MiMo",
  "providers": [{"name":"MiMo","apiKey":"fictional-old-key"}]
}
"""#.data(using: .utf8)!
        try? FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
        try? legacyData.write(to: firstConfigURL)

        let firstLoaded = AppConfig.loadOrCreate(at: firstConfigURL)
        let firstPersisted = AppConfig.load(from: firstConfigURL)
        let firstBackupData = try? Data(contentsOf: firstBackupURL)
        let firstBackupText = firstBackupData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let firstBackupProviders = AzureTestSupport.jsonDictionary(firstBackupData)?["providers"] as? [[String: Any]]
        let firstCreatedDefaults = firstLoaded.translator == AzureTranslatorConfig()
            && firstLoaded.azureOpenAI == AzureOpenAIConfig()
            && firstPersisted?.translator == AzureTranslatorConfig()
            && firstPersisted?.azureOpenAI == AzureOpenAIConfig()

        let secondDirectory = root.appendingPathComponent("existing-backup", isDirectory: true)
        let secondConfigURL = secondDirectory.appendingPathComponent("config.json")
        let secondBackupURL = secondDirectory.appendingPathComponent("config.pre-azure-backup.json")
        let undecodableData = Data([0xFF, 0x00, 0x7B, 0x7D])
        let existingBackupData = #"{"preserved":"original-backup"}"#.data(using: .utf8)!
        try? FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        try? undecodableData.write(to: secondConfigURL)
        try? existingBackupData.write(to: secondBackupURL)

        let secondLoaded = AppConfig.loadOrCreate(at: secondConfigURL)
        let secondPersisted = AppConfig.load(from: secondConfigURL)
        let secondBackupData = try? Data(contentsOf: secondBackupURL)
        let secondCreatedDefaults = secondLoaded.translator == AzureTranslatorConfig()
            && secondLoaded.azureOpenAI == AzureOpenAIConfig()
            && secondPersisted?.translator == AzureTranslatorConfig()
            && secondPersisted?.azureOpenAI == AzureOpenAIConfig()

        AzureTestSupport.expect(
            firstBackupData != legacyData
                && !firstBackupText.contains("fictional-old-key")
                && !firstBackupText.contains("apiKey")
                && firstBackupProviders?.first?["name"] as? String == "MiMo"
                && AzureTestSupport.permissions(at: firstBackupURL) == 0o600
                && firstCreatedDefaults
                && secondBackupData == existingBackupData
                && secondCreatedDefaults,
            "TestAzureAppConfigLegacyBackup.test_unknownOrUndecodableConfig_createsRedactedBackupWithoutOverwritingExistingSafeBackup"
        )
    }
}

final class TestAzureConnectionProbeRequest {
    static func test_unsavedTranslatorValues_buildMinimalRealTranslationProbe() {
        let unsaved = AzureTranslatorConfig(
            endpoint: "https://unsaved-translator.example.com",
            apiKey: "unsaved-translator-key",
            region: "westus2"
        )
        let request = unsaved.buildProbeRequest()
        let body = AzureTestSupport.jsonObject(request?.httpBody) as? [[String: Any]]
        let query = AzureTestSupport.queryItems(request)

        AzureTestSupport.expect(
            request?.url?.host == "unsaved-translator.example.com"
                && request?.httpMethod == "POST"
                && query["api-version"] == "3.0"
                && query["to"] == "zh-Hans"
                && request?.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Key") == "unsaved-translator-key"
                && request?.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Region") == "westus2"
                && body?.count == 1
                && body?.first?["Text"] as? String == "test",
            "TestAzureConnectionProbeRequest.test_unsavedTranslatorValues_buildMinimalRealTranslationProbe"
        )
    }

    static func test_unsavedGptValues_buildMinimalNonStreamingChatProbe() {
        let unsaved = AzureOpenAIConfig(
            endpoint: "https://unsaved-gpt.example.com/openai/v1",
            apiKey: "unsaved-gpt-key",
            deploymentName: "unsaved-deployment",
            supportsVision: false
        )
        let request = unsaved.buildProbeRequest()
        let body = AzureTestSupport.jsonDictionary(request?.httpBody)
        let messages = body?["messages"] as? [[String: Any]]

        AzureTestSupport.expect(
            request?.url?.absoluteString == "https://unsaved-gpt.example.com/openai/v1/chat/completions"
                && request?.httpMethod == "POST"
                && request?.value(forHTTPHeaderField: "api-key") == "unsaved-gpt-key"
                && body?["model"] as? String == "unsaved-deployment"
                && body?["stream"] as? Bool == false
                && messages?.count == 1
                && messages?.first?["role"] as? String == "user"
                && !(messages?.first?["content"] as? String ?? "").isEmpty
                && body?["temperature"] == nil
                && body?["thinking"] == nil,
            "TestAzureConnectionProbeRequest.test_unsavedGptValues_buildMinimalNonStreamingChatProbe"
        )
    }
}

@main
enum AzureServicesTests {
    static func main() {
        TestAzureTranslatorTargetLanguage.test_textContainingChineseCharacter_targetsEnglish()
        TestAzureTranslatorTargetLanguage.test_textWithoutChineseCharacter_targetsSimplifiedChinese()
        TestAzureTranslatorRequest.test_textWithRegion_buildsTranslateV3Request()
        TestAzureTranslatorRequest.test_emptyRegion_omitsRegionHeader()
        TestAzureOpenAIRequest.test_v1EndpointVariants_normalizeToChatCompletions()
        TestAzureOpenAIRequest.test_messagesAndDeployment_buildAzureChatBodyWithoutThinking()
        TestAzureServiceResponseParsing.test_translatorAndChatResponses_returnVisibleText()
        TestAzureServiceResponseParsing.test_sseDeltaDoneAndError_returnTypedEvents()
        TestAzureErrorParsing.test_jsonError_includesCodeAndMessageButRedactsCredentials()
        TestAzureErrorParsing.test_nonJsonError_reportsStatusWithoutLeakingResponseHeadersOrKey()
        TestAzureAppConfigPersistence.test_azureConfigs_codableRoundTripPreservesBothServices()
        TestAzureAppConfigPersistence.test_saveThenLoad_restoresAzureConfigsFromKeychainAndSanitizedFile()
        TestAzureAppConfigLegacyBackup.test_unknownOrUndecodableConfig_createsRedactedBackupWithoutOverwritingExistingSafeBackup()
        TestAzureConnectionProbeRequest.test_unsavedTranslatorValues_buildMinimalRealTranslationProbe()
        TestAzureConnectionProbeRequest.test_unsavedGptValues_buildMinimalNonStreamingChatProbe()

        print(AzureTestSupport.failures == 0 ? "ALL PASS" : "\(AzureTestSupport.failures) FAILURES")
        exit(AzureTestSupport.failures == 0 ? 0 : 1)
    }
}
