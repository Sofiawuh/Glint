import AppKit
import Carbon

final class HotKeyRecorderControl: NSControl {
    var onRecordingStateChanged: ((Bool) -> Void)?
    var onDecision: ((ScreenshotHotKey.RecordingDecision) -> Void)?

    private(set) var isRecording = false
    private var hotKey: ScreenshotHotKey = .default
    private var hovering = false { didSet { needsDisplay = true } }
    private var trackingRef: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 142, height: 30) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityRole(.button)
        setAccessibilityLabel("截图快捷键")
        toolTip = "点击后直接按新的快捷键"
    }

    required init?(coder: NSCoder) { fatalError() }

    func setPurposeLabel(_ label: String) {
        setAccessibilityLabel(label)
        toolTip = "点击后直接录制\(label)"
    }

    func setHotKey(_ value: ScreenshotHotKey) {
        hotKey = value
        if !isRecording { needsDisplay = true }
        setAccessibilityValue(value.displayString)
    }

    func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        needsDisplay = true
        window?.makeFirstResponder(self)
        onRecordingStateChanged?(true)
    }

    func finishRecording(with value: ScreenshotHotKey) {
        hotKey = value
        stopRecording()
        setAccessibilityValue(value.displayString)
    }

    func cancelRecording() {
        stopRecording()
    }

    func receiveCurrentHotKey(_ value: ScreenshotHotKey) {
        guard isRecording else { return }
        onDecision?(.commit(value))
    }

    override func mouseDown(with event: NSEvent) {
        beginRecording()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        let decision = ScreenshotHotKey.recordingDecision(
            keyCode: UInt32(event.keyCode),
            modifiers: Self.carbonModifiers(from: event.modifierFlags)
        )
        onDecision?(decision)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }
        onDecision?(.waitForKey)
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned && isRecording { cancelRecording() }
        return resigned
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingRef { removeTrackingArea(trackingRef) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingRef = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)

        let fill: NSColor
        if isRecording {
            fill = .controlAccentColor.withAlphaComponent(0.12)
        } else if hovering {
            fill = .controlBackgroundColor.blended(withFraction: 0.08, of: .labelColor) ?? .controlBackgroundColor
        } else {
            fill = .controlBackgroundColor
        }
        fill.setFill()
        path.fill()

        let stroke = isRecording ? NSColor.controlAccentColor : NSColor.separatorColor
        stroke.setStroke()
        path.lineWidth = isRecording ? 1.5 : 1
        path.stroke()

        if window?.firstResponder === self {
            NSGraphicsContext.saveGraphicsState()
            NSFocusRingPlacement.only.set()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        let text = isRecording ? "请按快捷键…" : hotKey.displayString
        let color: NSColor = isRecording ? .controlAccentColor : .labelColor
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: isRecording ? .medium : .regular),
            .foregroundColor: color
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let size = attributed.size()
        attributed.draw(at: NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        ))
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        needsDisplay = true
        onRecordingStateChanged?(false)
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }
}
