import AppKit
import ApplicationServices

struct SelectionPressContext {
    let before: SelectionProbe?
    let pressedRolePath: [String]
}

struct SelectionReadEvaluation {
    let outcome: SelectionDetectionOutcome
    let selectionEvidence: SelectionProbe
    let releasedRolePath: [String]
    let hasRange: Bool
    let hasBounds: Bool
    let clipboardEvidenceChanged: Bool
}

final class AccessibilitySelectionReader {
    private struct AccessibilityCandidate {
        let element: AXUIElement
        let origin: SelectionProbeOrigin
        let role: String
    }

    func capturePress(at quartzPoint: CGPoint) -> SelectionPressContext {
        let hit = element(at: quartzPoint)
        let roles = rolePath(startingAt: hit)
        return SelectionPressContext(
            before: bestSelectionProbe(releasePoint: quartzPoint, hitElement: hit),
            pressedRolePath: roles
        )
    }

    func evaluateRelease(
        from press: SelectionPressContext?,
        at quartzPoint: CGPoint,
        previousProbe: SelectionProbe?
    ) -> SelectionReadEvaluation {
        let hit = element(at: quartzPoint)
        let releasedRoles = rolePath(startingAt: hit)
        let after = bestSelectionProbe(releasePoint: quartzPoint, hitElement: hit)
            ?? SelectionProbe(
                text: nil,
                sourceApplication: frontmostApplicationIdentity(),
                focusedElementIdentity: nil,
                rangeLength: nil,
                rangeFingerprint: nil,
                boundsInQuartz: nil,
                releasePointInQuartz: quartzPoint
            )
        let outcome = SelectionDetection.evaluate(
            before: press?.before ?? previousProbe,
            after: after,
            pressedRolePath: press?.pressedRolePath ?? releasedRoles,
            releasedRolePath: releasedRoles
        )
        return SelectionReadEvaluation(
            outcome: outcome,
            selectionEvidence: after,
            releasedRolePath: releasedRoles,
            hasRange: after.rangeFingerprint != nil,
            hasBounds: after.boundsInQuartz != nil,
            clipboardEvidenceChanged: SelectionDetection.reliableSelectionEvidenceChanged(
                before: press?.before ?? previousProbe,
                after: after
            )
        )
    }

    func currentSourceIdentity() -> SelectionSourceIdentity {
        let systemWide = AXUIElementCreateSystemWide()
        let focused = copyElementAttribute(
            kAXFocusedUIElementAttribute as CFString,
            from: systemWide
        )
        return SelectionSourceIdentity(
            sourceApplication: frontmostApplicationIdentity(),
            focusedElementIdentity: focused.map(elementIdentity)
        )
    }

    func currentSelectionProbe() -> SelectionProbe? {
        bestSelectionProbe(releasePoint: .zero, hitElement: nil)
    }

    private func bestSelectionProbe(
        releasePoint: CGPoint,
        hitElement: AXUIElement?
    ) -> SelectionProbe? {
        let systemWide = AXUIElementCreateSystemWide()
        let focused = copyElementAttribute(
            kAXFocusedUIElementAttribute as CFString,
            from: systemWide
        )
        let application = frontmostApplicationIdentity()
        let candidates = accessibilityCandidates(
            focusedElement: focused,
            hitElement: hitElement
        ).map { candidate in
            SelectionProbeCandidate(
                origin: candidate.origin,
                role: candidate.role,
                probe: selectionProbe(
                    from: candidate.element,
                    sourceApplication: application,
                    releasePoint: releasePoint
                )
            )
        }
        if let best = SelectionDetection.bestCandidate(from: candidates) {
            return best.probe
        }
        return candidates.filter {
            ($0.probe.rangeLength ?? 0) > 0
                || $0.probe.rangeFingerprint != nil
                || $0.probe.boundsInQuartz != nil
        }.max { lhs, rhs in
            selectionEvidenceScore(lhs.probe) < selectionEvidenceScore(rhs.probe)
        }?.probe
    }

    private func selectionEvidenceScore(_ probe: SelectionProbe) -> Int {
        ((probe.rangeLength ?? 0) > 0 ? 4 : 0)
            + (probe.rangeFingerprint != nil ? 2 : 0)
            + (probe.boundsInQuartz != nil ? 1 : 0)
    }

