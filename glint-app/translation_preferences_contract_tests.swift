import Foundation

// 翻译偏好与 Speech 配置持久化黑盒契约测试（不进入 App 打包）。
// 仅使用临时文件和明显虚构配置，不读取真实 ~/.config/glint/config.json。
//
// 预期最小运行命令（生产契约存在后）：
//   swiftc -o /tmp/glint_translation_preferences_contract_test \
//     TranslationFormatting.swift TranslationDocument.swift Config.swift \
//     ScreenshotHotKey.swift TextCommandHotKey.swift HotKey.swift \
//     translation_preferences_contract_tests.swift -framework Foundation -framework Carbon \
//     && /tmp/glint_translation_preferences_contract_test

enum TranslationPreferencesContractTestSupport {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() {
            print("  ok  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
        }
    }

    static func temporaryConfigURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("glint-smart-translation-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("config.json")
    }
}

final class TestTranslationPreferencesDefaults {
    static func test_newConfig_defaultsToAutomaticTargetAndSmartFormatting() {
        let config = AppConfig()

        TranslationPreferencesContractTestSupport.expect(
            config.translationPreferences.targetMode == .automatic
                && config.translationPreferences.fixedTargetLanguage == "zh-Hans"
                && config.translationPreferences.formattingMode == .smart,
            "TestTranslationPreferencesDefaults.test_newConfig_defaultsToAutomaticTargetAndSmartFormatting"
        )
    }

    static func test_automaticAndFixedModes_routeTargetsWithoutChangingSavedFixedLanguage() {
        let automatic = TranslationPreferences(
            targetMode: .automatic,
            fixedTargetLanguage: "ja",
            formattingMode: .smart
        )
        let fixed = TranslationPreferences(
            targetMode: .fixed,
            fixedTargetLanguage: "fr",
            formattingMode: .strict
        )

        TranslationPreferencesContractTestSupport.expect(
            automatic.targetLanguage(for: "含有中文的虚构样本") == "en"
                && automatic.targetLanguage(for: "Synthetic English sample") == "zh-Hans"
                && automatic.fixedTargetLanguage == "ja"
                && fixed.targetLanguage(for: "任意原文") == "fr",
            "TestTranslationPreferencesDefaults.test_automaticAndFixedModes_routeTargetsWithoutChangingSavedFixedLanguage"
        )
    }
}

