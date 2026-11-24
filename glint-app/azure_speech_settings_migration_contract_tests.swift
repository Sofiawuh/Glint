import Foundation

// Azure Speech 两字段设置、Portal Endpoint 转换、自动 Voice 与旧配置迁移黑盒契约。
// 不发起网络请求；Endpoint、Key 和正文均为虚构样本。
//
// 预期最小运行命令：
//   swiftc -o /tmp/glint_azure_speech_settings_migration_contract_test \
//     TranslationFormatting.swift TranslationDocument.swift Config.swift \
//     ScreenshotHotKey.swift TextCommandHotKey.swift HotKey.swift \
//     azure_speech_settings_migration_contract_tests.swift \
//     -framework Foundation -framework Carbon \
//     && /tmp/glint_azure_speech_settings_migration_contract_test

enum AzureSpeechSettingsMigrationContractTestSupport {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() {
            print("  ok  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
        }
    }

    static func encodedObject(_ config: AzureSpeechConfig) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(config) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

final class TestAzureSpeechEndpointNormalization {
    static func test_portalEndpoint_buildsRegionalTTSRequestURL() {
        let config = AzureSpeechConfig(
            endpoint: "https://fictional-eastus.api.cognitive.microsoft.com/",
            apiKey: "fictional-speech-key"
        )
        let request = config.buildSynthesisRequest(
            text: "Fictional speech body.",
            languageCode: "en"
        )

        AzureSpeechSettingsMigrationContractTestSupport.expect(
            request?.url?.absoluteString == "https://fictional-eastus.tts.speech.microsoft.com/cognitiveservices/v1",
            "TestAzureSpeechEndpointNormalization.test_portalEndpoint_buildsRegionalTTSRequestURL"
        )
    }

    static func test_standardTTSEndpoint_remainsTheRuntimeRequestURL() {
        let endpoint = "https://fictional-westus.tts.speech.microsoft.com/cognitiveservices/v1"
        let config = AzureSpeechConfig(endpoint: endpoint, apiKey: "fictional-speech-key")

        AzureSpeechSettingsMigrationContractTestSupport.expect(
            config.buildSynthesisRequest(
                text: "Fictional speech body.",
                languageCode: "en"
            )?.url?.absoluteString == endpoint,
            "TestAzureSpeechEndpointNormalization.test_standardTTSEndpoint_remainsTheRuntimeRequestURL"
        )
    }
}

final class TestAzureSpeechAutomaticVoice {
    static func test_languageAlwaysSelectsNeuralVoiceWithoutAUserVoiceSetting() {
        let config = AzureSpeechConfig(
            endpoint: "https://fictional-eastus.api.cognitive.microsoft.com/",
            apiKey: "fictional-speech-key"
        )

        AzureSpeechSettingsMigrationContractTestSupport.expect(
            config.voiceName(for: "zh-Hans") == "zh-CN-XiaoxiaoNeural"
                && config.voiceName(for: "en") == "en-US-JennyNeural"
                && config.voiceName(for: "ja") == "ja-JP-NanamiNeural"
                && config.voiceName(for: "fr") == "fr-FR-DeniseNeural",
            "TestAzureSpeechAutomaticVoice.test_languageAlwaysSelectsNeuralVoiceWithoutAUserVoiceSetting"
        )
    }
}

final class TestAzureSpeechLegacyMigration {
    static func test_legacyVoiceAndRegion_areIgnoredWhileEndpointAndKeyArePreserved() {
        let legacy = #"{"endpoint":"https://fictional-eastus.api.cognitive.microsoft.com/","apiKey":"fictional-speech-key","region":"fictional-eastus","voice":"fictional-eastus"}"#
            .data(using: .utf8)!
        let decoded = try? JSONDecoder().decode(AzureSpeechConfig.self, from: legacy)
        let request = decoded?.buildSynthesisRequest(
            text: "Fictional migrated speech body.",
            languageCode: "ja"
        )

        AzureSpeechSettingsMigrationContractTestSupport.expect(
            decoded?.endpoint == "https://fictional-eastus.api.cognitive.microsoft.com/"
                && decoded?.apiKey == "fictional-speech-key"
                && decoded?.voiceName(for: "ja") == "ja-JP-NanamiNeural"
                && request?.url?.absoluteString == "https://fictional-eastus.tts.speech.microsoft.com/cognitiveservices/v1",
            "TestAzureSpeechLegacyMigration.test_legacyVoiceAndRegion_areIgnoredWhileEndpointAndKeyArePreserved"
        )
    }

    static func test_newEncoding_persistsOnlyEndpointAndAPIKey() {
        let config = AzureSpeechConfig(
            endpoint: "https://fictional-eastus.api.cognitive.microsoft.com/",
            apiKey: "fictional-speech-key"
        )
        let object = AzureSpeechSettingsMigrationContractTestSupport.encodedObject(config)
        let encodedKeys = Set(object.map { Array($0.keys) } ?? [])

        AzureSpeechSettingsMigrationContractTestSupport.expect(
            encodedKeys == Set(["endpoint", "apiKey"])
                && object?["endpoint"] as? String == "https://fictional-eastus.api.cognitive.microsoft.com/"
                && object?["apiKey"] as? String == "fictional-speech-key"
                && object?["voice"] == nil
                && object?["region"] == nil,
            "TestAzureSpeechLegacyMigration.test_newEncoding_persistsOnlyEndpointAndAPIKey"
        )
    }
}

@main
enum AzureSpeechSettingsMigrationContractTests {
    static func main() {
        TestAzureSpeechEndpointNormalization.test_portalEndpoint_buildsRegionalTTSRequestURL()
        TestAzureSpeechEndpointNormalization.test_standardTTSEndpoint_remainsTheRuntimeRequestURL()
        TestAzureSpeechAutomaticVoice.test_languageAlwaysSelectsNeuralVoiceWithoutAUserVoiceSetting()
        TestAzureSpeechLegacyMigration.test_legacyVoiceAndRegion_areIgnoredWhileEndpointAndKeyArePreserved()
        TestAzureSpeechLegacyMigration.test_newEncoding_persistsOnlyEndpointAndAPIKey()

        print(
            AzureSpeechSettingsMigrationContractTestSupport.failures == 0
                ? "ALL PASS"
                : "\(AzureSpeechSettingsMigrationContractTestSupport.failures) FAILURES"
        )
        exit(AzureSpeechSettingsMigrationContractTestSupport.failures == 0 ? 0 : 1)
    }
}