    private func selectionProbe(
        from element: AXUIElement,
        sourceApplication: String?,
        releasePoint: CGPoint
    ) -> SelectionProbe {
        let text = copyAttribute(kAXSelectedTextAttribute as CFString, from: element) as? String
        let rawRangeValue = copyAttribute(
            kAXSelectedTextRangeAttribute as CFString,
            from: element
        )
        let rangeValue: AXValue? = rawRangeValue.flatMap {
            guard CFGetTypeID($0) == AXValueGetTypeID() else { return nil }
            return ($0 as! AXValue)
        }
        let range = rangeValue.flatMap(cfRange(from:))
        let bounds = rangeValue.flatMap { boundsForRange($0, element: element) }

        return SelectionProbe(
            text: text,
            sourceApplication: sourceApplication,
            focusedElementIdentity: elementIdentity(element),
            rangeLength: range.map { max(0, $0.length) },
            rangeFingerprint: range.map { "\($0.location):\($0.length)" },
            boundsInQuartz: bounds,
            releasePointInQuartz: releasePoint
        )
    }

    private func accessibilityCandidates(
        focusedElement: AXUIElement?,
        hitElement: AXUIElement?
    ) -> [AccessibilityCandidate] {
        var result: [AccessibilityCandidate] = []
        var seen: Set<String> = []

        func append(_ element: AXUIElement?, origin: SelectionProbeOrigin) {
            guard let element else { return }
            let identity = elementIdentity(element)
            guard seen.insert(identity).inserted else { return }
            result.append(AccessibilityCandidate(
                element: element,
                origin: origin,
                role: role(of: element)
            ))
        }

        append(focusedElement, origin: .focusedElement)
        append(hitElement, origin: .hitElement)

        var focusedParent = focusedElement.flatMap {
            copyElementAttribute(kAXParentAttribute as CFString, from: $0)
        }
        var hitParent = hitElement.flatMap {
            copyElementAttribute(kAXParentAttribute as CFString, from: $0)
        }
        for depth in 1...8 {
            append(focusedParent, origin: .focusedAncestor(depth: depth))
            append(hitParent, origin: .hitAncestor(depth: depth))
            focusedParent = focusedParent.flatMap {
                copyElementAttribute(kAXParentAttribute as CFString, from: $0)
            }
            hitParent = hitParent.flatMap {
                copyElementAttribute(kAXParentAttribute as CFString, from: $0)
            }
            if focusedParent == nil && hitParent == nil { break }
        }
        return result
    }

    private func element(at point: CGPoint) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            systemWide,
            Float(point.x),
            Float(point.y),
            &hit
        ) == .success else { return nil }
        return hit
    }

    private func rolePath(startingAt first: AXUIElement?) -> [String] {
        var result: [String] = []
        var current: AXUIElement? = first
        var depth = 0
        while let element = current, depth < 14 {
            if let role = copyAttribute(kAXRoleAttribute as CFString, from: element) as? String {
                result.append(role)
            }
            if let subrole = copyAttribute(kAXSubroleAttribute as CFString, from: element) as? String,
               !subrole.isEmpty {
                result.append(subrole)
            }
            current = copyElementAttribute(kAXParentAttribute as CFString, from: element)
            depth += 1
        }
        return result
    }

    private func role(of element: AXUIElement) -> String {
        copyAttribute(kAXRoleAttribute as CFString, from: element) as? String
            ?? "AXUnknown"
    }

    private func boundsForRange(_ rangeValue: AXValue, element: AXUIElement) -> CGRect? {
        var value: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgRect else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &rect), !rect.isNull, !rect.isInfinite else {
            return nil
        }
        return rect
    }

    private func cfRange(from value: AXValue) -> CFRange? {
        guard AXValueGetType(value) == .cfRange else { return nil }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(value, .cfRange, &range) else { return nil }
        return range
    }

    private func elementIdentity(_ element: AXUIElement) -> String {
        if let identifier = copyAttribute(kAXIdentifierAttribute as CFString, from: element) as? String,
           !identifier.isEmpty {
            return identifier
        }
        let role = copyAttribute(kAXRoleAttribute as CFString, from: element) as? String ?? "AXUnknown"
        return "\(role):\(CFHash(element))"
    }

    private func frontmostApplicationIdentity() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
    }

    private func copyAttribute(_ name: CFString, from element: AXUIElement) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
        return value
    }

    private func copyElementAttribute(_ name: CFString, from element: AXUIElement) -> AXUIElement? {
        guard let value = copyAttribute(name, from: element),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
