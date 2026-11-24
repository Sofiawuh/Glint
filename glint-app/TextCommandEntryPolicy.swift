import Foundation

enum TextCommandAppInput: Equatable {
    case mouseReleased(clickCount: Int, displacement: Double)
    case mouseMoved
    case keyboardSelection
    case selectAll
    case textCommandHotKey
    case screenshotHotKey
    case escape
    case externalMouseDown
}

enum TextCommandAppAction: Equatable {
    case none
    case beginTextRead
    case beginScreenshot
    case dismissTextCommandPanel
}

enum TextCommandReadCheckpoint: Equatable {
    case beforeAccessibilityRead
    case afterAccessibilityRead
    case beforeProtectedCopy
    case duringProtectedCopy
    case beforePresentation
}

struct TextCommandReadIdentity: Equatable {
    let generation: UInt64
    let sourceApplicationPID: Int32
}

enum TextCommandReadSourcePolicy {
    static func allows(
        _ request: TextCommandReadIdentity,
        currentGeneration: UInt64,
        frontmostApplicationPID: Int32?,
        at checkpoint: TextCommandReadCheckpoint
    ) -> Bool {
        _ = checkpoint
        guard currentGeneration == request.generation,
              let frontmostApplicationPID else { return false }
        return frontmostApplicationPID == request.sourceApplicationPID
    }
}

enum TextCommandEntryPolicy {
    static func action(
        for input: TextCommandAppInput,
        panelIsVisible: Bool
    ) -> TextCommandAppAction {
        switch input {
        case .textCommandHotKey:
            return .beginTextRead
        case .screenshotHotKey:
            return .beginScreenshot
        case .escape, .externalMouseDown:
            return panelIsVisible ? .dismissTextCommandPanel : .none
        case .mouseReleased, .mouseMoved, .keyboardSelection, .selectAll:
            return .none
        }
    }
}
