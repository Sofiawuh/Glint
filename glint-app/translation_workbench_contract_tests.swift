import Foundation

// 双编辑区翻译工作台、重译代际、互斥朗读与历史同 ID 更新黑盒契约测试。
// 不创建 UI、不访问网络、音频、剪贴板、选中文字或真实配置。
//
// 预期最小运行命令（生产契约存在后）：
//   swiftc -o /tmp/glint_translation_workbench_contract_test \
//     RecentResults.swift TranslationFormatting.swift TranslationWorkbench.swift \
//     translation_workbench_contract_tests.swift -framework Foundation \
//     && /tmp/glint_translation_workbench_contract_test

enum TranslationWorkbenchContractTestSupport {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() {
            print("  ok  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
        }
    }

    static func makeWorkbench() -> TranslationWorkbenchState {
        TranslationWorkbenchState(
            historyID: "translation-history-stable-id",
            sourceText: "Initial source text.",
            translatedText: "初始译文。",
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            formattingMode: .smart
        )
    }
}

final class TestTranslationWorkbenchEditing {
    static func test_twoEditors_areIndependentlyEditableAndRetranslationReadsCurrentSource() {
        var workbench = TranslationWorkbenchContractTestSupport.makeWorkbench()
        workbench.editSource("Edited source\nwith a visual wrap.")
        workbench.editTranslation("用户手工修改后的译文。")

        let request = workbench.beginRetranslation()

        TranslationWorkbenchContractTestSupport.expect(
            workbench.sourceText == "Edited source\nwith a visual wrap."
                && workbench.translatedText == "用户手工修改后的译文。"
                && request?.sourceText == "Edited source\nwith a visual wrap."
                && request?.targetLanguage == "zh-Hans"
                && request?.formattingMode == .smart
                && workbench.isRequestInFlight
                && !workbench.canRetranslate
                && !workbench.canChangeTargetLanguage
                && !workbench.canSwitchRecentResult,
            "TestTranslationWorkbenchEditing.test_twoEditors_areIndependentlyEditableAndRetranslationReadsCurrentSource"
        )
    }
}

final class TestTranslationWorkbenchGeneration {
    static func test_cancelledOlderRequest_cannotOverwriteNewerEditedSourceOrTranslation() {
        var workbench = TranslationWorkbenchContractTestSupport.makeWorkbench()
        workbench.editSource("First edited source")
        guard let first = workbench.beginRetranslation() else {
            TranslationWorkbenchContractTestSupport.expect(
                false,
                "TestTranslationWorkbenchGeneration.test_cancelledOlderRequest_cannotOverwriteNewerEditedSourceOrTranslation"
            )
            return
        }

        workbench.cancelRetranslation()
        workbench.editSource("Second edited source")
        guard let second = workbench.beginRetranslation() else {
            TranslationWorkbenchContractTestSupport.expect(
                false,
                "TestTranslationWorkbenchGeneration.test_cancelledOlderRequest_cannotOverwriteNewerEditedSourceOrTranslation"
            )
            return
        }

        let acceptedLateFirst = workbench.completeRetranslation(
            generation: first.generation,
            translatedText: "晚到的旧译文",
            detectedSourceLanguage: "en"
        )
        let acceptedSecond = workbench.completeRetranslation(
            generation: second.generation,
            translatedText: "第二次编辑后的新译文",
            detectedSourceLanguage: "en"
        )

        TranslationWorkbenchContractTestSupport.expect(
            !acceptedLateFirst
                && acceptedSecond
                && workbench.sourceText == "Second edited source"
                && workbench.translatedText == "第二次编辑后的新译文"
                && !workbench.isRequestInFlight
                && workbench.canRetranslate
                && workbench.canChangeTargetLanguage
                && workbench.canSwitchRecentResult,
            "TestTranslationWorkbenchGeneration.test_cancelledOlderRequest_cannotOverwriteNewerEditedSourceOrTranslation"
        )
    }
}

