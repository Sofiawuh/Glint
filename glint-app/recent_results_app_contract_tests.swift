import Foundation

// 最近结果应用状态与只读展示黑盒契约测试（不进入 App 打包）。
// 通过纯值状态验证菜单 ID 路由、在途禁用、只读能力和当前窗口恢复，
// 不创建 NSPanel、输入框、网络任务，不读取真实配置或用户内容。
//
// 预期最小运行命令（生产契约存在后）：
//   swiftc -o /tmp/glint_recent_results_app_contract_test \
//     RecentResults.swift RecentResultsPresentation.swift \
//     recent_results_app_contract_tests.swift -framework Foundation \
//     && /tmp/glint_recent_results_app_contract_test

enum RecentResultsAppContractTestSupport {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() {
            print("  ok  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
        }
    }

    static let historyID = "history-route-fixture"

    static func historyEntry() -> RecentResultEntry {
        RecentResultEntry(
            id: historyID,
            kind: .question,
            completedAt: Date(timeIntervalSince1970: 100),
            menuSummary: "safe history summary",
            snapshot: .question(
                selectedText: "synthetic-selection",
                transcript: [
                    RecentResultTurn(role: .user, content: "synthetic-question"),
                    RecentResultTurn(role: .assistant, content: "synthetic-answer")
                ]
            )
        )
    }

    static func currentWindow() -> CurrentWindowSnapshot {
        CurrentWindowSnapshot(
            content: .questionComposer(selectedText: "synthetic-current-selection"),
            draft: "unsent-local-draft",
            frame: RecentResultWindowFrame(x: 120, y: 240, width: 500, height: 420),
            isPinned: true,
            visibility: .visible
        )
    }

    static func store() -> RecentResultStore {
        var store = RecentResultStore(maxEntries: 10, maxTextBytes: 10 * 1_024 * 1_024)
        _ = store.upsert(historyEntry())
        return store
    }
}

final class TestRecentResultIDRouting {
    static func test_existingID_opensExactlyOneReadOnlyWindowWithNoInputOrNetworkCapability() {
        let store = RecentResultsAppContractTestSupport.store()
        var browser = RecentResultsBrowserState(
            currentWindow: RecentResultsAppContractTestSupport.currentWindow()
        )

        let route = browser.openHistory(
            id: RecentResultsAppContractTestSupport.historyID,
            from: store,
            requestInFlight: false
        )
        let history = browser.visibleHistoryWindow

        RecentResultsAppContractTestSupport.expect(
            route == .opened(RecentResultsAppContractTestSupport.historyID)
                && browser.visibleWindowCount == 1
                && history?.entryID == RecentResultsAppContractTestSupport.historyID
                && history?.allowsCopy == true
                && history?.allowsPinning == true
                && history?.allowsClose == true
                && history?.allowsResize == true
                && history?.hasPromptInput == false
                && history?.hasSendButton == false
                && history?.canStartNetworkRequest == false,
            "TestRecentResultIDRouting.test_existingID_opensExactlyOneReadOnlyWindowWithNoInputOrNetworkCapability"
        )
    }

    static func test_missingOrEvictedID_refreshesSafelyWithoutOpeningWindow() {
        let store = RecentResultsAppContractTestSupport.store()
        var browser = RecentResultsBrowserState(
            currentWindow: RecentResultsAppContractTestSupport.currentWindow()
        )

        let route = browser.openHistory(
            id: "missing-route-fixture",
            from: store,
            requestInFlight: false
        )

        RecentResultsAppContractTestSupport.expect(
            route == .missingRefreshMenu
                && browser.visibleHistoryWindow == nil
                && browser.visibleWindowCount == 0,
            "TestRecentResultIDRouting.test_missingOrEvictedID_refreshesSafelyWithoutOpeningWindow"
        )
    }

    static func test_requestInFlight_blocksHistorySwitchWithoutCancellingOrHidingCurrentWindow() {
        let current = RecentResultsAppContractTestSupport.currentWindow()
        let store = RecentResultsAppContractTestSupport.store()
        var browser = RecentResultsBrowserState(currentWindow: current)

        let route = browser.openHistory(
            id: RecentResultsAppContractTestSupport.historyID,
            from: store,
            requestInFlight: true
        )

        RecentResultsAppContractTestSupport.expect(
            route == .blockedInFlight
                && browser.visibleHistoryWindow == nil
                && browser.currentWindow == current
                && browser.didRequestNetworkCancellation == false,
            "TestRecentResultIDRouting.test_requestInFlight_blocksHistorySwitchWithoutCancellingOrHidingCurrentWindow"
        )
    }
}

final class TestRecentResultCurrentWindowRestoration {
    static func test_browsingHistory_preservesCurrentContentDraftFramePinAndVisibilityForReturn() {
        let current = RecentResultsAppContractTestSupport.currentWindow()
        let store = RecentResultsAppContractTestSupport.store()
        var browser = RecentResultsBrowserState(currentWindow: current)

        _ = browser.openHistory(
            id: RecentResultsAppContractTestSupport.historyID,
            from: store,
            requestInFlight: false
        )
        let restored = browser.showCurrentWindow()

        RecentResultsAppContractTestSupport.expect(
            restored == current
                && browser.currentWindow == current
                && browser.visibleHistoryWindow == nil
                && browser.visibleWindowCount == 1
                && browser.didStartNetworkRequest == false
                && browser.didRequestNetworkCancellation == false,
            "TestRecentResultCurrentWindowRestoration.test_browsingHistory_preservesCurrentContentDraftFramePinAndVisibilityForReturn"
        )
    }

