import Foundation

// 翻译文本处理模式与兼容迁移黑盒契约测试（不进入 App 打包）。
// 测试只使用内存 JSON 和虚构配置，不读取真实 Glint 配置。
//
// 预期最小运行命令（生产契约存在后）：
//   swiftc -o /tmp/glint_translation_processing_modes_contract_test \
//     TranslationFormatting.swift TranslationDocument.swift Config.swift \
//     ScreenshotHotKey.swift TextCommandHotKey.swift HotKey.swift \
//     translation_processing_modes_contract_tests.swift \
//     -framework Foundation -framework Carbon \
//     && /tmp/glint_translation_processing_modes_contract_test

enum TranslationProcessingModesContractTestSupport {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() {
            print("  ok  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
        }
    }
}

final class TestTranslationProcessingModes {
    static func test_publicModes_exposeStrictSmartAndPolishWithStablePersistenceValues() {
        let modes = TranslationFormattingMode.allCases

        TranslationProcessingModesContractTestSupport.expect(
            modes == [.strict, .smart, .polish]
                && TranslationFormattingMode.strict.rawValue == "strict"
                && TranslationFormattingMode.smart.rawValue == "smart"
                && TranslationFormattingMode.polish.rawValue == "polish"
                && TranslationFormattingMode.strict.displayName == "严格保留"
                && TranslationFormattingMode.smart.displayName == "智能排版"
                && TranslationFormattingMode.polish.displayName == "智能润色",
            "TestTranslationProcessingModes.test_publicModes_exposeStrictSmartAndPolishWithStablePersistenceValues"
        )
    }

    static func test_newPreferences_defaultToAutomaticTargetAndSmartProcessing() {
        let preferences = TranslationPreferences()

        TranslationProcessingModesContractTestSupport.expect(
            preferences.targetMode == .automatic
                && preferences.fixedTargetLanguage == "zh-Hans"
                && preferences.formattingMode == .smart,
            "TestTranslationProcessingModes.test_newPreferences_defaultToAutomaticTargetAndSmartProcessing"
        )
    }
}

final class TestTranslationProcessingModeMigration {
    static func test_legacyStrictAndSmartValues_decodeWithoutChangingTheirMeaning() {
        let decoder = JSONDecoder()
        let strict = try? decoder.decode(
            TranslationPreferences.self,
            from: #"{"targetMode":"fixed","fixedTargetLanguage":"ja","formattingMode":"strict"}"#.data(using: .utf8)!
        )
        let smart = try? decoder.decode(
            TranslationPreferences.self,
            from: #"{"targetMode":"automatic","fixedTargetLanguage":"fr","formattingMode":"smart"}"#.data(using: .utf8)!
        )

        TranslationProcessingModesContractTestSupport.expect(
            strict?.formattingMode == .strict
                && strict?.targetMode == .fixed
                && strict?.fixedTargetLanguage == "ja"
                && smart?.formattingMode == .smart
                && smart?.targetMode == .automatic
                && smart?.fixedTargetLanguage == "fr",
            "TestTranslationProcessingModeMigration.test_legacyStrictAndSmartValues_decodeWithoutChangingTheirMeaning"
        )
    }

    static func test_polishSelection_roundTripsAsTheLastWorkbenchChoice() {
        let original = TranslationPreferences(
            targetMode: .fixed,
            fixedTargetLanguage: "de",
            formattingMode: .polish
        )
        let data = try? JSONEncoder().encode(original)
        let decoded = data.flatMap { try? JSONDecoder().decode(TranslationPreferences.self, from: $0) }

        TranslationProcessingModesContractTestSupport.expect(
            decoded == original,
            "TestTranslationProcessingModeMigration.test_polishSelection_roundTripsAsTheLastWorkbenchChoice"
        )
    }
}

@main
enum TranslationProcessingModesContractTests {
    static func main() {
        TestTranslationProcessingModes.test_publicModes_exposeStrictSmartAndPolishWithStablePersistenceValues()
        TestTranslationProcessingModes.test_newPreferences_defaultToAutomaticTargetAndSmartProcessing()
        TestTranslationProcessingModeMigration.test_legacyStrictAndSmartValues_decodeWithoutChangingTheirMeaning()
        TestTranslationProcessingModeMigration.test_polishSelection_roundTripsAsTheLastWorkbenchChoice()

        print(
            TranslationProcessingModesContractTestSupport.failures == 0
                ? "ALL PASS"
                : "\(TranslationProcessingModesContractTestSupport.failures) FAILURES"
        )
        exit(TranslationProcessingModesContractTestSupport.failures == 0 ? 0 : 1)
    }
}
