import Foundation
import CoreGraphics

enum TextCommandPanelAction: Equatable {
    case translate
    case ask
}

struct TextCommandPanelRequest: Equatable {
    fileprivate let generation: UInt64
}

enum TextCommandPanelState: Equatable {
    case hidden
    case reading
    case visible(
        text: String,
        mouseLocation: CGPoint,
        actions: [TextCommandPanelAction]
    )
}

struct TextCommandPanelSubmission: Equatable {
    let action: TextCommandPanelAction
    let text: String
}

struct TextCommandPanelLifecycle {
    private var generation: UInt64 = 0
    private(set) var state: TextCommandPanelState = .hidden

    mutating func beginRequest() -> TextCommandPanelRequest {
        generation &+= 1
        state = .reading
        return TextCommandPanelRequest(generation: generation)
    }

    @discardableResult
    mutating func completeRequest(
        _ request: TextCommandPanelRequest,
        text rawText: String,
        mouseLocation: CGPoint
    ) -> Bool {
        guard request.generation == generation else { return false }
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            state = .hidden
            return false
        }
        state = .visible(
            text: text,
            mouseLocation: mouseLocation,
            actions: [.translate, .ask]
        )
        return true
    }

    mutating func completeWithoutText(_ request: TextCommandPanelRequest) -> Bool {
        guard request.generation == generation else { return false }
        state = .hidden
        return true
    }

    mutating func handleOutsideClick() {
        guard case .visible = state else { return }
        generation &+= 1
        state = .hidden
    }

    mutating func handleEscape() {
        handleOutsideClick()
    }

    mutating func hide() {
        generation &+= 1
        state = .hidden
    }

    mutating func submit(_ action: TextCommandPanelAction) -> TextCommandPanelSubmission? {
        guard case .visible(let text, _, let actions) = state,
              actions.contains(action) else { return nil }
        generation &+= 1
        state = .hidden
        return TextCommandPanelSubmission(action: action, text: text)
    }
}
