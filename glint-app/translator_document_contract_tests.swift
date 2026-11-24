import Foundation

// Translator 文档拆片、预算、结构保护、稳定重组与检测语言黑盒契约测试。
// 不发起网络请求，仅验证纯值文档协议。
//
// 预期最小运行命令（生产契约存在后）：
//   swiftc -o /tmp/glint_translator_document_contract_test \
//     TranslationDocument.swift TranslationFormatting.swift Config.swift \
//     ScreenshotHotKey.swift TextCommandHotKey.swift HotKey.swift \
//     translator_document_contract_tests.swift -framework Carbon -framework Foundation \
//     && /tmp/glint_translator_document_contract_test

enum TranslatorDocumentContractTestSupport {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() {
            print("  ok  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
        }
    }

    static let structuredInput = """
    # Release Notes

    1. First item
    2. Second item

    | Name | Count |
    | --- | --- |
    | Widget | 2 |

    > Quoted message

    ```swift
    let secret = "fictional-only"
    ```
    """

    static func occurrenceCount(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        return haystack.components(separatedBy: needle).count - 1
    }
}

final class TestTranslationDocumentSegmentation {
    static func test_structuredText_extractsOnlyTranslatableContentWithStableUniqueIDs() {
        let first = TranslationDocument(formattedText: TranslatorDocumentContractTestSupport.structuredInput)
        let second = TranslationDocument(formattedText: TranslatorDocumentContractTestSupport.structuredInput)
        let texts = first.fragments
            .filter { $0.protectedTokens.isEmpty }
            .map(\.text)
        let protectedOriginals = first.fragments.flatMap { fragment in
            fragment.protectedTokens.map(\.originalText)
        }
        let ids = first.fragments.map(\.id)

        TranslatorDocumentContractTestSupport.expect(
            texts == [
                "Release Notes",
                "First item",
                "Second item",
                "Name",
                "Count",
                "Widget",
                "Quoted message"
            ]
                && protectedOriginals == ["2"]
                && first.fragments.allSatisfy { fragment in
                    fragment.protectedTokens.allSatisfy { token in
                        !fragment.text.contains(token.originalText)
                            && TranslatorDocumentContractTestSupport.occurrenceCount(
                                of: token.placeholder,
                                in: fragment.text
                            ) == 1
                    }
                }
                && Set(ids).count == ids.count
                && ids == second.fragments.map(\.id)
                && !texts.joined(separator: " ").contains("1.")
                && !texts.joined(separator: " ").contains("|")
                && !texts.joined(separator: " ").contains("let secret"),
            "TestTranslationDocumentSegmentation.test_structuredText_extractsOnlyTranslatableContentWithStableUniqueIDs"
        )
    }

    static func test_itemAndCharacterBudgets_batchAtFragmentBoundariesWithoutTruncatingOversizedFragment() {
        let input = """
        Alpha

        BetaBeta

        This single fragment is deliberately longer than the fictional budget.

        Gamma
        """
        let document = TranslationDocument(formattedText: input)
        let batches = document.batches(limits: TranslationBatchLimits(maxItems: 2, maxCharacters: 12))
        let flattened = batches.flatMap { $0 }
        let oversized = flattened.first { $0.text.hasPrefix("This single fragment") }

        TranslatorDocumentContractTestSupport.expect(
            flattened.map(\.id) == document.fragments.map(\.id)
                && batches.allSatisfy { batch in
                    batch.count <= 2
                        && (batch.reduce(0) { $0 + $1.text.count } <= 12 || batch.count == 1)
                }
                && oversized?.text == "This single fragment is deliberately longer than the fictional budget.",
            "TestTranslationDocumentSegmentation.test_itemAndCharacterBudgets_batchAtFragmentBoundariesWithoutTruncatingOversizedFragment"
        )
    }

