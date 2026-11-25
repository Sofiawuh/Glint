import Foundation

// 翻译工作台目标语言恢复、单侧手动 AI 与底部一键双侧 AI 请求代际黑盒契约测试。
// 不创建 UI、不读取配置、不访问网络、剪贴板、Speech 或最近结果存储。
//
// 预期最小运行命令：
//   swiftc -parse-as-library -o /tmp/glint_translation_workbench_orchestration_contract_test \
//     TranslationFormatting.swift RecentResults.swift TranslationWorkbench.swift \
//     translation_workbench_orchestration_contract_tests.swift -framework Foundation \
//     && /tmp/glint_translation_workbench_orchestration_contract_test

enum TranslationWorkbenchOrchestrationContractTestSupport {
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

final class TestTranslationWorkbenchAutomaticTargetRestoration {
    static func test_fixedSelection_canSwitchBackToAutomaticAndUsesCurrentDetectedLanguage() {
        var workbench = TranslationWorkbenchState(
            historyID: "fictional-automatic-restore-history",
            sourceText: "虚构中文原文。",
            translatedText: "Synthetic English translation.",
            sourceLanguage: "zh-Hans",
            targetLanguage: "fr",
            targetMode: .fixed,
            fixedTargetLanguage: "fr",
            formattingMode: .smart
        )

        workbench.setTargetLanguage("auto")
        let firstAutomaticRequest = workbench.beginRetranslation()
        let firstAccepted = firstAutomaticRequest.map {
            workbench.completeRetranslation(
                generation: $0.generation,
                translatedText: "Synthetic English result.",
                detectedSourceLanguage: "en"
            )
        } ?? false
        let secondAutomaticRequest = workbench.beginRetranslation()

        TranslationWorkbenchOrchestrationContractTestSupport.expect(
            firstAutomaticRequest?.targetLanguage == "en"
                && firstAccepted
                && secondAutomaticRequest?.targetLanguage == "zh-Hans"
                && workbench.targetMode == .automatic
                && workbench.fixedTargetLanguage == "fr"
                && workbench.sourceLanguage == "en",
            "TestTranslationWorkbenchAutomaticTargetRestoration.test_fixedSelection_canSwitchBackToAutomaticAndUsesCurrentDetectedLanguage"
        )
    }

    static func test_editingSourceToAnotherLanguage_recomputesAutomaticTargetBeforeRetranslation() {
        var chineseWorkbench = TranslationWorkbenchState(
            historyID: "fictional-auto-target-from-chinese",
            sourceText: "这是最初的中文原文。",
            translatedText: "Initial English translation.",
            sourceLanguage: "zh-Hans",
            targetLanguage: "en",
            targetMode: .automatic,
            fixedTargetLanguage: "fr",
            formattingMode: .smart
        )
        chineseWorkbench.editSource("This replacement source is now English.")
        let englishRequest = chineseWorkbench.beginRetranslation()

        var englishWorkbench = TranslationWorkbenchState(
            historyID: "fictional-auto-target-from-english",
            sourceText: "This is the initial English source.",
            translatedText: "这是初始中文译文。",
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            targetMode: .automatic,
            fixedTargetLanguage: "de",
            formattingMode: .smart
        )
        englishWorkbench.editSource("这份替换后的原文已经是中文。")
        let chineseRequest = englishWorkbench.beginRetranslation()

        TranslationWorkbenchOrchestrationContractTestSupport.expect(
            englishRequest?.targetLanguage == "zh-Hans"
                && chineseRequest?.targetLanguage == "en",
            "TestTranslationWorkbenchAutomaticTargetRestoration.test_editingSourceToAnotherLanguage_recomputesAutomaticTargetBeforeRetranslation"
        )
    }
}

final class TestTranslationWorkbenchManualAIGeneration {
    static func test_sourceEdit_rejectsLateSourceAIResponseWithoutChangingEitherEditor() {
        var workbench = TranslationWorkbenchState(
            historyID: "fictional-source-ai-history",
            sourceText: "Original source CASE-2141.",
            translatedText: "原始译文 CASE-2141。",
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            formattingMode: .smart
        )
        guard let request = workbench.beginAIProcessing(field: .source, mode: .smart) else {
            TranslationWorkbenchOrchestrationContractTestSupport.expect(
                false,
                "TestTranslationWorkbenchManualAIGeneration.test_sourceEdit_rejectsLateSourceAIResponseWithoutChangingEitherEditor"
            )
            return
        }

        workbench.editSource("User edited source CASE-2141 while AI was pending.")
        let acceptedLateResponse = workbench.completeAIProcessing(
            generation: request.generation,
            field: .source,
            text: "Late AI source CASE-2141."
        )

        TranslationWorkbenchOrchestrationContractTestSupport.expect(
            request.field == .source
                && request.text == "Original source CASE-2141."
                && request.mode == .smart
                && !acceptedLateResponse
                && workbench.sourceText == "User edited source CASE-2141 while AI was pending."
                && workbench.translatedText == "原始译文 CASE-2141。"
                && workbench.aiFieldInFlight == nil,
            "TestTranslationWorkbenchManualAIGeneration.test_sourceEdit_rejectsLateSourceAIResponseWithoutChangingEitherEditor"
        )
    }

