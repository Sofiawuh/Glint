import Foundation

// Azure Speech SSML、请求协议、声音映射、探测与错误脱敏黑盒契约测试。
// 不发起网络请求，Endpoint、Key 与正文均为明显虚构样本。
//
// 预期最小运行命令（生产契约存在后）：
//   swiftc -o /tmp/glint_azure_speech_contract_test \
//     TranslationFormatting.swift TranslationDocument.swift Config.swift \
//     ScreenshotHotKey.swift TextCommandHotKey.swift HotKey.swift \
//     azure_speech_contract_tests.swift \
//     -framework Foundation -framework Carbon \
//     && /tmp/glint_azure_speech_contract_test

enum AzureSpeechContractTestSupport {
    static var failures = 0
    static let standardEndpoint = "https://fictional-eastus.tts.speech.microsoft.com/cognitiveservices/v1"
    static let portalEndpoint = "https://fictional-eastus.api.cognitive.microsoft.com/"

    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() {
            print("  ok  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
        }
    }

    static func body(_ request: URLRequest?) -> String {
        guard let data = request?.httpBody else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

final class TestAzureSpeechVoiceMapping {
    static func test_automaticVoice_mapsSupportedLanguageCodesToNeuralVoices() {
        let config = AzureSpeechConfig(
            endpoint: AzureSpeechContractTestSupport.standardEndpoint,
            apiKey: "fictional-speech-key"
        )

        AzureSpeechContractTestSupport.expect(
            config.voiceName(for: "zh-Hans") == "zh-CN-XiaoxiaoNeural"
                && config.voiceName(for: "en") == "en-US-JennyNeural"
                && config.voiceName(for: "ja") == "ja-JP-NanamiNeural"
                && config.voiceName(for: "ko") == "ko-KR-SunHiNeural"
                && config.voiceName(for: "fr") == "fr-FR-DeniseNeural"
                && config.voiceName(for: "de") == "de-DE-KatjaNeural",
            "TestAzureSpeechVoiceMapping.test_automaticVoice_mapsSupportedLanguageCodesToNeuralVoices"
        )
    }

    static func test_legacyExplicitVoice_isIgnoredAndLanguageMappingAlwaysWins() {
        let config = AzureSpeechConfig(
            endpoint: AzureSpeechContractTestSupport.standardEndpoint,
            apiKey: "fictional-speech-key",
            voice: "en-GB-SoniaNeural"
        )

        AzureSpeechContractTestSupport.expect(
            config.voiceName(for: "zh-Hans") == "zh-CN-XiaoxiaoNeural"
                && config.voiceName(for: "ja") == "ja-JP-NanamiNeural"
                && config.voice == AzureSpeechConfig.automaticVoice,
            "TestAzureSpeechVoiceMapping.test_legacyExplicitVoice_isIgnoredAndLanguageMappingAlwaysWins"
        )
    }

    static func test_languageCode_buildsRequestWithMatchingAutomaticNameAndLocale() {
        let config = AzureSpeechConfig(
            endpoint: AzureSpeechContractTestSupport.standardEndpoint,
            apiKey: "fictional-speech-key"
        )
        let request = config.buildSynthesisRequest(
            text: "Synthetic Japanese voice sample.",
            languageCode: "ja"
        )
        let body = AzureSpeechContractTestSupport.body(request)

        AzureSpeechContractTestSupport.expect(
            request != nil
                && body.contains("name=\"ja-JP-NanamiNeural\"")
                && body.contains("xml:lang=\"ja-JP\""),
            "TestAzureSpeechVoiceMapping.test_languageCode_buildsRequestWithMatchingAutomaticNameAndLocale"
        )
    }
}

#if !GLINT_CONTRACT_SKIP_SPEECH_TEXT
final class TestSpeechTextFormatting {
    static func test_speechText_removesMarkdownStructureButPreservesBodyBlankLinesNumbersAndURL() {
        let source = """
        # Quarterly update

        - First item keeps 42.
        1. Visit https://example.invalid/reports/42.

        > Quoted body remains unchanged.

        ```swift
        let total = 42
        print("https://example.invalid/code")
        ```
        """
        let expected = """
        Quarterly update

        First item keeps 42.
        Visit https://example.invalid/reports/42.

        Quoted body remains unchanged.

        let total = 42
        print("https://example.invalid/code")
        """

        let spoken = SpeechTextFormatter.speechText(from: source)

        AzureSpeechContractTestSupport.expect(
            spoken == expected,
            "TestSpeechTextFormatting.test_speechText_removesMarkdownStructureButPreservesBodyBlankLinesNumbersAndURL"
        )
    }

    static func test_synthesisRequest_usesCleanSpeechTextInsteadOfRawEditorMarkdown() {
        let source = """
        # Synthetic heading

        - Item 42
        > Visit https://example.invalid/speech/42

        ```text
        code body 42
        ```
        """
        let spoken = SpeechTextFormatter.speechText(from: source)
        let config = AzureSpeechConfig(
            endpoint: AzureSpeechContractTestSupport.standardEndpoint,
            apiKey: "fictional-speech-key"
        )
        let rawRequest = config.buildSynthesisRequest(text: source, languageCode: "en")
        let cleanRequest = config.buildSynthesisRequest(text: spoken, languageCode: "en")
        let rawBody = AzureSpeechContractTestSupport.body(rawRequest)
        let cleanBody = AzureSpeechContractTestSupport.body(cleanRequest)

        AzureSpeechContractTestSupport.expect(
            rawRequest != nil
                && rawBody == cleanBody
                && rawBody.contains("Synthetic heading")
                && rawBody.contains("Item 42")
                && rawBody.contains("https://example.invalid/speech/42")
                && rawBody.contains("code body 42")
                && !rawBody.contains("# Synthetic heading")
                && !rawBody.contains("- Item 42")
                && !rawBody.contains("&gt; Visit")
                && !rawBody.contains("```"),
            "TestSpeechTextFormatting.test_synthesisRequest_usesCleanSpeechTextInsteadOfRawEditorMarkdown"
        )
    }
}
#endif

final class TestAzureSpeechRequest {
    static func test_synthesisRequest_usesConfiguredEndpointHeadersAudioFormatAndEscapedSSML() {
        let config = AzureSpeechConfig(
            endpoint: AzureSpeechContractTestSupport.portalEndpoint,
            apiKey: "fictional-speech-key"
        )
        let request = config.buildSynthesisRequest(
            text: "A&B <tag> \"quoted\" 'apostrophe'\n\nSecond paragraph.",
            languageCode: "en"
        )
        let body = AzureSpeechContractTestSupport.body(request)

        AzureSpeechContractTestSupport.expect(
            request?.url?.absoluteString == AzureSpeechContractTestSupport.standardEndpoint
                && request?.httpMethod == "POST"
                && request?.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Key") == "fictional-speech-key"
                && request?.value(forHTTPHeaderField: "Content-Type") == "application/ssml+xml"
                && request?.value(forHTTPHeaderField: "X-Microsoft-OutputFormat") == "audio-24khz-48kbitrate-mono-mp3"
                && body.contains("<speak")
                && body.contains("xml:lang=\"en-US\"")
                && body.contains("name=\"en-US-JennyNeural\"")
                && body.contains("A&amp;B &lt;tag&gt; &quot;quoted&quot; &apos;apostrophe&apos;")
                && body.contains("<break")
                && !body.contains("A&B <tag>"),
            "TestAzureSpeechRequest.test_synthesisRequest_usesConfiguredEndpointHeadersAudioFormatAndEscapedSSML"
        )
    }

    static func test_probeRequest_usesFixedMinimalTextAndNeverIncludesCallerContent() {
        let config = AzureSpeechConfig(
            endpoint: AzureSpeechContractTestSupport.standardEndpoint,
            apiKey: "fictional-speech-key"
        )
        let request = config.buildProbeRequest()
        let body = AzureSpeechContractTestSupport.body(request)

        AzureSpeechContractTestSupport.expect(
            request != nil
                && body.count < 1_024
                && body.contains("<speak")
                && !body.contains("selected-user-text")
                && request?.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Key") == "fictional-speech-key",
            "TestAzureSpeechRequest.test_probeRequest_usesFixedMinimalTextAndNeverIncludesCallerContent"
        )
    }

    static func test_missingEndpointOrKey_refusesToBuildRequest() {
        let missingEndpoint = AzureSpeechConfig(endpoint: "", apiKey: "fictional-key")
        let missingKey = AzureSpeechConfig(
            endpoint: AzureSpeechContractTestSupport.standardEndpoint,
            apiKey: ""
        )

        AzureSpeechContractTestSupport.expect(
            missingEndpoint.buildProbeRequest() == nil
                && missingKey.buildProbeRequest() == nil,
            "TestAzureSpeechRequest.test_missingEndpointOrKey_refusesToBuildRequest"
        )
    }

    static func test_legacyUnsafeVoiceValues_areIgnoredAndNeverEnterSSMLAttributes() {
        let unsafeVoices = [
            "en-US-Jenny\"Neural",
            "en-US-Jenny&Neural",
            "en-US-Jenny<Neural",
            "en-US-Jenny>Neural",
            "en-US JennyNeural",
            " en-US-JennyNeural",
            "en-US-JennyNeural\n",
            "en-US-JennyNeural\"/><voice name=\"injected"
        ]

        let allIgnored = unsafeVoices.allSatisfy { voice in
            let config = AzureSpeechConfig(
                endpoint: AzureSpeechContractTestSupport.standardEndpoint,
                apiKey: "fictional-speech-key",
                voice: voice
            )
            let request = config.buildSynthesisRequest(
                text: "Synthetic voice validation text.",
                languageCode: "en"
            )
            let body = AzureSpeechContractTestSupport.body(request)
            return request != nil
                && body.contains("name=\"en-US-JennyNeural\"")
                && !body.contains(voice)
        }

        AzureSpeechContractTestSupport.expect(
            allIgnored,
            "TestAzureSpeechRequest.test_legacyUnsafeVoiceValues_areIgnoredAndNeverEnterSSMLAttributes"
        )
    }
}

final class TestAzureSpeechErrorSanitization {
    static func test_authenticationError_returnsSpecificSafeMessageAndRedactsSecrets() {
        let key = "fictional-speech-key-never-log"
        let querySecret = "fictional-query-secret"
        let queryToken = "fictional-token-value"
        let endpoint = "\(AzureSpeechContractTestSupport.standardEndpoint)?sig=\(querySecret)&token=\(queryToken)"
        let config = AzureSpeechConfig(
            endpoint: endpoint,
            apiKey: key
        )
        let data = #"{"error":{"code":"Unauthorized","message":"fictional-query-secret fictional-token-value fictional-speech-key-never-log"}}"#
            .data(using: .utf8)!
        let message = config.parseError(statusCode: 401, data: data)

        AzureSpeechContractTestSupport.expect(
            message == "Speech Key 无效或资源区域不匹配"
                && !message.contains(key)
                && !message.contains(querySecret)
                && !message.contains(queryToken)
                && !message.contains("?sig="),
            "TestAzureSpeechErrorSanitization.test_authenticationError_returnsSpecificSafeMessageAndRedactsSecrets"
        )
    }

    #if !GLINT_CONTRACT_SKIP_NETWORK_ERROR
    static func test_networkError_preservesSafeDescriptionButRedactsEndpointQueryAndKey() {
        let key = "fictional-speech-key-never-log"
        let querySecret = "fictional-query-secret"
        let queryToken = "fictional-token-value"
        let endpoint = "\(AzureSpeechContractTestSupport.standardEndpoint)?sig=\(querySecret)&token=\(queryToken)"
        let config = AzureSpeechConfig(
            endpoint: endpoint,
            apiKey: key
        )
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorTimedOut,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "The fictional request timed out at \(endpoint) using \(key)."
            ]
        )

        let message = config.parseNetworkError(error)

        AzureSpeechContractTestSupport.expect(
            message.lowercased().contains("timed out")
                && !message.contains(key)
                && !message.contains(querySecret)
                && !message.contains(queryToken)
                && !message.contains("?sig=")
                && !message.contains("token="),
            "TestAzureSpeechErrorSanitization.test_networkError_preservesSafeDescriptionButRedactsEndpointQueryAndKey"
        )
    }
    #endif
}

