import Foundation

enum TextCommandSelectedTextSource: Equatable {
    case accessibility
    case clipboard
}

struct TextCommandSelectedText: Equatable {
    let text: String
    let source: TextCommandSelectedTextSource
}

enum SelectedTextExtractionDecision: Equatable {
    case selected(TextCommandSelectedText)
    case copyRequired
}

struct TextCommandClipboardCapture: Equatable {
    let changeCountBefore: Int
    let changeCountAfter: Int
    let text: String?
    let types: [String]
}

struct TextCommandPasteboardItem: Equatable {
    let dataByType: [String: Data]
}

struct TextCommandClipboardTransaction {
    private let originalItems: [TextCommandPasteboardItem]
    private let changeCountBeforeCopy: Int
    private var observedCopyChangeCount: Int?
    private var readTokenIsValid = true

    init(
        originalItems: [TextCommandPasteboardItem],
        changeCountBeforeCopy: Int
    ) {
        self.originalItems = originalItems
        self.changeCountBeforeCopy = changeCountBeforeCopy
    }

    mutating func invalidateReadToken() {
        readTokenIsValid = false
    }

    mutating func observeCopy(changeCount: Int) -> Bool {
        guard readTokenIsValid,
              observedCopyChangeCount == nil,
              changeCount != changeCountBeforeCopy else { return false }
        observedCopyChangeCount = changeCount
        return true
    }

    func restorationItems(currentChangeCount: Int) -> [TextCommandPasteboardItem]? {
        guard let observedCopyChangeCount,
              observedCopyChangeCount == currentChangeCount else { return nil }
        return originalItems
    }
}

enum SelectedTextExtractor {
    private static let disallowedClipboardTypes: Set<String> = [
        "public.file-url",
        "nsfilenamespboardtype",
        "public.image",
        "public.png",
        "public.tiff",
        "public.jpeg",
        "public.jpeg-2000",
        "com.compuserve.gif",
        "public.heic",
        "public.heif"
    ]

    static func begin(axSelectedText: String?) -> SelectedTextExtractionDecision {
        let text = normalized(axSelectedText)
        guard !text.isEmpty else { return .copyRequired }
        return .selected(TextCommandSelectedText(
            text: text,
            source: .accessibility
        ))
    }

    static func completeClipboard(
        _ capture: TextCommandClipboardCapture
    ) -> TextCommandSelectedText? {
        guard capture.changeCountAfter != capture.changeCountBefore,
              !capture.types.contains(where: isDisallowedClipboardType) else { return nil }
        let text = normalized(capture.text)
        guard !text.isEmpty else { return nil }
        return TextCommandSelectedText(text: text, source: .clipboard)
    }

    private static func normalized(_ text: String?) -> String {
        text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func isDisallowedClipboardType(_ rawType: String) -> Bool {
        let type = rawType.lowercased()
        return disallowedClipboardTypes.contains(type)
            || type.contains("file-url")
            || type.contains("filenamespboardtype")
            || type.hasSuffix(".png")
            || type.hasSuffix(".tiff")
            || type.hasSuffix(".jpeg")
            || type.hasSuffix(".jpg")
            || type.hasSuffix(".gif")
            || type.hasSuffix(".heic")
            || type.hasSuffix(".heif")
    }
}