    static func test_translationAICompletion_onlyChangesRequestedTranslationEditor() {
        var workbench = TranslationWorkbenchState(
            historyID: "fictional-translation-ai-history",
            sourceText: "Source remains unchanged CASE-2141.",
            translatedText: "待润色译文 CASE-2141。",
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            formattingMode: .polish
        )
        guard let request = workbench.beginAIProcessing(field: .translation, mode: .polish) else {
            TranslationWorkbenchOrchestrationContractTestSupport.expect(
                false,
                "TestTranslationWorkbenchManualAIGeneration.test_translationAICompletion_onlyChangesRequestedTranslationEditor"
            )
            return
        }

        let accepted = workbench.completeAIProcessing(
            generation: request.generation,
            field: .translation,
            text: "润色后的译文仍保留 CASE-2141。"
        )

        TranslationWorkbenchOrchestrationContractTestSupport.expect(
            accepted
                && request.field == .translation
                && request.text == "待润色译文 CASE-2141。"
                && request.mode == .polish
                && workbench.sourceText == "Source remains unchanged CASE-2141."
                && workbench.translatedText == "润色后的译文仍保留 CASE-2141。"
                && workbench.aiFieldInFlight == nil,
            "TestTranslationWorkbenchManualAIGeneration.test_translationAICompletion_onlyChangesRequestedTranslationEditor"
        )
    }

    static func test_retranslationStartedDuringManualAI_clearsAIStateAndRejectsLateCompletion() {
        var workbench = TranslationWorkbenchState(
            historyID: "fictional-ai-retranslation-race",
            sourceText: "Source CASE-2141.",
            translatedText: "译文 CASE-2141。",
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            targetMode: .automatic,
            formattingMode: .polish
        )
        guard let aiRequest = workbench.beginAIProcessing(field: .translation, mode: .polish),
              let retranslationRequest = workbench.beginRetranslation() else {
            TranslationWorkbenchOrchestrationContractTestSupport.expect(
                false,
                "TestTranslationWorkbenchManualAIGeneration.test_retranslationStartedDuringManualAI_clearsAIStateAndRejectsLateCompletion"
            )
            return
        }
        let acceptedLateAI = workbench.completeAIProcessing(
            generation: aiRequest.generation,
            field: .translation,
            text: "不应采用的晚到 AI 译文 CASE-2141。"
        )

        TranslationWorkbenchOrchestrationContractTestSupport.expect(
            retranslationRequest.sourceText == "Source CASE-2141."
                && workbench.aiFieldInFlight == nil
                && !acceptedLateAI
                && workbench.translatedText == "译文 CASE-2141。",
            "TestTranslationWorkbenchManualAIGeneration.test_retranslationStartedDuringManualAI_clearsAIStateAndRejectsLateCompletion"
        )
    }

    static func test_independentSideProcessing_sourceSuccessSurvivesTranslationFailure() {
        var workbench = TranslationWorkbenchState(
            historyID: "fictional-independent-side-history",
            sourceText: "Original fictional source.",
            translatedText: "原始虚构译文。",
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            formattingMode: .smart
        )
        guard let sourceRequest = workbench.beginAIProcessing(field: .source, mode: .smart) else {
            TranslationWorkbenchOrchestrationContractTestSupport.expect(
                false,
                "TestTranslationWorkbenchManualAIGeneration.test_independentSideProcessing_sourceSuccessSurvivesTranslationFailure"
            )
            return
        }
        let sourceAccepted = workbench.completeAIProcessing(
            generation: sourceRequest.generation,
            field: .source,
            text: "Formatted fictional source."
        )
        guard let translationRequest = workbench.beginAIProcessing(field: .translation, mode: .smart) else {
            TranslationWorkbenchOrchestrationContractTestSupport.expect(
                false,
                "TestTranslationWorkbenchManualAIGeneration.test_independentSideProcessing_sourceSuccessSurvivesTranslationFailure"
            )
            return
        }
        let failureAccepted = workbench.failAIProcessing(generation: translationRequest.generation)

        TranslationWorkbenchOrchestrationContractTestSupport.expect(
            sourceAccepted
                && failureAccepted
                && workbench.sourceText == "Formatted fictional source."
                && workbench.translatedText == "原始虚构译文。"
                && workbench.aiFieldInFlight == nil,
            "TestTranslationWorkbenchManualAIGeneration.test_independentSideProcessing_sourceSuccessSurvivesTranslationFailure"
        )
    }
}

final class TestTranslationWorkbenchPairAIGeneration {
    private static func makeWorkbench(
        id: String,
        mode: TranslationFormattingMode = .smart
    ) -> TranslationWorkbenchState {
        TranslationWorkbenchState(
            historyID: id,
            sourceText: "Current source CASE-2141.",
            translatedText: "当前译文 CASE-2141。",
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            targetMode: .automatic,
            formattingMode: mode
        )
    }