final class TestTranslationPreferencesMigration {
    static func test_legacyConfigMissingNewFields_decodesDefaultsAndPreservesExistingServicesAndHotKeys() {
        let legacyJSON = #"""
        {
          "translator": {
            "endpoint": "https://translator.invalid.example",
            "apiKey": "fictional-translator-key",
            "region": "fictional-region"
          },
          "azureOpenAI": {
            "endpoint": "https://openai.invalid.example/openai/v1",
            "apiKey": "fictional-openai-key",
            "deploymentName": "fictional-deployment",
            "supportsVision": true
          },
          "screenshotHotKey": {"keyCode": 15, "modifiers": 786432},
          "textCommandHotKey": {"keyCode": 50, "modifiers": 0}
        }
        """#.data(using: .utf8)!

        let decoded = try? JSONDecoder().decode(AppConfig.self, from: legacyJSON)

        TranslationPreferencesContractTestSupport.expect(
            decoded?.translationPreferences == TranslationPreferences()
                && decoded?.speech == AzureSpeechConfig()
                && decoded?.translator.endpoint == "https://translator.invalid.example"
                && decoded?.translator.apiKey == "fictional-translator-key"
                && decoded?.azureOpenAI.deploymentName == "fictional-deployment"
                && decoded?.azureOpenAI.supportsVision == true
                && decoded?.screenshotHotKey.keyCode == 15
                && decoded?.textCommandHotKey.keyCode == 50,
            "TestTranslationPreferencesMigration.test_legacyConfigMissingNewFields_decodesDefaultsAndPreservesExistingServicesAndHotKeys"
        )
    }
}

final class TestTranslationPreferencesPersistence {
    static func test_saveThenLoad_roundTripsFixedTargetFormattingAndSpeechIndependently() {
        let url = TranslationPreferencesContractTestSupport.temporaryConfigURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let original = AppConfig(
            translator: AzureTranslatorConfig(
                endpoint: "https://translator.invalid.example",
                apiKey: "fictional-translator-key",
                region: "fictional-region"
            ),
            azureOpenAI: AzureOpenAIConfig(
                endpoint: "https://openai.invalid.example/openai/v1",
                apiKey: "fictional-openai-key",
                deploymentName: "fictional-deployment",
                supportsVision: false
            ),
            screenshotHotKey: ScreenshotHotKey(
                keyCode: 14,
                modifiers: ScreenshotHotKey.default.modifiers
            ),
            textCommandHotKey: TextCommandHotKey(keyCode: 50, modifiers: 0),
            translationPreferences: TranslationPreferences(
                targetMode: .fixed,
                fixedTargetLanguage: "de",
                formattingMode: .strict
            ),
            speech: AzureSpeechConfig(
                endpoint: "https://speech.invalid.example/cognitiveservices/v1",
                apiKey: "fictional-speech-key",
                voice: AzureSpeechConfig.automaticVoice
            )
        )

        let saved = original.save(to: url)
        let loaded = AppConfig.load(from: url)

        TranslationPreferencesContractTestSupport.expect(
            saved
                && loaded?.translationPreferences.targetMode == .fixed
                && loaded?.translationPreferences.fixedTargetLanguage == "de"
                && loaded?.translationPreferences.formattingMode == .strict
                && loaded?.speech.endpoint == "https://speech.invalid.example/cognitiveservices/v1"
                && loaded?.speech.apiKey == "fictional-speech-key"
                && loaded?.translator.region == "fictional-region"
                && loaded?.azureOpenAI.deploymentName == "fictional-deployment"
                && loaded?.screenshotHotKey.keyCode == 14
                && loaded?.textCommandHotKey.keyCode == 50,
            "TestTranslationPreferencesPersistence.test_saveThenLoad_roundTripsFixedTargetFormattingAndSpeechIndependently"
        )
    }

    static func test_setTranslationPreferences_commitsOnlyPreferencesAndPersistsAtomically() {
        let url = TranslationPreferencesContractTestSupport.temporaryConfigURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let config = AppConfig(
            translator: AzureTranslatorConfig(
                endpoint: "https://translator.invalid.example",
                apiKey: "fictional-translator-key",
                region: "fictional-region"
            ),
            azureOpenAI: AzureOpenAIConfig(
                endpoint: "https://openai.invalid.example/openai/v1",
                apiKey: "fictional-openai-key",
                deploymentName: "fictional-deployment",
                supportsVision: true
            ),
            screenshotHotKey: ScreenshotHotKey(
                keyCode: 14,
                modifiers: ScreenshotHotKey.default.modifiers
            ),
            textCommandHotKey: TextCommandHotKey(keyCode: 50, modifiers: 0),
            translationPreferences: TranslationPreferences(
                targetMode: .automatic,
                fixedTargetLanguage: "ja",
                formattingMode: .smart
            ),
            speech: AzureSpeechConfig(
                endpoint: "https://speech.invalid.example/cognitiveservices/v1",
                apiKey: "fictional-speech-key",
                voice: "en-GB-SoniaNeural"
            )
        )
        let updated = TranslationPreferences(
            targetMode: .fixed,
            fixedTargetLanguage: "de",
            formattingMode: .strict
        )

        let committed = config.setTranslationPreferences(updated, to: url)
        let loaded = AppConfig.load(from: url)

        TranslationPreferencesContractTestSupport.expect(
            committed
                && config.translationPreferences == updated
                && loaded?.translationPreferences == updated
                && config.translator.endpoint == "https://translator.invalid.example"
                && config.translator.apiKey == "fictional-translator-key"
                && config.translator.region == "fictional-region"
                && loaded?.translator.endpoint == "https://translator.invalid.example"
                && loaded?.translator.apiKey == "fictional-translator-key"
                && loaded?.translator.region == "fictional-region"
                && config.azureOpenAI.endpoint == "https://openai.invalid.example/openai/v1"
                && config.azureOpenAI.apiKey == "fictional-openai-key"
                && config.azureOpenAI.deploymentName == "fictional-deployment"
                && config.azureOpenAI.supportsVision
                && loaded?.azureOpenAI.endpoint == "https://openai.invalid.example/openai/v1"
                && loaded?.azureOpenAI.apiKey == "fictional-openai-key"
                && loaded?.azureOpenAI.deploymentName == "fictional-deployment"
                && loaded?.azureOpenAI.supportsVision == true
                && config.speech.endpoint == "https://speech.invalid.example/cognitiveservices/v1"
                && config.speech.apiKey == "fictional-speech-key"
                && config.speech.voice == "en-GB-SoniaNeural"
                && loaded?.speech.endpoint == "https://speech.invalid.example/cognitiveservices/v1"
                && loaded?.speech.apiKey == "fictional-speech-key"
                && loaded?.speech.voice == "en-GB-SoniaNeural"
                && config.screenshotHotKey.keyCode == 14
                && config.screenshotHotKey.modifiers == ScreenshotHotKey.default.modifiers
                && loaded?.screenshotHotKey.keyCode == 14
                && loaded?.screenshotHotKey.modifiers == ScreenshotHotKey.default.modifiers
                && config.textCommandHotKey.keyCode == 50
                && config.textCommandHotKey.modifiers == 0
                && loaded?.textCommandHotKey.keyCode == 50
                && loaded?.textCommandHotKey.modifiers == 0,
            "TestTranslationPreferencesPersistence.test_setTranslationPreferences_commitsOnlyPreferencesAndPersistsAtomically"
        )
    }

    static func test_setTranslationPreferences_whenPersistenceFails_rollsBackInMemoryPreferences() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("glint-preference-rollback-\(UUID().uuidString)", isDirectory: true)
        let blockingFile = root.appendingPathComponent("not-a-directory")
        let impossibleURL = blockingFile.appendingPathComponent("config.json")
        defer { try? FileManager.default.removeItem(at: root) }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? Data("blocking-file".utf8).write(to: blockingFile)

        let original = TranslationPreferences(
            targetMode: .automatic,
            fixedTargetLanguage: "fr",
            formattingMode: .smart
        )
        let config = AppConfig(
            translator: AzureTranslatorConfig(
                endpoint: "https://translator.invalid.example",
                apiKey: "fictional-translator-key",
                region: "fictional-region"
            ),
            azureOpenAI: AzureOpenAIConfig(
                endpoint: "https://openai.invalid.example/openai/v1",
                apiKey: "fictional-openai-key",
                deploymentName: "fictional-deployment",
                supportsVision: false
            ),
            screenshotHotKey: ScreenshotHotKey(
                keyCode: 14,
                modifiers: ScreenshotHotKey.default.modifiers
            ),
            textCommandHotKey: TextCommandHotKey(keyCode: 50, modifiers: 0),
            translationPreferences: original,
            speech: AzureSpeechConfig(
                endpoint: "https://speech.invalid.example/cognitiveservices/v1",
                apiKey: "fictional-speech-key",
                voice: AzureSpeechConfig.automaticVoice
            )
        )
        let attempted = TranslationPreferences(
            targetMode: .fixed,
            fixedTargetLanguage: "ko",
            formattingMode: .strict
        )

        let committed = config.setTranslationPreferences(attempted, to: impossibleURL)

        TranslationPreferencesContractTestSupport.expect(
            !committed
                && config.translationPreferences == original
                && config.translator.endpoint == "https://translator.invalid.example"
                && config.azureOpenAI.deploymentName == "fictional-deployment"
                && config.speech.endpoint == "https://speech.invalid.example/cognitiveservices/v1"
                && config.screenshotHotKey.keyCode == 14
                && config.textCommandHotKey.keyCode == 50
                && !FileManager.default.fileExists(atPath: impossibleURL.path),
            "TestTranslationPreferencesPersistence.test_setTranslationPreferences_whenPersistenceFails_rollsBackInMemoryPreferences"
        )
    }
}

@main
enum TranslationPreferencesContractTests {
    static func main() {
        TestTranslationPreferencesDefaults.test_newConfig_defaultsToAutomaticTargetAndSmartFormatting()
        TestTranslationPreferencesDefaults.test_automaticAndFixedModes_routeTargetsWithoutChangingSavedFixedLanguage()
        TestTranslationPreferencesMigration.test_legacyConfigMissingNewFields_decodesDefaultsAndPreservesExistingServicesAndHotKeys()
        TestTranslationPreferencesPersistence.test_saveThenLoad_roundTripsFixedTargetFormattingAndSpeechIndependently()
        TestTranslationPreferencesPersistence.test_setTranslationPreferences_commitsOnlyPreferencesAndPersistsAtomically()
        TestTranslationPreferencesPersistence.test_setTranslationPreferences_whenPersistenceFails_rollsBackInMemoryPreferences()

        print(
            TranslationPreferencesContractTestSupport.failures == 0
                ? "ALL PASS"
                : "\(TranslationPreferencesContractTestSupport.failures) FAILURES"
        )
        exit(TranslationPreferencesContractTestSupport.failures == 0 ? 0 : 1)
    }
}
