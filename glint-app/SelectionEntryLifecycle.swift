import Foundation

struct SelectionReadGenerationToken: Equatable {
    fileprivate let generation: UInt64
}

struct SelectionReadGenerationGate {
    private var generation: UInt64 = 0

    mutating func beginRead() -> SelectionReadGenerationToken {
        generation &+= 1
        return SelectionReadGenerationToken(generation: generation)
    }

    mutating func invalidate() {
        generation &+= 1
    }

    func accepts(_ token: SelectionReadGenerationToken) -> Bool {
        token.generation == generation
    }
}

enum SelectionEntryPhase: Equatable {
    case hidden
    case marker
    case hoverPending
    case expanded
    case collapsePending
}

enum SelectionEntryTimerKind: Equatable {
    case expand
    case collapse
}

struct SelectionEntryTimerToken: Equatable {
    fileprivate let generation: UInt64
    fileprivate let sequence: UInt64
}

struct SelectionEntryTimerRequest: Equatable {
    let kind: SelectionEntryTimerKind
    let delayMilliseconds: Int
    let token: SelectionEntryTimerToken
}

enum SelectionEntryAction: Equatable {
    case translate
    case ask
}

struct SelectionEntrySubmission: Equatable {
    let action: SelectionEntryAction
    let snapshot: SelectionSnapshot
}

struct SelectionEntryLifecycle {
    private(set) var phase: SelectionEntryPhase = .hidden
    private(set) var currentSnapshot: SelectionSnapshot?

    private var generation: UInt64 = 0
    private var timerSequence: UInt64 = 0
    private var pendingTimer: SelectionEntryTimerToken?
    private var hasObservedPointerOutside = false

    mutating func present(
        _ snapshot: SelectionSnapshot,
        pointerInsideContinuousRegion: Bool
    ) {
        generation &+= 1
        invalidateTimer()
        currentSnapshot = snapshot
        phase = .marker
        hasObservedPointerOutside = !pointerInsideContinuousRegion
    }

    @discardableResult
    mutating func pointerMoved(isInsideContinuousRegion: Bool) -> SelectionEntryTimerRequest? {
        guard currentSnapshot != nil else { return nil }

        switch phase {
        case .hidden:
            return nil

        case .marker:
            guard isInsideContinuousRegion else {
                hasObservedPointerOutside = true
                return nil
            }
            guard hasObservedPointerOutside else { return nil }
            phase = .hoverPending
            return schedule(.expand, delayMilliseconds: 180)

        case .hoverPending:
            guard !isInsideContinuousRegion else { return nil }
            invalidateTimer()
            phase = .marker
            hasObservedPointerOutside = true
            return nil

        case .expanded:
            guard !isInsideContinuousRegion else { return nil }
            phase = .collapsePending
            return schedule(.collapse, delayMilliseconds: 400)

        case .collapsePending:
            guard isInsideContinuousRegion else { return nil }
            invalidateTimer()
            phase = .expanded
            return nil
        }
    }

    mutating func timerFired(_ token: SelectionEntryTimerToken) {
        guard token == pendingTimer, token.generation == generation else { return }
        pendingTimer = nil
        switch phase {
        case .hoverPending:
            phase = .expanded
        case .collapsePending:
            phase = .marker
            hasObservedPointerOutside = true
        default:
            break
        }
    }

    mutating func outsideMouseDown() {
        hide()
    }

    mutating func escapePressed() {
        hide()
    }

    mutating func selectionInvalidated() {
        hide()
    }

    mutating func submit(_ action: SelectionEntryAction) -> SelectionEntrySubmission? {
        guard let snapshot = currentSnapshot, phase != .hidden else { return nil }
        let submission = SelectionEntrySubmission(action: action, snapshot: snapshot)
        hide()
        return submission
    }

    mutating func hide() {
        generation &+= 1
        invalidateTimer()
        phase = .hidden
        currentSnapshot = nil
        hasObservedPointerOutside = false
    }

    private mutating func schedule(
        _ kind: SelectionEntryTimerKind,
        delayMilliseconds: Int
    ) -> SelectionEntryTimerRequest {
        timerSequence &+= 1
        let token = SelectionEntryTimerToken(generation: generation, sequence: timerSequence)
        pendingTimer = token
        return SelectionEntryTimerRequest(
            kind: kind,
            delayMilliseconds: delayMilliseconds,
            token: token
        )
    }

    private mutating func invalidateTimer() {
        pendingTimer = nil
        timerSequence &+= 1
    }
}
