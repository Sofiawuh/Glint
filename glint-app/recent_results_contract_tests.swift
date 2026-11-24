import Foundation

// 最近结果纯内存领域层黑盒契约测试（不进入 App 打包）。
// 不读取 ~/.config/glint/config.json，不访问真实 Azure、剪贴板、选中文字或凭据。
//
// 预期最小运行命令（生产契约存在后）：
//   swiftc -o /tmp/glint_recent_results_contract_test \
//     RecentResults.swift recent_results_contract_tests.swift -framework Foundation \
//     && /tmp/glint_recent_results_contract_test

enum RecentResultsContractTestSupport {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() {
            print("  ok  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
        }
    }

    static func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    static func translation(
        id: String,
        completedAt: TimeInterval,
        menuSummary: String = "",
        sourceText: String,
        resultText: String
    ) -> RecentResultEntry {
        RecentResultEntry(
            id: id,
            kind: .translation,
            completedAt: date(completedAt),
            menuSummary: menuSummary,
            snapshot: .translation(sourceText: sourceText, resultText: resultText)
        )
    }

    static func question(
        id: String,
        completedAt: TimeInterval,
        menuSummary: String = "",
        selectedText: String = "selected-fixture",
        turns: [RecentResultTurn]
    ) -> RecentResultEntry {
        RecentResultEntry(
            id: id,
            kind: .question,
            completedAt: date(completedAt),
            menuSummary: menuSummary,
            snapshot: .question(selectedText: selectedText, transcript: turns)
        )
    }
}

final class TestRecentResultStoreLimits {
    static func test_moreThanTenEntries_evictsOldestAndKeepsNewestFirst() {
        var store = RecentResultStore(maxEntries: 10, maxTextBytes: 10 * 1_024 * 1_024)

        for index in 0..<12 {
            _ = store.upsert(
                RecentResultsContractTestSupport.translation(
                    id: "translation-\(index)",
                    completedAt: TimeInterval(index),
                    sourceText: "s",
                    resultText: "r"
                )
            )
        }

        RecentResultsContractTestSupport.expect(
            store.entries.map(\.id) == (2..<12).reversed().map { "translation-\($0)" },
            "TestRecentResultStoreLimits.test_moreThanTenEntries_evictsOldestAndKeepsNewestFirst"
        )
    }

    static func test_totalTextOverBudget_evictsOldestUntilWithinBudget() {
        // 每条快照恰好 12 UTF-8 bytes；36 bytes 超过 24 bytes 后只能保留最新两条。
        var store = RecentResultStore(maxEntries: 10, maxTextBytes: 24)
        let first = RecentResultsContractTestSupport.translation(
            id: "first",
            completedAt: 1,
            sourceText: "1234",
            resultText: "abcdefgh"
        )
        let second = RecentResultsContractTestSupport.translation(
            id: "second",
            completedAt: 2,
            sourceText: "5678",
            resultText: "ijklmnop"
        )
        let third = RecentResultsContractTestSupport.translation(
            id: "third",
            completedAt: 3,
            sourceText: "90ab",
            resultText: "qrstuvwx"
        )

        _ = store.upsert(first)
        _ = store.upsert(second)
        _ = store.upsert(third)

        RecentResultsContractTestSupport.expect(
            store.entries.map(\.id) == ["third", "second"]
                && store.entry(id: "first") == nil,
            "TestRecentResultStoreLimits.test_totalTextOverBudget_evictsOldestUntilWithinBudget"
        )
    }

    static func test_defaultTenMegabyteBudget_acceptsExactLimitAndRejectsOneByteOver() {
        var exactLimitStore = RecentResultStore()
        let exactLimitText = String(repeating: "x", count: 10 * 1_024 * 1_024)
        let accepted = exactLimitStore.upsert(
            RecentResultsContractTestSupport.translation(
                id: "exact-ten-megabytes",
                completedAt: 1,
                sourceText: "",
                resultText: exactLimitText
            )
        )

        var oversizedStore = RecentResultStore()
        let oversizedText = String(repeating: "y", count: 10 * 1_024 * 1_024 + 1)
        let rejected = oversizedStore.upsert(
            RecentResultsContractTestSupport.translation(
                id: "over-ten-megabytes",
                completedAt: 2,
                sourceText: "",
                resultText: oversizedText
            )
        )

        RecentResultsContractTestSupport.expect(
            accepted == .inserted
                && exactLimitStore.entries.map(\.id) == ["exact-ten-megabytes"]
                && rejected == .rejectedOversized
                && oversizedStore.entries.isEmpty,
            "TestRecentResultStoreLimits.test_defaultTenMegabyteBudget_acceptsExactLimitAndRejectsOneByteOver"
        )
    }

