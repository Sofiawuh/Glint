import Foundation
import CoreGraphics

struct SelectionProbe: Equatable {
    let text: String?
    let sourceApplication: String?
    let focusedElementIdentity: String?
    let rangeLength: Int?
    let rangeFingerprint: String?
    let boundsInQuartz: CGRect?
    let releasePointInQuartz: CGPoint
}

struct SelectionSnapshot: Equatable {
    let text: String
    let sourceApplication: String?
    let focusedElementIdentity: String?
    let rangeFingerprint: String?
    let boundsInQuartz: CGRect?
    let releasePointInQuartz: CGPoint
}

enum KeyboardSelectionTrigger: Equatable {
    case extendSelection
    case selectAll
}

enum SelectionObservationTrigger: Equatable {
    case mouseRelease(clickCount: Int, displacement: CGPoint)
    case keyboardSelection(KeyboardSelectionTrigger)
    case revalidation
    case baseline
}

struct SelectionObservationRequest: Equatable {
    fileprivate let generation: UInt64
    let trigger: SelectionObservationTrigger
    let baseline: SelectionSnapshot?
    let baselineProbe: SelectionProbe?
}

enum SelectionObservationDecision: Equatable {
    case present(SelectionSnapshot)
    case unchanged
    case clear
    case stale
}

struct SelectionObservationTracker {
    private var generation: UInt64 = 0
    private(set) var stableSelection: SelectionSnapshot?
    private var stableProbe: SelectionProbe?

    mutating func beginObservation(
        _ trigger: SelectionObservationTrigger
    ) -> SelectionObservationRequest {
        generation &+= 1
        return SelectionObservationRequest(
            generation: generation,
            trigger: trigger,
            baseline: stableSelection,
            baselineProbe: stableProbe
        )
    }

    mutating func completeObservation(
        _ request: SelectionObservationRequest,
        probe: SelectionProbe
    ) -> SelectionObservationDecision {
        guard request.generation == generation else { return .stale }
        stableProbe = probe
        guard let snapshot = snapshot(from: probe, trigger: request.trigger) else {
            stableSelection = nil
            return .clear
        }
        return accept(snapshot)
    }

    mutating func completeObservation(
        _ request: SelectionObservationRequest,
        snapshot: SelectionSnapshot
    ) -> SelectionObservationDecision {
        guard request.generation == generation else { return .stale }
        stableProbe = SelectionProbe(
            text: snapshot.text,
            sourceApplication: snapshot.sourceApplication,
            focusedElementIdentity: snapshot.focusedElementIdentity,
            rangeLength: snapshot.rangeFingerprint == nil && snapshot.boundsInQuartz == nil ? nil : 1,
            rangeFingerprint: snapshot.rangeFingerprint,
            boundsInQuartz: snapshot.boundsInQuartz,
            releasePointInQuartz: snapshot.releasePointInQuartz
        )
        return accept(snapshot)
    }

    mutating func seed(with probe: SelectionProbe?) {
        generation &+= 1
        guard let probe else {
            stableSelection = nil
            stableProbe = nil
            return
        }
        stableProbe = probe
        stableSelection = snapshot(
            from: probe,
            trigger: .mouseRelease(clickCount: 1, displacement: .zero)
        )
    }

    mutating func invalidatePendingObservations() {
        generation &+= 1
    }

    private mutating func accept(
        _ snapshot: SelectionSnapshot
    ) -> SelectionObservationDecision {
        if let stableSelection, sameSelection(stableSelection, snapshot) {
            return .unchanged
        }
        stableSelection = snapshot
        return .present(snapshot)
    }

    private func snapshot(
        from probe: SelectionProbe,
        trigger: SelectionObservationTrigger
    ) -> SelectionSnapshot? {
        let text = probe.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty,
              (probe.rangeLength ?? 0) > 0,
              probe.rangeFingerprint != nil || probe.boundsInQuartz != nil else { return nil }
        if case .keyboardSelection = trigger, probe.boundsInQuartz == nil {
            return nil
        }
        return SelectionSnapshot(
            text: text,
            sourceApplication: probe.sourceApplication,
            focusedElementIdentity: probe.focusedElementIdentity,
            rangeFingerprint: probe.rangeFingerprint,
            boundsInQuartz: probe.boundsInQuartz,
            releasePointInQuartz: probe.releasePointInQuartz
        )
    }

    private func sameSelection(
        _ lhs: SelectionSnapshot,
        _ rhs: SelectionSnapshot
    ) -> Bool {
        lhs.text == rhs.text
            && lhs.sourceApplication == rhs.sourceApplication
            && lhs.focusedElementIdentity == rhs.focusedElementIdentity
            && lhs.rangeFingerprint == rhs.rangeFingerprint
            && lhs.boundsInQuartz == rhs.boundsInQuartz
    }
}

struct SelectionSourceIdentity: Equatable {
    let sourceApplication: String?
    let focusedElementIdentity: String?
}

enum SelectionSourceRevalidation {
    static func isValid(
        snapshot: SelectionSnapshot,
        currentSource: SelectionSourceIdentity
    ) -> Bool {
        guard let expectedApplication = snapshot.sourceApplication,
              let currentApplication = currentSource.sourceApplication,
              expectedApplication == currentApplication else { return false }
        if let expectedElement = snapshot.focusedElementIdentity {
            return currentSource.focusedElementIdentity == expectedElement
        }
        return true
    }