@main
enum AzureSpeechContractTests {
    static func main() {
        TestAzureSpeechVoiceMapping.test_automaticVoice_mapsSupportedLanguageCodesToNeuralVoices()
        TestAzureSpeechVoiceMapping.test_legacyExplicitVoice_isIgnoredAndLanguageMappingAlwaysWins()
        TestAzureSpeechVoiceMapping.test_languageCode_buildsRequestWithMatchingAutomaticNameAndLocale()
        #if !GLINT_CONTRACT_SKIP_SPEECH_TEXT
        TestSpeechTextFormatting.test_speechText_removesMarkdownStructureButPreservesBodyBlankLinesNumbersAndURL()
        TestSpeechTextFormatting.test_synthesisRequest_usesCleanSpeechTextInsteadOfRawEditorMarkdown()
        #endif
        TestAzureSpeechRequest.test_synthesisRequest_usesConfiguredEndpointHeadersAudioFormatAndEscapedSSML()
        TestAzureSpeechRequest.test_probeRequest_usesFixedMinimalTextAndNeverIncludesCallerContent()
        TestAzureSpeechRequest.test_missingEndpointOrKey_refusesToBuildRequest()
        TestAzureSpeechRequest.test_legacyUnsafeVoiceValues_areIgnoredAndNeverEnterSSMLAttributes()
        TestAzureSpeechErrorSanitization.test_authenticationError_returnsSpecificSafeMessageAndRedactsSecrets()
        #if !GLINT_CONTRACT_SKIP_NETWORK_ERROR
        TestAzureSpeechErrorSanitization.test_networkError_preservesSafeDescriptionButRedactsEndpointQueryAndKey()
        #endif

        print(
            AzureSpeechContractTestSupport.failures == 0
                ? "ALL PASS"
                : "\(AzureSpeechContractTestSupport.failures) FAILURES"
        )
        exit(AzureSpeechContractTestSupport.failures == 0 ? 0 : 1)
    }
}