final class TestTranslationWorkbenchTargetMode {
    static func test_automaticMode_usesDetectedLanguageForTheNextTargetAndKeepsSourceLanguageCurrent() {
        var workbench = TranslationWorkbenchState(
            historyID: "automatic-target-history-id",
            sourceText: "Synthetic source.",
            translatedText: "虚构译文。",
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            targetMode: .automatic,
            fixedTargetLanguage: "fr",
            formattingMode: .smart
        )
        let expectations = [
            (detected: "ja", nextTarget: "zh-Hans"),
            (detected: "ko", nextTarget: "zh-Hans"),
            (detected: "en", nextTarget: "zh-Hans"),
            (detected: "zh", nextTarget: "en"),
            (detected: "zh-Hans", nextTarget: "en")
        ]
        var observed: [(detected: String, nextTarget: String?, sourceLanguage: String)] = []

        for item in expectations {
            guard let current = workbench.beginRetranslation() else {
                observed.append((item.detected, nil, workbench.sourceLanguage))
                continue
            }
            let accepted = workbench.completeRetranslation(
                generation: current.generation,
                translatedText: "Synthetic translated result for \(item.detected).",
                detectedSourceLanguage: item.detected
            )
            let next = accepted ? workbench.beginRetranslation() : nil
            observed.append((item.detected, next?.targetLanguage, workbench.sourceLanguage))
            workbench.cancelRetranslation()
        }

        TranslationWorkbenchContractTestSupport.expect(
            zip(observed, expectations).allSatisfy { actual, expected in
                actual.detected == expected.detected
                    && actual.nextTarget == expected.nextTarget
                    && actual.sourceLanguage == expected.detected
            }
                && workbench.targetMode == .automatic
                && workbench.fixedTargetLanguage == "fr",
            "TestTranslationWorkbenchTargetMode.test_automaticMode_usesDetectedLanguageForTheNextTargetAndKeepsSourceLanguageCurrent"
        )
    }

    static func test_fixedMode_neverChangesTargetAfterDetectionButStillUpdatesSourceLanguage() {
        var workbench = TranslationWorkbenchState(
            historyID: "fixed-target-history-id",
            sourceText: "Synthetic source.",
            translatedText: "虚构译文。",
            sourceLanguage: "en",
            targetLanguage: "de",
            targetMode: .fixed,
            fixedTargetLanguage: "de",
            formattingMode: .smart
        )
        let detectedLanguages = ["ja", "zh", "en"]
        var observed: [(nextTarget: String?, sourceLanguage: String)] = []

        for detected in detectedLanguages {
            guard let current = workbench.beginRetranslation() else {
                observed.append((nil, workbench.sourceLanguage))
                continue
            }
            let accepted = workbench.completeRetranslation(
                generation: current.generation,
                translatedText: "Synthetic fixed-target result.",
                detectedSourceLanguage: detected
            )
            let next = accepted ? workbench.beginRetranslation() : nil
            observed.append((next?.targetLanguage, workbench.sourceLanguage))
            workbench.cancelRetranslation()
        }

        TranslationWorkbenchContractTestSupport.expect(
            zip(observed, detectedLanguages).allSatisfy { actual, detected in
                actual.nextTarget == "de" && actual.sourceLanguage == detected
            }
                && workbench.targetMode == .fixed
                && workbench.fixedTargetLanguage == "de",
            "TestTranslationWorkbenchTargetMode.test_fixedMode_neverChangesTargetAfterDetectionButStillUpdatesSourceLanguage"
        )
    }
}