    static func test_singleEntryOverBudget_isRejectedWithoutEvictingExistingHistory() {
        var store = RecentResultStore(maxEntries: 10, maxTextBytes: 24)
        _ = store.upsert(
            RecentResultsContractTestSupport.translation(
                id: "kept",
                completedAt: 1,
                sourceText: "1234",
                resultText: "abcdefgh"
            )
        )

        let mutation = store.upsert(
            RecentResultsContractTestSupport.translation(
                id: "oversized",
                completedAt: 2,
                sourceText: "123456789012",
                resultText: "abcdefghijklm"
            )
        )

        RecentResultsContractTestSupport.expect(
            mutation == .rejectedOversized
                && store.entries.map(\.id) == ["kept"],
            "TestRecentResultStoreLimits.test_singleEntryOverBudget_isRejectedWithoutEvictingExistingHistory"
        )
    }
}

final class TestRecentResultStoreUpdateAndClear {
    static func test_sameQuestionID_updatesOneEntryAndMovesItToNewestPosition() {
        var store = RecentResultStore(maxEntries: 10, maxTextBytes: 10 * 1_024 * 1_024)
        _ = store.upsert(
            RecentResultsContractTestSupport.question(
                id: "question-session",
                completedAt: 1,
                turns: [
                    RecentResultTurn(role: .user, content: "first-question"),
                    RecentResultTurn(role: .assistant, content: "first-answer")
                ]
            )
        )
        _ = store.upsert(
            RecentResultsContractTestSupport.translation(
                id: "translation",
                completedAt: 2,
                sourceText: "source",
                resultText: "result"
            )
        )

        let update = store.upsert(
            RecentResultsContractTestSupport.question(
                id: "question-session",
                completedAt: 3,
                turns: [
                    RecentResultTurn(role: .user, content: "first-question"),
                    RecentResultTurn(role: .assistant, content: "first-answer"),
                    RecentResultTurn(role: .user, content: "follow-up"),
                    RecentResultTurn(role: .assistant, content: "follow-up-answer")
                ]
            )
        )

        let updatedTranscriptCount: Int
        if case .question(_, let transcript)? = store.entry(id: "question-session")?.snapshot {
            updatedTranscriptCount = transcript.count
        } else {
            updatedTranscriptCount = -1
        }

        RecentResultsContractTestSupport.expect(
            update == .updated
                && store.entries.map(\.id) == ["question-session", "translation"]
                && updatedTranscriptCount == 4,
            "TestRecentResultStoreUpdateAndClear.test_sameQuestionID_updatesOneEntryAndMovesItToNewestPosition"
        )
    }

    static func test_clear_removesEveryEntryAndReleasesAllLookupRoutes() {
        var store = RecentResultStore(maxEntries: 10, maxTextBytes: 10 * 1_024 * 1_024)
        _ = store.upsert(
            RecentResultsContractTestSupport.translation(
                id: "one",
                completedAt: 1,
                sourceText: "source-one",
                resultText: "result-one"
            )
        )
        _ = store.upsert(
            RecentResultsContractTestSupport.translation(
                id: "two",
                completedAt: 2,
                sourceText: "source-two",
                resultText: "result-two"
            )
        )

        store.removeAll()

        RecentResultsContractTestSupport.expect(
            store.entries.isEmpty
                && store.entry(id: "one") == nil
                && store.entry(id: "two") == nil,
            "TestRecentResultStoreUpdateAndClear.test_clear_removesEveryEntryAndReleasesAllLookupRoutes"
        )
    }
}

final class TestRecentResultRecordingPolicy {
    static func test_successfulTranslationAndCompleteTextQuestion_createRecordableEntries() {
        let translation = RecentResultRecorder.makeEntry(
            from: .translationSucceeded(
                id: "translation-success",
                sourceText: "synthetic-source",
                resultText: "synthetic-result",
                menuSummary: "safe translation summary",
                completedAt: RecentResultsContractTestSupport.date(1)
            )
        )
        let question = RecentResultRecorder.makeEntry(
            from: .textQuestionCompleted(
                id: "question-success",
                selectedText: "synthetic-selection",
                transcript: [
                    RecentResultTurn(role: .user, content: "synthetic-question"),
                    RecentResultTurn(role: .assistant, content: "synthetic-answer")
                ],
                menuSummary: "safe question summary",
                completedAt: RecentResultsContractTestSupport.date(2)
            )
        )

        RecentResultsContractTestSupport.expect(
            translation?.kind == .translation
                && question?.kind == .question,
            "TestRecentResultRecordingPolicy.test_successfulTranslationAndCompleteTextQuestion_createRecordableEntries"
        )
    }

