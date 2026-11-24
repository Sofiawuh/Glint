import AppKit
import ApplicationServices

final class AccessibilitySelectionReader {
    func currentSelectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        guard var current = copyElementAttribute(
            kAXFocusedUIElementAttribute as CFString,
            from: systemWide
        ) else { return nil }

        for _ in 0...8 {
            if let text = copyAttribute(
                kAXSelectedTextAttribute as CFString,
                from: current
            ) as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
            guard let parent = copyElementAttribute(
                kAXParentAttribute as CFString,
                from: current
            ) else { break }
            current = parent
        }
        return nil
    }

    private func copyAttribute(
        _ name: CFString,
        from element: AXUIElement
    ) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else {
            return nil
        }
        return value
    }

    private func copyElementAttribute(
        _ name: CFString,
        from element: AXUIElement
    ) -> AXUIElement? {
        guard let value = copyAttribute(name, from: element),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