    static func test_unicodeListMarkers_areExcludedFromTranslatorPayloadAndRestoredByteForByte() {
        let input = """
        • Alpha item
        ◦ Beta item
        ▪ Gamma item
        ‣ Delta item
        – Epsilon item
        """
        let document = TranslationDocument(formattedText: input)
        let expectedBodies = [
            "Alpha item",
            "Beta item",
            "Gamma item",
            "Delta item",
            "Epsilon item"
        ]
        let translations = [
            "Alpha item": "甲项目",
            "Beta item": "乙项目",
            "Gamma item": "丙项目",
            "Delta item": "丁项目",
            "Epsilon item": "戊项目"
        ]
        let responses = document.fragments.map { fragment in
            TranslationFragmentResponse(
                id: fragment.id,
                translatedText: translations[fragment.text] ?? fragment.text,
                detectedLanguage: "en"
            )
        }
        let result = document.reassemble(responses)
        let expected = """
        • 甲项目
        ◦ 乙项目
        ▪ 丙项目
        ‣ 丁项目
        – 戊项目
        """

        TranslatorDocumentContractTestSupport.expect(
            document.fragments.map(\.text) == expectedBodies
                && document.fragments.allSatisfy { fragment in
                    !fragment.text.contains("•")
                        && !fragment.text.contains("◦")
                        && !fragment.text.contains("▪")
                        && !fragment.text.contains("‣")
                        && !fragment.text.contains("–")
                }
                && result?.text == expected,
            "TestTranslationDocumentSegmentation.test_unicodeListMarkers_areExcludedFromTranslatorPayloadAndRestoredByteForByte"
        )
    }

    static func test_singleFragmentOverAzureBudget_isLosslesslySplitIntoBuildableRequests() {
        let input = String(repeating: "A", count: 45_001)
        let document = TranslationDocument(formattedText: input)
        let batches = document.batches(limits: .azureDefault)
        let translator = AzureTranslatorConfig(
            endpoint: "https://translator.example.invalid",
            apiKey: "fictional-translator-key",
            region: "fictional-region"
        )
        let responses = document.fragments.map {
            TranslationFragmentResponse(
                id: $0.id,
                translatedText: $0.text,
                detectedLanguage: "en"
            )
        }

        TranslatorDocumentContractTestSupport.expect(
            document.fragments.count > 1
                && batches.count > 1
                && batches.allSatisfy {
                    !$0.isEmpty
                        && $0.reduce(0) { $0 + $1.text.count } <= TranslationBatchLimits.azureDefault.maxCharacters
                        && translator.buildRequest(fragments: $0, targetLanguage: "zh-Hans") != nil
                }
                && document.reassemble(responses)?.text == input,
            "TestTranslationDocumentSegmentation.test_singleFragmentOverAzureBudget_isLosslesslySplitIntoBuildableRequests"
        )
    }
}

final class TestTranslationDocumentReassembly {
    static func test_shuffledResponses_reassembleByStableIDAndPreserveEveryStructureMarker() {
        let document = TranslationDocument(formattedText: TranslatorDocumentContractTestSupport.structuredInput)
        let replacements = [
            "Release Notes": "发布说明",
            "First item": "第一项",
            "Second item": "第二项",
            "Name": "名称",
            "Count": "数量",
            "Widget": "组件",
            "Quoted message": "引用消息"
        ]
        let responses = document.fragments
            .map { fragment in
                TranslationFragmentResponse(
                    id: fragment.id,
                    translatedText: replacements[fragment.text] ?? fragment.text,
                    detectedLanguage: "en"
                )
            }
            .reversed()
        let result = document.reassemble(Array(responses))
        let expected = """
        # 发布说明

        1. 第一项
        2. 第二项

        | 名称 | 数量 |
        | --- | --- |
        | 组件 | 2 |

        > 引用消息

        ```swift
        let secret = "fictional-only"
        ```
        """

        TranslatorDocumentContractTestSupport.expect(
            result?.text == expected
                && result?.detectedLanguage == "en",
            "TestTranslationDocumentReassembly.test_shuffledResponses_reassembleByStableIDAndPreserveEveryStructureMarker"
        )
    }