    static func test_showCurrentWindow_restoresAHiddenCurrentDraftWithoutOpeningHistory() {
        let hidden = CurrentWindowSnapshot(
            content: .questionComposer(selectedText: "synthetic-hidden-selection"),
            draft: "hidden-unsent-draft",
            frame: RecentResultWindowFrame(x: 80, y: 160, width: 460, height: 360),
            isPinned: false,
            visibility: .hiddenRestorable
        )
        let expectedVisible = CurrentWindowSnapshot(
            content: hidden.content,
            draft: hidden.draft,
            frame: hidden.frame,
            isPinned: hidden.isPinned,
            visibility: .visible
        )
        var browser = RecentResultsBrowserState(currentWindow: hidden)

        let restored = browser.showCurrentWindow()

        RecentResultsAppContractTestSupport.expect(
            restored == expectedVisible
                && browser.currentWindow == expectedVisible
                && browser.visibleWindowCount == 1,
            "TestRecentResultCurrentWindowRestoration.test_showCurrentWindow_restoresAHiddenCurrentDraftWithoutOpeningHistory"
        )
    }

    static func test_closeEscapeAndOutsideClick_hideHistoryWithoutDeletingRecordOrCurrentState() {
        for reason in [HistoryHideReason.close, .escape, .outsideClick] {
            let current = RecentResultsAppContractTestSupport.currentWindow()
            let store = RecentResultsAppContractTestSupport.store()
            var browser = RecentResultsBrowserState(currentWindow: current)
            _ = browser.openHistory(
                id: RecentResultsAppContractTestSupport.historyID,
                from: store,
                requestInFlight: false
            )

            browser.hideHistory(reason: reason)

            RecentResultsAppContractTestSupport.expect(
                browser.visibleHistoryWindow == nil
                    && store.entry(id: RecentResultsAppContractTestSupport.historyID) != nil
                    && browser.currentWindow == current,
                "TestRecentResultCurrentWindowRestoration.test_closeEscapeAndOutsideClick_hideHistoryWithoutDeletingRecordOrCurrentState[\(reason)]"
            )
        }
    }

    static func test_selectingAnotherHistory_reusesTheSingleWindowSlot() {
        var store = RecentResultsAppContractTestSupport.store()
        _ = store.upsert(
            RecentResultEntry(
                id: "second-history-route",
                kind: .translation,
                completedAt: Date(timeIntervalSince1970: 200),
                menuSummary: "second safe summary",
                snapshot: .translation(
                    sourceText: "synthetic-second-source",
                    resultText: "synthetic-second-result"
                )
            )
        )
        var browser = RecentResultsBrowserState(
            currentWindow: RecentResultsAppContractTestSupport.currentWindow()
        )

        _ = browser.openHistory(
            id: RecentResultsAppContractTestSupport.historyID,
            from: store,
            requestInFlight: false
        )
        _ = browser.openHistory(
            id: "second-history-route",
            from: store,
            requestInFlight: false
        )

        RecentResultsAppContractTestSupport.expect(
            browser.visibleWindowCount == 1
                && browser.visibleHistoryWindow?.entryID == "second-history-route",
            "TestRecentResultCurrentWindowRestoration.test_selectingAnotherHistory_reusesTheSingleWindowSlot"
        )
    }
}

final class TestRecentResultClearRouting {
    static func test_clearWhileHistoryVisible_closesReadOnlyWindowButPreservesCurrentWindow() {
        let current = RecentResultsAppContractTestSupport.currentWindow()
        var store = RecentResultsAppContractTestSupport.store()
        var browser = RecentResultsBrowserState(currentWindow: current)
        _ = browser.openHistory(
            id: RecentResultsAppContractTestSupport.historyID,
            from: store,
            requestInFlight: false
        )

        store.removeAll()
        browser.historyWasCleared()

        RecentResultsAppContractTestSupport.expect(
            store.entries.isEmpty
                && browser.visibleHistoryWindow == nil
                && browser.visibleWindowCount == 0
                && browser.currentWindow == current
                && browser.didStartNetworkRequest == false
                && browser.didRequestNetworkCancellation == false,
            "TestRecentResultClearRouting.test_clearWhileHistoryVisible_closesReadOnlyWindowButPreservesCurrentWindow"
        )
    }
}

@main
enum RecentResultsAppContractTests {
    static func main() {
        TestRecentResultIDRouting.test_existingID_opensExactlyOneReadOnlyWindowWithNoInputOrNetworkCapability()
        TestRecentResultIDRouting.test_missingOrEvictedID_refreshesSafelyWithoutOpeningWindow()
        TestRecentResultIDRouting.test_requestInFlight_blocksHistorySwitchWithoutCancellingOrHidingCurrentWindow()
        TestRecentResultCurrentWindowRestoration.test_browsingHistory_preservesCurrentContentDraftFramePinAndVisibilityForReturn()
        TestRecentResultCurrentWindowRestoration.test_showCurrentWindow_restoresAHiddenCurrentDraftWithoutOpeningHistory()
        TestRecentResultCurrentWindowRestoration.test_closeEscapeAndOutsideClick_hideHistoryWithoutDeletingRecordOrCurrentState()
        TestRecentResultCurrentWindowRestoration.test_selectingAnotherHistory_reusesTheSingleWindowSlot()
        TestRecentResultClearRouting.test_clearWhileHistoryVisible_closesReadOnlyWindowButPreservesCurrentWindow()

        if RecentResultsAppContractTestSupport.failures > 0 {
            print("\n\(RecentResultsAppContractTestSupport.failures) recent-results app contract test(s) failed")
            exit(1)
        }
        print("\nAll recent-results app contract tests passed")
    }
}
