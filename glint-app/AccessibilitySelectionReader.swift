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
    func capturePress(at quartzPoint: CGPoint) -> SelectionPressContext {
        let roles = rolePath(at: quartzPoint)
        return SelectionPressContext(
            before: focusedSelectionProbe(releasePoint: quartzPoint),
            pressedRolePath: roles
        )
    }

    func evaluateRelease(
        from press: SelectionPressContext?,
        at quartzPoint: CGPoint,
        previousProbe: SelectionProbe?
    ) -> SelectionReadEvaluation {
        let releasedRoles = rolePath(at: quartzPoint)
        let after = focusedSelectionProbe(releasePoint: quartzPoint)
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
            before: nil,
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
                before: previousProbe,
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
        focusedSelectionProbe(releasePoint: .zero)
    }

    private func focusedSelectionProbe(releasePoint: CGPoint) -> SelectionProbe? {
        let systemWide = AXUIElementCreateSystemWide()
        guard let focused = copyElementAttribute(
            kAXFocusedUIElementAttribute as CFString,
            from: systemWide
        ) else { return nil }

        let text = copyAttribute(kAXSelectedTextAttribute as CFString, from: focused) as? String
        let rawRangeValue = copyAttribute(
            kAXSelectedTextRangeAttribute as CFString,
            from: focused
        )
        let rangeValue: AXValue? = rawRangeValue.flatMap {
            guard CFGetTypeID($0) == AXValueGetTypeID() else { return nil }
            return ($0 as! AXValue)
        }
        let range = rangeValue.flatMap(cfRange(from:))
        let bounds = rangeValue.flatMap { boundsForRange($0, element: focused) }

        return SelectionProbe(
            text: text,
            sourceApplication: frontmostApplicationIdentity(),
            focusedElementIdentity: elementIdentity(focused),
            rangeLength: range.map { max(0, $0.length) },
            rangeFingerprint: range.map { "\($0.location):\($0.length)" },
            boundsInQuartz: bounds,
            releasePointInQuartz: releasePoint
        )
    }

    private func rolePath(at point: CGPoint) -> [String] {
        let systemWide = AXUIElementCreateSystemWide()
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            systemWide,
            Float(point.x),
            Float(point.y),
            &hit
        ) == .success, let first = hit else { return [] }

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
