import Foundation

struct SelectionEntryKeyboardInput: Equatable {
    let keyCode: Int64
    let sourceUserData: Int64
}

enum SelectionEntryKeyboardDecision: Equatable {
    case ignoreInternalSyntheticCopy
    case dismissEntry
    case revalidateSourceAndSelection
}

struct SelectionEntryKeyboardRevalidationRequest: Equatable {
    let snapshot: SelectionSnapshot
}

enum SelectionEntryKeyboardClassifier {
    // "GLINTCOP" encoded as an Int64. Only Glint's synthetic copy events use this tag.
    static let internalSyntheticCopySourceUserData: Int64 = 0x474C494E54434F50

    static func classify(
        _ input: SelectionEntryKeyboardInput
    ) -> SelectionEntryKeyboardDecision {
        if input.sourceUserData == internalSyntheticCopySourceUserData {
            return .ignoreInternalSyntheticCopy
        }
        if input.keyCode == 53 {
            return .dismissEntry
        }
        return .revalidateSourceAndSelection
    }

    static func selectionTrigger(
        keyCode: Int64,
        shiftPressed: Bool,
        commandPressed: Bool
    ) -> KeyboardSelectionTrigger? {
        if commandPressed, keyCode == 0 {
            return .selectAll
        }
        let navigationKeyCodes: Set<Int64> = [
            115, // Home
            116, // Page Up
            119, // End
            121, // Page Down
            123, // Left Arrow
            124, // Right Arrow
            125, // Down Arrow
            126, // Up Arrow
        ]
        if shiftPressed, navigationKeyCodes.contains(keyCode) {
            return .extendSelection
        }
        return nil
    }
}

enum SelectionEntryKeyboardHandler {
    @discardableResult
    static func handle(
        _ input: SelectionEntryKeyboardInput,
        readGate: inout SelectionReadGenerationGate,
        lifecycle: inout SelectionEntryLifecycle,
        revalidateSourceAndSelection: () -> Bool
    ) -> SelectionEntryKeyboardDecision {
        let decision = SelectionEntryKeyboardClassifier.classify(input)
        switch decision {
        case .ignoreInternalSyntheticCopy:
            break
        case .dismissEntry:
            readGate.invalidate()
            lifecycle.escapePressed()
        case .revalidateSourceAndSelection:
            readGate.invalidate()
            if !revalidateSourceAndSelection() {
                lifecycle.selectionInvalidated()
            }
        }
        return decision
    }

    static func beginRevalidation(
        for lifecycle: SelectionEntryLifecycle
    ) -> SelectionEntryKeyboardRevalidationRequest? {
        lifecycle.currentSnapshot.map {
            SelectionEntryKeyboardRevalidationRequest(snapshot: $0)
        }
    }

    @discardableResult
    static func completeRevalidation(
        _ request: SelectionEntryKeyboardRevalidationRequest,
        sourceAndSelectionAreValid: Bool,
        lifecycle: inout SelectionEntryLifecycle
    ) -> Bool {
        guard lifecycle.currentSnapshot == request.snapshot else { return false }
        if !sourceAndSelectionAreValid {
            lifecycle.selectionInvalidated()
        }
        return true
    }
}