    static func test_missingOrUnknownResponseID_refusesPartialOrCorruptReassembly() {
        let document = TranslationDocument(formattedText: "First block\n\nSecond block")
        guard let first = document.fragments.first else {
            TranslatorDocumentContractTestSupport.expect(
                false,
                "TestTranslationDocumentReassembly.test_missingOrUnknownResponseID_refusesPartialOrCorruptReassembly"
            )
            return
        }
        let incomplete = [
            TranslationFragmentResponse(
                id: first.id,
                translatedText: "第一块",
                detectedLanguage: "en"
            )
        ]
        let unknown = document.fragments.map {
            TranslationFragmentResponse(id: $0.id, translatedText: $0.text, detectedLanguage: "en")
        } + [
            TranslationFragmentResponse(
                id: "unknown-fragment-id",
                translatedText: "不应出现",
                detectedLanguage: "en"
            )
        ]

        TranslatorDocumentContractTestSupport.expect(
            document.reassemble(incomplete) == nil
                && document.reassemble(unknown) == nil,
            "TestTranslationDocumentReassembly.test_missingOrUnknownResponseID_refusesPartialOrCorruptReassembly"
        )
    }
}

final class TestTranslationDocumentTabularProtection {
    static let tabSeparatedInput = """
    Name\tContact\tDue\tAmount\tPath\tVariable\tCount
    Widget\ttester@example.invalid\t2026-12-31\tUSD 1,234.50\t/opt/glint/config.json\tGLINT_MODE\t42
    """

    static func validResponses(for document: TranslationDocument) -> [TranslationFragmentResponse] {
        let translations = [
            "Name": "名称",
            "Contact": "联系人",
            "Due": "到期日",
            "Amount": "金额",
            "Path": "路径",
            "Variable": "变量",
            "Count": "数量",
            "Widget": "组件"
        ]
        return document.fragments.map { fragment in
            TranslationFragmentResponse(
                id: fragment.id,
                translatedText: translations[fragment.text] ?? fragment.text,
                detectedLanguage: "en"
            )
        }
    }

    static func test_tabSeparatedCells_areIndependentFragmentsAndProtectedValuesNeverReachTranslatorRaw() {
        let document = TranslationDocument(formattedText: tabSeparatedInput)
        let translatableTexts = document.fragments
            .filter { $0.protectedTokens.isEmpty }
            .map(\.text)
        let protectedOriginals = document.fragments.flatMap { fragment in
            fragment.protectedTokens.map(\.originalText)
        }
        let expectedProtected = Set([
            "tester@example.invalid",
            "2026-12-31",
            "USD 1,234.50",
            "/opt/glint/config.json",
            "GLINT_MODE",
            "42"
        ])
        let everyProtectedValueIsMaskedOnce = document.fragments.allSatisfy { fragment in
            fragment.protectedTokens.allSatisfy { token in
                !token.placeholder.isEmpty
                    && !fragment.text.contains(token.originalText)
                    && TranslatorDocumentContractTestSupport.occurrenceCount(
                        of: token.placeholder,
                        in: fragment.text
                    ) == 1
            }
        }

        let urlDocument = TranslationDocument(
            formattedText: "Website\thttps://example.invalid/account?id=42"
        )
        let urlIsProtectedWithoutRawExposure = urlDocument.fragments.contains { fragment in
            fragment.protectedTokens.contains { token in
                token.originalText == "https://example.invalid/account?id=42"
                    && !fragment.text.contains(token.originalText)
                    && TranslatorDocumentContractTestSupport.occurrenceCount(
                        of: token.placeholder,
                        in: fragment.text
                    ) == 1
            }
        }

        TranslatorDocumentContractTestSupport.expect(
            document.fragments.count == 14
                && translatableTexts == [
                    "Name", "Contact", "Due", "Amount", "Path", "Variable", "Count", "Widget"
                ]
                && Set(protectedOriginals) == expectedProtected
                && protectedOriginals.count == expectedProtected.count
                && everyProtectedValueIsMaskedOnce
                && urlIsProtectedWithoutRawExposure,
            "TestTranslationDocumentTabularProtection.test_tabSeparatedCells_areIndependentFragmentsAndProtectedValuesNeverReachTranslatorRaw"
        )
    }

    static func test_validResponses_restoreTabsAndEveryProtectedTokenByteForByte() {
        let document = TranslationDocument(formattedText: tabSeparatedInput)
        let result = document.reassemble(validResponses(for: document))
        let expected = """
        名称\t联系人\t到期日\t金额\t路径\t变量\t数量
        组件\ttester@example.invalid\t2026-12-31\tUSD 1,234.50\t/opt/glint/config.json\tGLINT_MODE\t42
        """
        let rowColumnCounts = result?.text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.split(separator: "\t", omittingEmptySubsequences: false).count }

