import Foundation

struct RecentResultWindowFrame: Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

enum CurrentWindowContent: Equatable {
    case translation(resultText: String)
    case questionComposer(selectedText: String)
    case questionConversation(selectedText: String, transcript: [RecentResultTurn])
    case screenshotComposer
    case screenshotConversation
}

enum CurrentWindowVisibility: Equatable {
    case visible
    case hiddenRestorable
}

struct CurrentWindowSnapshot: Equatable {
    let content: CurrentWindowContent
    let draft: String
    let frame: RecentResultWindowFrame
    let isPinned: Bool
    let visibility: CurrentWindowVisibility
}

struct ReadOnlyHistoryWindow: Equatable {
    let entryID: String
    let snapshot: RecentResultSnapshot
    let allowsCopy = true
    let allowsPinning = true
    let allowsClose = true
    let allowsResize = true
    let hasPromptInput = false
    let hasSendButton = false
    let canStartNetworkRequest = false
}

enum RecentResultHistoryRoute: Equatable {
    case opened(String)
    case missingRefreshMenu
    case blockedInFlight
}

enum HistoryHideReason: Equatable {
    case close
    case escape
    case outsideClick
}

struct RecentResultsBrowserState {
    private(set) var currentWindow: CurrentWindowSnapshot?
    private(set) var visibleHistoryWindow: ReadOnlyHistoryWindow?
    private(set) var didStartNetworkRequest = false
    private(set) var didRequestNetworkCancellation = false
    private var currentWindowIsDisplayed = false

    init(currentWindow: CurrentWindowSnapshot? = nil) {
        self.currentWindow = currentWindow
    }

    var visibleWindowCount: Int {
        if visibleHistoryWindow != nil { return 1 }
        return currentWindowIsDisplayed ? 1 : 0
    }

    mutating func openHistory(
        id: String,
        from store: RecentResultStore,
        requestInFlight: Bool
    ) -> RecentResultHistoryRoute {
        guard !requestInFlight else { return .blockedInFlight }
        guard let entry = store.entry(id: id) else {
            visibleHistoryWindow = nil
            currentWindowIsDisplayed = false
            return .missingRefreshMenu
        }
        visibleHistoryWindow = ReadOnlyHistoryWindow(
            entryID: entry.id,
            snapshot: entry.snapshot
        )
        currentWindowIsDisplayed = false
        return .opened(entry.id)
    }

    @discardableResult
    mutating func showCurrentWindow() -> CurrentWindowSnapshot? {
        visibleHistoryWindow = nil
        guard let currentWindow else {
            currentWindowIsDisplayed = false
            return nil
        }
        let visible = CurrentWindowSnapshot(
            content: currentWindow.content,
            draft: currentWindow.draft,
            frame: currentWindow.frame,
            isPinned: currentWindow.isPinned,
            visibility: .visible
        )
        self.currentWindow = visible
        currentWindowIsDisplayed = true
        return visible
    }

    mutating func hideHistory(reason: HistoryHideReason) {
        visibleHistoryWindow = nil
        currentWindowIsDisplayed = false
    }

    mutating func historyWasCleared() {
        visibleHistoryWindow = nil
        currentWindowIsDisplayed = false
    }
}
