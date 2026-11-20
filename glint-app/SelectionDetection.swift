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

enum SelectionProbeOrigin: Equatable {
    case focusedElement
    case hitElement
    case focusedAncestor(depth: Int)
    case hitAncestor(depth: Int)
}

struct SelectionProbeCandidate: Equatable {
    let origin: SelectionProbeOrigin
    let role: String
    let probe: SelectionProbe
}

enum SelectionEvidenceSource: Equatable {
    case accessibility
    case clipboardOnly
}

enum SelectionDeduplicationInvalidation: Equatable {
    case escape
    case ordinaryKey
    case mouseDown
    case sourceApplicationChanged
}

struct SelectionSnapshot: Equatable {
    let text: String
    let sourceApplication: String?
    let focusedElementIdentity: String?
    let rangeFingerprint: String?
    let boundsInQuartz: CGRect?
    let releasePointInQuartz: CGPoint
    let evidenceSource: SelectionEvidenceSource

    init(
        text: String,
        sourceApplication: String?,
        focusedElementIdentity: String?,
        rangeFingerprint: String?,
        boundsInQuartz: CGRect?,
        releasePointInQuartz: CGPoint,
        evidenceSource: SelectionEvidenceSource = .accessibility
    ) {
        self.text = text
        self.sourceApplication = sourceApplication
        self.focusedElementIdentity = focusedElementIdentity
        self.rangeFingerprint = rangeFingerprint
        self.boundsInQuartz = boundsInQuartz
        self.releasePointInQuartz = releasePointInQuartz
        self.evidenceSource = evidenceSource
    }
}

struct ClipboardFallbackCapture: Equatable {
    let changeCountBefore: Int
    let changeCountAfter: Int
    let text: String?
    let types: [String]
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

    mutating func invalidateClipboardOnlyDeduplication(
        for reason: SelectionDeduplicationInvalidation
    ) {
        _ = reason
        generation &+= 1
        guard stableSelection?.evidenceSource == .clipboardOnly else { return }
        stableSelection = nil
        stableProbe = nil
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
        if lhs.evidenceSource == .clipboardOnly || rhs.evidenceSource == .clipboardOnly {
            return lhs.evidenceSource == rhs.evidenceSource
                && lhs.text == rhs.text
                && lhs.sourceApplication == rhs.sourceApplication
        }
        return lhs.text == rhs.text
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
        if snapshot.evidenceSource == .clipboardOnly {
            return true
        }
        if let expectedElement = snapshot.focusedElementIdentity {
            return currentSource.focusedElementIdentity == expectedElement
        }
        return true
    }