    static func test_smartAndPolish_captureCurrentSourceAndTranslationInOnePairRequest() {
        var smartWorkbench = makeWorkbench(id: "fictional-pair-smart", mode: .smart)
        smartWorkbench.editSource("Edited smart source CASE-2141.")
        let smartRetranslation = smartWorkbench.beginRetranslation()!
        _ = smartWorkbench.completeRetranslation(
            generation: smartRetranslation.generation,
            translatedText: "编辑后的智能排版译文 CASE-2141。",
            detectedSourceLanguage: "en"
        )
        smartWorkbench.editTranslation("编辑后的智能排版译文 CASE-2141。")
        let smartRequest = smartWorkbench.beginPairAIProcessing(mode: .smart)

        var polishWorkbench = makeWorkbench(id: "fictional-pair-polish", mode: .polish)
        polishWorkbench.editSource("Edited polish source CASE-2141.")
        let polishRetranslation = polishWorkbench.beginRetranslation()!
        _ = polishWorkbench.completeRetranslation(
            generation: polishRetranslation.generation,
            translatedText: "编辑后的智能润色译文 CASE-2141。",
            detectedSourceLanguage: "en"
        )
        polishWorkbench.editTranslation("编辑后的智能润色译文 CASE-2141。")
        let polishRequest = polishWorkbench.beginPairAIProcessing(mode: .polish)

        var strictWorkbench = makeWorkbench(id: "fictional-pair-strict", mode: .strict)
        let strictRequest = strictWorkbench.beginPairAIProcessing(mode: .strict)

        TranslationWorkbenchOrchestrationContractTestSupport.expect(
            smartRequest?.sourceText == "Edited smart source CASE-2141."
                && smartRequest?.translatedText == "编辑后的智能排版译文 CASE-2141。"
                && smartRequest?.mode == .smart
                && polishRequest?.sourceText == "Edited polish source CASE-2141."
                && polishRequest?.translatedText == "编辑后的智能润色译文 CASE-2141。"
                && polishRequest?.mode == .polish
                && strictRequest == nil,
            "TestTranslationWorkbenchPairAIGeneration.test_smartAndPolish_captureCurrentSourceAndTranslationInOnePairRequest"
        )
    }

    static func test_pairAICompletion_updatesBothEditorsAtomicallyAndClearsProcessingState() {
        var workbench = makeWorkbench(id: "fictional-pair-completion")
        guard let request = workbench.beginPairAIProcessing(mode: .smart) else {
            TranslationWorkbenchOrchestrationContractTestSupport.expect(
                false,
                "TestTranslationWorkbenchPairAIGeneration.test_pairAICompletion_updatesBothEditorsAtomicallyAndClearsProcessingState"
            )
            return
        }

        let accepted = workbench.completePairAIProcessing(
            generation: request.generation,
            sourceText: "Structured source CASE-2141.",
            translatedText: "结构化译文 CASE-2141。"
        )

        TranslationWorkbenchOrchestrationContractTestSupport.expect(
            accepted
                && workbench.sourceText == "Structured source CASE-2141."
                && workbench.translatedText == "结构化译文 CASE-2141。"
                && !workbench.isPairAIProcessing,
            "TestTranslationWorkbenchPairAIGeneration.test_pairAICompletion_updatesBothEditorsAtomicallyAndClearsProcessingState"
        )
    }