        TranslatorDocumentContractTestSupport.expect(
            result?.text == expected
                && rowColumnCounts == [7, 7]
                && result?.detectedLanguage == "en",
            "TestTranslationDocumentTabularProtection.test_validResponses_restoreTabsAndEveryProtectedTokenByteForByte"
        )
    }

    static func test_missingDuplicatedOrTamperedProtectedPlaceholder_refusesReassemblyForEveryToken() {
        var rejectsEveryMutation = true
        var exercisedTokenCount = 0

        let documents = [
            TranslationDocument(formattedText: tabSeparatedInput),
            TranslationDocument(formattedText: "Website\thttps://example.invalid/account?id=42")
        ]
        for document in documents {
            let valid = validResponses(for: document)
            for (fragmentIndex, fragment) in document.fragments.enumerated() {
                for token in fragment.protectedTokens {
                    exercisedTokenCount += 1

                    var missing = valid
                    let missingText = fragment.text.replacingOccurrences(of: token.placeholder, with: "")
                    missing[fragmentIndex] = TranslationFragmentResponse(
                        id: fragment.id,
                        translatedText: missingText,
                        detectedLanguage: "en"
                    )

                    var duplicated = valid
                    let duplicatedText = fragment.text.replacingOccurrences(
                        of: token.placeholder,
                        with: token.placeholder + token.placeholder
                    )
                    duplicated[fragmentIndex] = TranslationFragmentResponse(
                        id: fragment.id,
                        translatedText: duplicatedText,
                        detectedLanguage: "en"
                    )

                    let replacementSuffix = token.placeholder.last == "X" ? "Y" : "X"
                    let tamperedPlaceholder = String(token.placeholder.dropLast()) + replacementSuffix
                    var tampered = valid
                    let tamperedText = fragment.text.replacingOccurrences(
                        of: token.placeholder,
                        with: tamperedPlaceholder
                    )
                    tampered[fragmentIndex] = TranslationFragmentResponse(
                        id: fragment.id,
                        translatedText: tamperedText,
                        detectedLanguage: "en"
                    )

                    rejectsEveryMutation = rejectsEveryMutation
                        && document.reassemble(missing) == nil
                        && document.reassemble(duplicated) == nil
                        && document.reassemble(tampered) == nil
                }
            }
        }

        TranslatorDocumentContractTestSupport.expect(
            exercisedTokenCount == 7 && rejectsEveryMutation,
            "TestTranslationDocumentTabularProtection.test_missingDuplicatedOrTamperedProtectedPlaceholder_refusesReassemblyForEveryToken"
        )
    }
}

@main
enum TranslatorDocumentContractTests {
    static func main() {
        TestTranslationDocumentSegmentation.test_structuredText_extractsOnlyTranslatableContentWithStableUniqueIDs()
        TestTranslationDocumentSegmentation.test_itemAndCharacterBudgets_batchAtFragmentBoundariesWithoutTruncatingOversizedFragment()
        TestTranslationDocumentSegmentation.test_unicodeListMarkers_areExcludedFromTranslatorPayloadAndRestoredByteForByte()
        TestTranslationDocumentSegmentation.test_singleFragmentOverAzureBudget_isLosslesslySplitIntoBuildableRequests()
        TestTranslationDocumentReassembly.test_shuffledResponses_reassembleByStableIDAndPreserveEveryStructureMarker()
        TestTranslationDocumentReassembly.test_missingOrUnknownResponseID_refusesPartialOrCorruptReassembly()
        TestTranslationDocumentTabularProtection.test_tabSeparatedCells_areIndependentFragmentsAndProtectedValuesNeverReachTranslatorRaw()
        TestTranslationDocumentTabularProtection.test_validResponses_restoreTabsAndEveryProtectedTokenByteForByte()
        TestTranslationDocumentTabularProtection.test_missingDuplicatedOrTamperedProtectedPlaceholder_refusesReassemblyForEveryToken()

        print(
            TranslatorDocumentContractTestSupport.failures == 0
                ? "ALL PASS"
                : "\(TranslatorDocumentContractTestSupport.failures) FAILURES"
        )
        exit(TranslatorDocumentContractTestSupport.failures == 0 ? 0 : 1)
    }
}
