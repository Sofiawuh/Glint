import Foundation

enum RecentResultKind: String, Equatable {
    case translation
    case question

    var menuLabel: String {
        switch self {
        case .translation: return "翻译"
        case .question: return "提问"
        }
    }
}

enum RecentResultTurnRole: String, Equatable {
    case user
    case assistant
}

struct RecentResultTurn: Equatable {
    let role: RecentResultTurnRole
    let content: String
}

enum RecentResultSnapshot: Equatable {
    case translation(sourceText: String, resultText: String)
    case question(selectedText: String, transcript: [RecentResultTurn])

    var textByteCount: Int {
        switch self {
        case .translation(let sourceText, let resultText):
            return sourceText.utf8.count + resultText.utf8.count
        case .question(let selectedText, let transcript):
            return selectedText.utf8.count
                + transcript.reduce(0) { $0 + $1.content.utf8.count }
        }
    }
}

struct RecentResultEntry: Equatable {
    let id: String
    let kind: RecentResultKind
    let completedAt: Date
    let menuSummary: String
    let snapshot: RecentResultSnapshot

    var textByteCount: Int {
        menuSummary.utf8.count + snapshot.textByteCount
    }
}

enum RecentResultStoreMutation: String, Equatable {
    case inserted
    case updated
    case rejectedOversized
}

struct RecentResultStore {
    static let defaultMaxEntries = 10
    static let defaultMaxTextBytes = 10 * 1_024 * 1_024

    let maxEntries: Int
    let maxTextBytes: Int
    private(set) var entries: [RecentResultEntry] = []

    init(
        maxEntries: Int = RecentResultStore.defaultMaxEntries,
        maxTextBytes: Int = RecentResultStore.defaultMaxTextBytes
    ) {
        self.maxEntries = max(0, maxEntries)
        self.maxTextBytes = max(0, maxTextBytes)
    }

    func entry(id: String) -> RecentResultEntry? {
        entries.first { $0.id == id }
    }

    @discardableResult
    mutating func upsert(_ entry: RecentResultEntry) -> RecentResultStoreMutation {
        guard entry.textByteCount <= maxTextBytes else {
            return .rejectedOversized
        }

        let wasExisting = entries.contains { $0.id == entry.id }
        entries.removeAll { $0.id == entry.id }
        entries.append(entry)
        entries.sort {
            if $0.completedAt == $1.completedAt { return $0.id > $1.id }
            return $0.completedAt > $1.completedAt
        }

        while entries.count > maxEntries || totalTextBytes > maxTextBytes {
            guard !entries.isEmpty else { break }
            entries.removeLast()
        }
        return wasExisting ? .updated : .inserted
    }

    mutating func removeAll() {
        entries.removeAll(keepingCapacity: false)
    }

    private var totalTextBytes: Int {
        entries.reduce(0) { $0 + $1.textByteCount }
    }
}

enum RecentResultCompletion {
    case translationLoading
    case translationSucceeded(
        id: String,
        sourceText: String,
        resultText: String,
        menuSummary: String,
        completedAt: Date
    )
    case translationFailed
    case textQuestionCompleted(
        id: String,
        selectedText: String,
        transcript: [RecentResultTurn],
        menuSummary: String,
        completedAt: Date
    )
    case textQuestionCancelled
    case textQuestionFailed
    case textQuestionDraft
    case screenshotQuestionCompleted
}

enum RecentResultRecorder {
    static func makeEntry(from completion: RecentResultCompletion) -> RecentResultEntry? {
        switch completion {
        case .translationSucceeded(
            let id,
            let sourceText,
            let resultText,
            let menuSummary,
            let completedAt
        ):
            let trimmedResult = resultText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedResult.isEmpty else { return nil }
            return RecentResultEntry(
                id: id,
                kind: .translation,
                completedAt: completedAt,
                menuSummary: menuSummary,
                snapshot: .translation(sourceText: sourceText, resultText: trimmedResult)
            )

        case .textQuestionCompleted(
            let id,
            let selectedText,
            let transcript,
            let menuSummary,
            let completedAt
        ):
            guard transcript.contains(where: {
                $0.role == .user
                    && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }), transcript.last?.role == .assistant,
            let lastContent = transcript.last?.content,
            !lastContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return RecentResultEntry(
                id: id,
                kind: .question,
                completedAt: completedAt,
                menuSummary: menuSummary,
                snapshot: .question(selectedText: selectedText, transcript: transcript)
            )

        case .translationLoading,
             .translationFailed,
             .textQuestionCancelled,
             .textQuestionFailed,
             .textQuestionDraft,
             .screenshotQuestionCompleted:
            return nil
        }
    }
}

enum RecentResultsMenuItemRole: Equatable {
    case history
    case separator
    case emptyState
    case clear
}

struct RecentResultsMenuItemModel: Equatable {
    let id: String?
    let title: String
    let isEnabled: Bool
    let role: RecentResultsMenuItemRole
}

struct RecentResultsMenuModel {
    let items: [RecentResultsMenuItemModel]

    init(
        entries: [RecentResultEntry],
        historySwitchingEnabled: Bool,
        summaryCharacterLimit: Int = 42,
        timeZone: TimeZone = .current
    ) {
        let sorted = entries.sorted {
            if $0.completedAt == $1.completedAt { return $0.id > $1.id }
            return $0.completedAt > $1.completedAt
        }
        var result: [RecentResultsMenuItemModel] = []
        if sorted.isEmpty {
            result.append(RecentResultsMenuItemModel(
                id: nil,
                title: "暂无最近结果",
                isEnabled: false,
                role: .emptyState
            ))
        } else {
            result.append(contentsOf: sorted.map { entry in
                RecentResultsMenuItemModel(
                    id: entry.id,
                    title: Self.title(
                        for: entry,
                        summaryCharacterLimit: summaryCharacterLimit,
                        timeZone: timeZone
                    ),
                    isEnabled: historySwitchingEnabled,
                    role: .history
                )
            })
        }
        result.append(RecentResultsMenuItemModel(
            id: nil,
            title: "",
            isEnabled: false,
            role: .separator
        ))
        result.append(RecentResultsMenuItemModel(
            id: nil,
            title: "清空最近结果",
            isEnabled: !sorted.isEmpty,
            role: .clear
        ))
        items = result
    }

    private static func title(
        for entry: RecentResultEntry,
        summaryCharacterLimit: Int,
        timeZone: TimeZone
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: entry.completedAt))  \(entry.kind.menuLabel) · \(summary(entry.menuSummary, limit: summaryCharacterLimit))"
    }

    private static func summary(_ raw: String, limit: Int) -> String {
        let normalized = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let safeLimit = max(1, limit)
        guard normalized.count > safeLimit else { return normalized }
        return String(normalized.prefix(safeLimit)) + "…"
    }
}

enum RecentResultsLogEvent {
    case upserted(
        entryID: String,
        kind: RecentResultKind,
        count: Int,
        mutation: RecentResultStoreMutation
    )
    case routeMissing(entryID: String, count: Int)
    case cleared(previousCount: Int)

    var message: String {
        switch self {
        case .upserted(let entryID, let kind, let count, let mutation):
            return "RECENT_RESULTS upsert id=\(entryID) kind=\(kind.rawValue) count=\(count) mutation=\(mutation.rawValue)"
        case .routeMissing(let entryID, let count):
            return "RECENT_RESULTS route-missing id=\(entryID) count=\(count)"
        case .cleared(let previousCount):
            return "RECENT_RESULTS cleared previousCount=\(previousCount)"
        }
    }
}