    static func isValid(
        snapshot: SelectionSnapshot,
        currentProbe: SelectionProbe?
    ) -> Bool {
        if snapshot.evidenceSource == .clipboardOnly {
            return false
        }
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

enum ClipboardRestorationPolicy {
    struct CopyTransaction {
        private let changeCountBeforeCopy: Int
        private var observedCopyChangeCount: Int?
        private var readTokenIsValid = true

        init(changeCountBeforeCopy: Int) {
            self.changeCountBeforeCopy = changeCountBeforeCopy
        }

        mutating func invalidateReadToken() {
            readTokenIsValid = false
        }

        mutating func observePasteboardChange(changeCount: Int) -> Bool {
            guard readTokenIsValid,
                  observedCopyChangeCount == nil,
                  changeCount != changeCountBeforeCopy else { return false }
            observedCopyChangeCount = changeCount
            return true
        }

        func shouldRestore(currentChangeCount: Int) -> Bool {
            guard let observedCopyChangeCount else { return false }
            return ClipboardRestorationPolicy.shouldRestore(
                copiedChangeCount: observedCopyChangeCount,
                currentChangeCount: currentChangeCount
            )
        }
    }

    static func shouldRestore(
        copiedChangeCount: Int,
        currentChangeCount: Int
    ) -> Bool {
        copiedChangeCount == currentChangeCount
    }
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

    private static let explicitNonTextRoles: Set<String> = [
        "AXButton",
        "AXCheckBox",
        "AXRadioButton",
        "AXMenu",
        "AXMenuBar",
        "AXMenuItem",
        "AXImage",
        "AXIcon",
        "AXDisclosureTriangle",
        "AXTabGroup",
    ]

    private static let preferredCandidateRoles: Set<String> = textRoles

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
        "public.heif",
    ]

    static func bestCandidate(
        from candidates: [SelectionProbeCandidate]
    ) -> SelectionProbeCandidate? {
        candidates.enumerated().compactMap { index, candidate -> (Int, Int, SelectionProbeCandidate)? in
            let text = candidate.probe.text?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty, candidate.probe.rangeLength != 0 else { return nil }

            let hasNonzeroRange = (candidate.probe.rangeLength ?? 0) > 0
            let hasRangeFingerprint = candidate.probe.rangeFingerprint != nil
            let hasBounds = candidate.probe.boundsInQuartz != nil
            let evidenceRank: Int
            if hasNonzeroRange && hasRangeFingerprint && hasBounds {
                evidenceRank = 3
            } else if hasNonzeroRange && (hasRangeFingerprint || hasBounds) {
                evidenceRank = 2
            } else {
                evidenceRank = 1
            }

            let roleBonus = preferredCandidateRoles.contains(candidate.role) ? 1 : 0
            let originBonus: Int
            switch candidate.origin {
            case .focusedElement:
                originBonus = 400
            case .hitElement:
                originBonus = 300
            case .focusedAncestor(let depth):
                originBonus = max(0, 200 - depth)
            case .hitAncestor(let depth):
                originBonus = max(0, 100 - depth)
            }
            let tieRank = roleBonus * 10_000 + originBonus
            return (evidenceRank, tieRank - index, candidate)
        }.max { lhs, rhs in
            if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
            return lhs.1 < rhs.1
        }?.2
    }

    static func allowsClipboardFallback(
        clickCount: Int,
        displacement: CGPoint,
        pressedRolePath: [String],
        releasedRolePath: [String]
    ) -> Bool {
        guard !containsExcludedRole(pressedRolePath),
              !containsExcludedRole(releasedRolePath) else { return false }
        if clickCount >= 2 { return true }
        return hypot(displacement.x, displacement.y) >= 4.0
    }

    static func shouldAttemptClipboardFallback(
        outcome: SelectionDetectionOutcome,
        clickCount: Int,
        displacement: CGPoint,
        pressedRolePath: [String],
        releasedRolePath: [String]
    ) -> Bool {
        guard outcome == .clipboardFallbackEligible else { return false }
        return allowsClipboardFallback(
            clickCount: clickCount,
            displacement: displacement,
            pressedRolePath: pressedRolePath,
            releasedRolePath: releasedRolePath
        )
    }

    static func clipboardOnlySnapshot(
        capture: ClipboardFallbackCapture,
        sourceApplication: String?,
        focusedElementIdentity: String?,
        releasePointInQuartz: CGPoint
    ) -> SelectionSnapshot? {
        guard capture.changeCountAfter != capture.changeCountBefore,
              !containsDisallowedClipboardType(capture.types),
              let rawText = capture.text else { return nil }
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return SelectionSnapshot(
            text: text,
            sourceApplication: sourceApplication,
            focusedElementIdentity: focusedElementIdentity,
            rangeFingerprint: nil,
            boundsInQuartz: nil,
            releasePointInQuartz: releasePointInQuartz,
            evidenceSource: .clipboardOnly
        )
    }

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
            return isExplicitNonTextPath(pressedRolePath)
                || isExplicitNonTextPath(releasedRolePath)
                ? .ignored
                : .clipboardFallbackEligible
        }

        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, after.rangeLength != 0 else { return .ignored }

        if let before, selectionEvidenceIsUnchanged(before: before, after: after, trimmedAfterText: text) {
            return .ignored
        }

        let hasRangeEvidence = (after.rangeLength ?? 0) > 0
            || after.rangeFingerprint != nil
            || after.boundsInQuartz != nil
        guard hasRangeEvidence else { return .clipboardFallbackEligible }
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

    private static func containsDisallowedClipboardType(_ types: [String]) -> Bool {
        types.contains { rawType in
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

    private static func isTextSelectionPath(_ roles: [String]) -> Bool {
        !roles.isEmpty && roles.contains(where: textRoles.contains)
    }

    private static func isExplicitNonTextPath(_ roles: [String]) -> Bool {
        !roles.isEmpty && roles.contains(where: explicitNonTextRoles.contains)
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