    static func test_loadingFailureCancellationDraftAndScreenshot_neverCreateHistory() {
        let rejected: [RecentResultCompletion] = [
            .translationLoading,
            .translationFailed,
            .textQuestionCancelled,
            .textQuestionFailed,
            .textQuestionDraft,
            .screenshotQuestionCompleted
        ]

        RecentResultsContractTestSupport.expect(
            rejected.allSatisfy { RecentResultRecorder.makeEntry(from: $0) == nil },
            "TestRecentResultRecordingPolicy.test_loadingFailureCancellationDraftAndScreenshot_neverCreateHistory"
        )
    }

    static func test_emptyFinalTranslationOrIncompleteQuestionTranscript_isNotRecordable() {
        let emptyTranslation = RecentResultRecorder.makeEntry(
            from: .translationSucceeded(
                id: "empty-translation",
                sourceText: "synthetic-source",
                resultText: "  \n ",
                menuSummary: "safe summary",
                completedAt: RecentResultsContractTestSupport.date(1)
            )
        )
        let userOnlyQuestion = RecentResultRecorder.makeEntry(
            from: .textQuestionCompleted(
                id: "incomplete-question",
                selectedText: "synthetic-selection",
                transcript: [RecentResultTurn(role: .user, content: "unanswered")],
                menuSummary: "safe summary",
                completedAt: RecentResultsContractTestSupport.date(2)
            )
        )
        let blankAssistantQuestion = RecentResultRecorder.makeEntry(
            from: .textQuestionCompleted(
                id: "blank-answer",
                selectedText: "synthetic-selection",
                transcript: [
                    RecentResultTurn(role: .user, content: "question"),
                    RecentResultTurn(role: .assistant, content: " \n ")
                ],
                menuSummary: "safe summary",
                completedAt: RecentResultsContractTestSupport.date(3)
            )
        )

        RecentResultsContractTestSupport.expect(
            emptyTranslation == nil
                && userOnlyQuestion == nil
                && blankAssistantQuestion == nil,
            "TestRecentResultRecordingPolicy.test_emptyFinalTranslationOrIncompleteQuestionTranscript_isNotRecordable"
        )
    }
}