final class TestTranslationWorkbenchSpeech {
    static func test_sourceAndTranslationSpeech_areMutuallyExclusiveAndCurrentButtonStops() {
        var workbench = TranslationWorkbenchContractTestSupport.makeWorkbench()
        workbench.editSource("Currently edited source for speech.")
        workbench.editTranslation("当前编辑后的译文朗读内容。")

        let sourceAction = workbench.toggleSpeech(for: .source)
        let translationAction = workbench.toggleSpeech(for: .translation)
        let stopTranslationAction = workbench.toggleSpeech(for: .translation)

        let sourceStartedCorrectly: Bool
        if case .start(let request) = sourceAction {
            sourceStartedCorrectly = request.field == .source
                && request.text == "Currently edited source for speech."
                && request.languageCode == "en"
        } else {
            sourceStartedCorrectly = false
        }

        let translationReplacedSource: Bool
        if case .stopAndStart(let stoppedField, let request) = translationAction {
            translationReplacedSource = stoppedField == .source
                && request.field == .translation
                && request.text == "当前编辑后的译文朗读内容。"
                && request.languageCode == "zh-Hans"
        } else {
            translationReplacedSource = false
        }

        TranslationWorkbenchContractTestSupport.expect(
            sourceStartedCorrectly
                && translationReplacedSource
                && stopTranslationAction == .stop(.translation)
                && workbench.speakingField == nil,
            "TestTranslationWorkbenchSpeech.test_sourceAndTranslationSpeech_areMutuallyExclusiveAndCurrentButtonStops"
        )
    }
}

final class TestTranslationWorkbenchHistory {
    static func test_successfulRetranslation_updatesSameHistoryIDWithCurrentFormattedEditors() {
        var store = RecentResultStore()
        _ = store.upsert(
            RecentResultEntry(
                id: "translation-history-stable-id",
                kind: .translation,
                completedAt: Date(timeIntervalSince1970: 1),
                menuSummary: "old summary",
                snapshot: .translation(
                    sourceText: "Initial source text.",
                    resultText: "初始译文。"
                )
            )
        )
        var workbench = TranslationWorkbenchContractTestSupport.makeWorkbench()
        workbench.editSource("Edited source for successful retranslation.")
        guard let request = workbench.beginRetranslation() else {
            TranslationWorkbenchContractTestSupport.expect(
                false,
                "TestTranslationWorkbenchHistory.test_successfulRetranslation_updatesSameHistoryIDWithCurrentFormattedEditors"
            )
            return
        }
        _ = workbench.completeRetranslation(
            generation: request.generation,
            translatedText: "成功重译后的最终内容。",
            detectedSourceLanguage: "en"
        )

        let mutation = store.upsert(
            workbench.makeHistoryEntry(
                completedAt: Date(timeIntervalSince1970: 2),
                menuSummary: "updated summary"
            )
        )
        let snapshot = store.entry(id: "translation-history-stable-id")?.snapshot
        let hasCurrentEditors: Bool
        if case .translation(let source, let result)? = snapshot {
            hasCurrentEditors = source == "Edited source for successful retranslation."
                && result == "成功重译后的最终内容。"
        } else {
            hasCurrentEditors = false
        }

        TranslationWorkbenchContractTestSupport.expect(
            mutation == .updated
                && store.entries.count == 1
                && store.entries.first?.id == "translation-history-stable-id"
                && hasCurrentEditors,
            "TestTranslationWorkbenchHistory.test_successfulRetranslation_updatesSameHistoryIDWithCurrentFormattedEditors"
        )
    }
}

@main
enum TranslationWorkbenchContractTests {
    static func main() {
        TestTranslationWorkbenchEditing.test_twoEditors_areIndependentlyEditableAndRetranslationReadsCurrentSource()
        TestTranslationWorkbenchGeneration.test_cancelledOlderRequest_cannotOverwriteNewerEditedSourceOrTranslation()
        TestTranslationWorkbenchTargetMode.test_automaticMode_usesDetectedLanguageForTheNextTargetAndKeepsSourceLanguageCurrent()
        TestTranslationWorkbenchTargetMode.test_fixedMode_neverChangesTargetAfterDetectionButStillUpdatesSourceLanguage()
        TestTranslationWorkbenchSpeech.test_sourceAndTranslationSpeech_areMutuallyExclusiveAndCurrentButtonStops()
        TestTranslationWorkbenchHistory.test_successfulRetranslation_updatesSameHistoryIDWithCurrentFormattedEditors()

        print(
            TranslationWorkbenchContractTestSupport.failures == 0
                ? "ALL PASS"
                : "\(TranslationWorkbenchContractTestSupport.failures) FAILURES"
        )
        exit(TranslationWorkbenchContractTestSupport.failures == 0 ? 0 : 1)
    }
}
