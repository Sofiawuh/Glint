enum PopupPresentationState: Equatable {
    case dismissed
    case visible
    case hiddenRestorable
}

enum PopupOutsideClickAction: Equatable {
    case none
    case hide
    case dismiss
}

enum PopupNewSelectionAction: Equatable {
    case ignore
    case replace
}

struct PopupLifecycle {
    private(set) var state: PopupPresentationState = .dismissed
    private(set) var isPinned = false
    private(set) var isRestorableContent = false
    private(set) var allowsPinning = false

    var canRestore: Bool { state == .hiddenRestorable && isRestorableContent }

    mutating func present(isRestorableContent: Bool, allowsPinning: Bool) {
        state = .visible
        self.isRestorableContent = isRestorableContent
        self.allowsPinning = allowsPinning
        isPinned = false
    }

    @discardableResult
    mutating func togglePin() -> Bool {
        guard state == .visible, allowsPinning else { return false }
        isPinned.toggle()
        return true
    }

    mutating func outsideClick() -> PopupOutsideClickAction {
        guard state == .visible else { return .none }
        if isPinned { return .none }
        if isRestorableContent {
            state = .hiddenRestorable
            return .hide
        }
        dismiss()
        return .dismiss
    }

    @discardableResult
    mutating func restore() -> Bool {
        guard canRestore else { return false }
        state = .visible
        return true
    }

    func newSelection() -> PopupNewSelectionAction {
        state == .visible && isPinned ? .ignore : .replace
    }

    mutating func dismiss() {
        state = .dismissed
        isPinned = false
        isRestorableContent = false
        allowsPinning = false
    }
}