    static func test_editingEitherEditor_rejectsLatePairAIResponseAndClearsProcessingState() {
        var sourceEdited = makeWorkbench(id: "fictional-pair-source-edit")
        guard let sourceRequest = sourceEdited.beginPairAIProcessing(mode: .smart) else {
            TranslationWorkbenchOrchestrationContractTestSupport.expect(
                false,
                "TestTranslationWorkbenchPairAIGeneration.test_editingEitherEditor_rejectsLatePairAIResponseAndClearsProcessingState"
            )
            return
        }
        sourceEdited.editSource("User source edit CASE-2141.")
        let acceptedAfterSourceEdit = sourceEdited.completePairAIProcessing(
            generation: sourceRequest.generation,
            sourceText: "Late source result CASE-2141.",
            translatedText: "晚到译文 CASE-2141。"
        )

        var translationEdited = makeWorkbench(id: "fictional-pair-translation-edit")
        guard let translationRequest = translationEdited.beginPairAIProcessing(mode: .polish) else {
            TranslationWorkbenchOrchestrationContractTestSupport.expect(
                false,
                "TestTranslationWorkbenchPairAIGeneration.test_editingEitherEditor_rejectsLatePairAIResponseAndClearsProcessingState"
            )
            return
        }
        translationEdited.editTranslation("用户编辑后的译文 CASE-2141。")
        let acceptedAfterTranslationEdit = translationEdited.completePairAIProcessing(
            generation: translationRequest.generation,
            sourceText: "Late polished source CASE-2141.",
            translatedText: "晚到润色译文 CASE-2141。"
        )

        TranslationWorkbenchOrchestrationContractTestSupport.expect(
            !acceptedAfterSourceEdit
                && sourceEdited.sourceText == "User source edit CASE-2141."
                && sourceEdited.translatedText == "当前译文 CASE-2141。"
                && !sourceEdited.isPairAIProcessing
                && !acceptedAfterTranslationEdit
                && translationEdited.sourceText == "Current source CASE-2141."
                && translationEdited.translatedText == "用户编辑后的译文 CASE-2141。"
                && !translationEdited.isPairAIProcessing,
            "TestTranslationWorkbenchPairAIGeneration.test_editingEitherEditor_rejectsLatePairAIResponseAndClearsProcessingState"
        )
    }

    static func test_retranslationStartedDuringPairAI_rejectsLatePairResultAndClearsProcessingState() {
        var workbench = makeWorkbench(id: "fictional-pair-retranslation-race", mode: .polish)
        guard let pairRequest = workbench.beginPairAIProcessing(mode: .polish),
              let retranslationRequest = workbench.beginRetranslation() else {
            TranslationWorkbenchOrchestrationContractTestSupport.expect(
                false,
                "TestTranslationWorkbenchPairAIGeneration.test_retranslationStartedDuringPairAI_rejectsLatePairResultAndClearsProcessingState"
            )
            return
        }

        let acceptedLatePair = workbench.completePairAIProcessing(
            generation: pairRequest.generation,
            sourceText: "Late pair source CASE-2141.",
            translatedText: "晚到双侧译文 CASE-2141。"
        )

        TranslationWorkbenchOrchestrationContractTestSupport.expect(
            retranslationRequest.sourceText == "Current source CASE-2141."
                && !acceptedLatePair
                && workbench.sourceText == "Current source CASE-2141."
                && workbench.translatedText == "当前译文 CASE-2141。"
                && !workbench.isPairAIProcessing,
            "TestTranslationWorkbenchPairAIGeneration.test_retranslationStartedDuringPairAI_rejectsLatePairResultAndClearsProcessingState"
        )
    }
}

@main
enum TranslationWorkbenchOrchestrationContractTests {
    static func main() {
        TestTranslationWorkbenchAutomaticTargetRestoration.test_fixedSelection_canSwitchBackToAutomaticAndUsesCurrentDetectedLanguage()
        TestTranslationWorkbenchAutomaticTargetRestoration.test_editingSourceToAnotherLanguage_recomputesAutomaticTargetBeforeRetranslation()
        TestTranslationWorkbenchManualAIGeneration.test_sourceEdit_rejectsLateSourceAIResponseWithoutChangingEitherEditor()
        TestTranslationWorkbenchManualAIGeneration.test_translationAICompletion_onlyChangesRequestedTranslationEditor()
        TestTranslationWorkbenchManualAIGeneration.test_retranslationStartedDuringManualAI_clearsAIStateAndRejectsLateCompletion()
        TestTranslationWorkbenchManualAIGeneration.test_independentSideProcessing_sourceSuccessSurvivesTranslationFailure()
        TestTranslationWorkbenchPairAIGeneration.test_smartAndPolish_captureCurrentSourceAndTranslationInOnePairRequest()
        TestTranslationWorkbenchPairAIGeneration.test_pairAICompletion_updatesBothEditorsAtomicallyAndClearsProcessingState()
        TestTranslationWorkbenchPairAIGeneration.test_editingEitherEditor_rejectsLatePairAIResponseAndClearsProcessingState()
        TestTranslationWorkbenchPairAIGeneration.test_retranslationStartedDuringPairAI_rejectsLatePairResultAndClearsProcessingState()

        print(
            TranslationWorkbenchOrchestrationContractTestSupport.failures == 0
                ? "ALL PASS"
                : "\(TranslationWorkbenchOrchestrationContractTestSupport.failures) FAILURES"
        )
        exit(TranslationWorkbenchOrchestrationContractTestSupport.failures == 0 ? 0 : 1)
    }
}