    static func isValid(
        snapshot: SelectionSnapshot,
        currentProbe: SelectionProbe?
    ) -> Bool {
        guard let currentProbe,
              isValid(
                snapshot: snapshot,
                currentSource: SelectionSourceIdentity(
                    sourceApplication: currentProbe.sourceApplication,
                    focusedElementIdentity: currentProbe.focusedElementIdentity
                )
              ) else { return false }

        let currentText = currentProbe.text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard currentText == snapshot.text,
              (currentProbe.rangeLength ?? 0) > 0 else { return false }

        if let expectedRange = snapshot.rangeFingerprint {
            guard currentProbe.rangeFingerprint == expectedRange else { return false }
        }
        if let expectedBounds = snapshot.boundsInQuartz {
            guard currentProbe.boundsInQuartz == expectedBounds else { return false }
        }
        return snapshot.rangeFingerprint != nil || snapshot.boundsInQuartz != nil
    }
}

enum SelectionDetectionOutcome: Equatable {
    case accepted(SelectionSnapshot)
    case clipboardFallbackEligible
    case ignored
}

enum SelectionDetection {
    private static let excludedRoles: Set<String> = [
        "AXScrollBar",
        "AXScrollAreaThumb",
        "AXSlider",
        "AXSplitter",
        "AXIncrementor",
        "AXColumnHeader",
        "AXRowHeader",
        "AXRuler",
        "AXResizeHandle",
        "AXColumnResizeHandle",
        "AXRowResizeHandle",
        "AXGrowArea",
        "AXWindowResizeHandle",
        "AXToolbarDragArea",
    ]

    private static let textRoles: Set<String> = [
        "AXTextArea",
        "AXTextField",
        "AXStaticText",
        "AXWebArea",
        "AXDocument",
        "AXCell",
        "AXLink",
    ]

    static func evaluate(
        before: SelectionProbe?,
        after: SelectionProbe,
        pressedRolePath: [String],
        releasedRolePath: [String]
    ) -> SelectionDetectionOutcome {
        if containsExcludedRole(pressedRolePath) || containsExcludedRole(releasedRolePath) {
            return .ignored
        }
        if let beforeApplication = before?.sourceApplication,
           let afterApplication = after.sourceApplication,
           beforeApplication != afterApplication {
            return .ignored
        }

        guard let rawText = after.text else {
            return isTextSelectionPath(pressedRolePath) && isTextSelectionPath(releasedRolePath)
                ? .clipboardFallbackEligible
                : .ignored
        }

        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, after.rangeLength != 0 else { return .ignored }

        if let before, selectionEvidenceIsUnchanged(before: before, after: after, trimmedAfterText: text) {
            return .ignored
        }

        let hasRangeEvidence = (after.rangeLength ?? 0) > 0
            || after.rangeFingerprint != nil
            || after.boundsInQuartz != nil
        let textChanged = before.map {
            ($0.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) != text
        } ?? true
        guard hasRangeEvidence || textChanged else { return .ignored }

        return .accepted(SelectionSnapshot(
            text: text,
            sourceApplication: after.sourceApplication,
            focusedElementIdentity: after.focusedElementIdentity,
            rangeFingerprint: after.rangeFingerprint,
            boundsInQuartz: after.boundsInQuartz,
            releasePointInQuartz: after.releasePointInQuartz
        ))
    }

    static func clipboardSnapshot(
        text rawText: String,
        selectionEvidence: SelectionProbe,
        evidenceChanged: Bool
    ) -> SelectionSnapshot? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasEvidence = selectionEvidence.rangeFingerprint != nil
            || selectionEvidence.boundsInQuartz != nil
        guard evidenceChanged, hasEvidence, !text.isEmpty else { return nil }
        return SelectionSnapshot(
            text: text,
            sourceApplication: selectionEvidence.sourceApplication,
            focusedElementIdentity: selectionEvidence.focusedElementIdentity,
            rangeFingerprint: selectionEvidence.rangeFingerprint,
            boundsInQuartz: selectionEvidence.boundsInQuartz,
            releasePointInQuartz: selectionEvidence.releasePointInQuartz
        )
    }

    static func reliableSelectionEvidenceChanged(
        before: SelectionProbe?,
        after: SelectionProbe
    ) -> Bool {
        guard let before else { return false }
        if let beforeApplication = before.sourceApplication,
           let afterApplication = after.sourceApplication,
           beforeApplication != afterApplication {
            return false
        }
        let hasNonzeroRange = (after.rangeLength ?? 0) > 0
        let hasRangeOrBounds = after.rangeFingerprint != nil || after.boundsInQuartz != nil
        guard hasNonzeroRange && hasRangeOrBounds else { return false }
        return before.rangeLength != after.rangeLength
            || before.rangeFingerprint != after.rangeFingerprint
            || before.boundsInQuartz != after.boundsInQuartz
    }

    private static func containsExcludedRole(_ roles: [String]) -> Bool {
        roles.contains { role in
            excludedRoles.contains(role)
                || role.localizedCaseInsensitiveContains("resizehandle")
                || role.localizedCaseInsensitiveContains("resizer")
                || role.localizedCaseInsensitiveContains("scrollbarthumb")
        }
    }

    private static func isTextSelectionPath(_ roles: [String]) -> Bool {
        !roles.isEmpty && roles.contains(where: textRoles.contains)
    }

    private static func selectionEvidenceIsUnchanged(
        before: SelectionProbe,
        after: SelectionProbe,
        trimmedAfterText: String
    ) -> Bool {
        let beforeText = (before.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return before.sourceApplication == after.sourceApplication
            && before.focusedElementIdentity == after.focusedElementIdentity
            && beforeText == trimmedAfterText
            && before.rangeLength == after.rangeLength
            && before.rangeFingerprint == after.rangeFingerprint
            && before.boundsInQuartz == after.boundsInQuartz
    }
}