final class TestRecentResultsMenuModel {
    static func test_entriesAreNewestFirstWithSingleLineTruncatedSafeSummary() {
        let entries = [
            RecentResultsContractTestSupport.translation(
                id: "older",
                completedAt: 28_800,
                menuSummary: "alpha\n beta gamma private-body",
                sourceText: "source-body-that-must-not-appear",
                resultText: "translation-body-that-must-not-appear"
            ),
            RecentResultsContractTestSupport.question(
                id: "newer",
                completedAt: 28_860,
                menuSummary: "second safe",
                turns: [
                    RecentResultTurn(role: .user, content: "question-body-that-must-not-appear"),
                    RecentResultTurn(role: .assistant, content: "answer-body-that-must-not-appear")
                ]
            )
        ]
        let model = RecentResultsMenuModel(
            entries: entries,
            historySwitchingEnabled: true,
            summaryCharacterLimit: 10,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let historyItems = model.items.filter {
            if case .history = $0.role { return true }
            return false
        }

        RecentResultsContractTestSupport.expect(
            historyItems.map(\.id) == ["newer", "older"]
                && historyItems[0].title == "08:01  提问 · second saf…"
                && historyItems[1].title == "08:00  翻译 · alpha beta…"
                && historyItems.allSatisfy { !$0.title.contains("\n") },
            "TestRecentResultsMenuModel.test_entriesAreNewestFirstWithSingleLineTruncatedSafeSummary"
        )
    }

    static func test_emptyHistoryShowsDisabledEmptyStateAndDisabledClearAction() {
        let model = RecentResultsMenuModel(
            entries: [],
            historySwitchingEnabled: true,
            summaryCharacterLimit: 32,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let empty = model.items.first { $0.role == .emptyState }
        let clear = model.items.first { $0.role == .clear }

        RecentResultsContractTestSupport.expect(
            empty?.title == "暂无最近结果"
                && empty?.isEnabled == false
                && clear?.title == "清空最近结果"
                && clear?.isEnabled == false,
            "TestRecentResultsMenuModel.test_emptyHistoryShowsDisabledEmptyStateAndDisabledClearAction"
        )
    }

    static func test_inFlightRequestKeepsHistoryVisibleButDisablesEveryHistoryRoute() {
        let entry = RecentResultsContractTestSupport.translation(
            id: "visible-but-disabled",
            completedAt: 1,
            menuSummary: "safe summary",
            sourceText: "synthetic-source",
            resultText: "synthetic-result"
        )
        let model = RecentResultsMenuModel(
            entries: [entry],
            historySwitchingEnabled: false,
            summaryCharacterLimit: 32,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let item = model.items.first { $0.id == entry.id }

        RecentResultsContractTestSupport.expect(
            item != nil && item?.isEnabled == false,
            "TestRecentResultsMenuModel.test_inFlightRequestKeepsHistoryVisibleButDisablesEveryHistoryRoute"
        )
    }
}

final class TestRecentResultsPrivacyContract {
    static func test_menuUsesOnlySafeSummaryAndNeverIncludesSnapshotBodyOrCredentialFixtures() {
        let forbidden = [
            "selected-body-fixture",
            "question-body-fixture",
            "answer-body-fixture",
            "credential-fixture-value",
            "https://private-endpoint.invalid"
        ]
        let entry = RecentResultsContractTestSupport.question(
            id: "privacy-entry",
            completedAt: 1,
            menuSummary: "safe local label",
            selectedText: forbidden[0],
            turns: [
                RecentResultTurn(role: .user, content: forbidden[1]),
                RecentResultTurn(role: .assistant, content: forbidden[2])
            ]
        )
        let model = RecentResultsMenuModel(
            entries: [entry],
            historySwitchingEnabled: true,
            summaryCharacterLimit: 32,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let renderedMenu = model.items.map(\.title).joined(separator: "\n")

        RecentResultsContractTestSupport.expect(
            renderedMenu.contains("safe local label")
                && forbidden.allSatisfy { !renderedMenu.contains($0) },
            "TestRecentResultsPrivacyContract.test_menuUsesOnlySafeSummaryAndNeverIncludesSnapshotBodyOrCredentialFixtures"
        )
    }

    static func test_logMessagesContainOnlyMetadataAndNeverIncludeEntryContent() {
        let forbidden = [
            "selected-body-fixture",
            "question-body-fixture",
            "answer-body-fixture",
            "credential-fixture-value"
        ]
        let messages = [
            RecentResultsLogEvent.upserted(
                entryID: "privacy-entry",
                kind: .question,
                count: 1,
                mutation: .inserted
            ).message,
            RecentResultsLogEvent.routeMissing(entryID: "missing-entry", count: 0).message,
            RecentResultsLogEvent.cleared(previousCount: 1).message
        ].joined(separator: "\n")

        RecentResultsContractTestSupport.expect(
            messages.contains("privacy-entry")
                && messages.contains("question")
                && forbidden.allSatisfy { !messages.contains($0) },
            "TestRecentResultsPrivacyContract.test_logMessagesContainOnlyMetadataAndNeverIncludeEntryContent"
        )
    }
}

@main
enum RecentResultsContractTests {
    static func main() {
        TestRecentResultStoreLimits.test_moreThanTenEntries_evictsOldestAndKeepsNewestFirst()
        TestRecentResultStoreLimits.test_totalTextOverBudget_evictsOldestUntilWithinBudget()
        TestRecentResultStoreLimits.test_defaultTenMegabyteBudget_acceptsExactLimitAndRejectsOneByteOver()
        TestRecentResultStoreLimits.test_singleEntryOverBudget_isRejectedWithoutEvictingExistingHistory()
        TestRecentResultStoreUpdateAndClear.test_sameQuestionID_updatesOneEntryAndMovesItToNewestPosition()
        TestRecentResultStoreUpdateAndClear.test_clear_removesEveryEntryAndReleasesAllLookupRoutes()
        TestRecentResultRecordingPolicy.test_successfulTranslationAndCompleteTextQuestion_createRecordableEntries()
        TestRecentResultRecordingPolicy.test_loadingFailureCancellationDraftAndScreenshot_neverCreateHistory()
        TestRecentResultRecordingPolicy.test_emptyFinalTranslationOrIncompleteQuestionTranscript_isNotRecordable()
        TestRecentResultsMenuModel.test_entriesAreNewestFirstWithSingleLineTruncatedSafeSummary()
        TestRecentResultsMenuModel.test_emptyHistoryShowsDisabledEmptyStateAndDisabledClearAction()
        TestRecentResultsMenuModel.test_inFlightRequestKeepsHistoryVisibleButDisablesEveryHistoryRoute()
        TestRecentResultsPrivacyContract.test_menuUsesOnlySafeSummaryAndNeverIncludesSnapshotBodyOrCredentialFixtures()
        TestRecentResultsPrivacyContract.test_logMessagesContainOnlyMetadataAndNeverIncludeEntryContent()

        if RecentResultsContractTestSupport.failures > 0 {
            print("\n\(RecentResultsContractTestSupport.failures) recent-results contract test(s) failed")
            exit(1)
        }
        print("\nAll recent-results contract tests passed")
    }
}
