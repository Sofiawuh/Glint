import AppKit

private final class SelectionEntryPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

private final class SelectionMarkerView: NSView {
    private let style: SelectionEntryMarkerStyle
    private let markerFrame: NSRect

    init(
        frame frameRect: NSRect,
        style: SelectionEntryMarkerStyle,
        markerFrame: NSRect
    ) {
        self.style = style
        self.markerFrame = markerFrame
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(style.shadowOpacity)
        shadow.shadowBlurRadius = style.shadowBlurRadius
        shadow.shadowOffset = style.shadowOffset
        shadow.set()

        let bg = NSBezierPath(
            roundedRect: markerFrame,
            xRadius: style.cornerRadius,
            yRadius: style.cornerRadius
        )
        ClaudeTheme.terracotta.setFill()
        bg.fill()

        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.72).setStroke()
        bg.lineWidth = style.borderWidth
        bg.stroke()
    }
}

private final class SelectionActionsView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10)
        ClaudeTheme.paperBg.setFill()
        path.fill()
        ClaudeTheme.pillBorder.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

final class SelectionEntryController: NSObject {
    private let markerStyle = SelectionEntryMarkerStyle.default
    private let expandedSize = NSSize(width: 162, height: 38)
    private let onTranslate: (SelectionSnapshot, NSPoint) -> Void
    private let onAsk: (SelectionSnapshot, NSPoint) -> Void

    private var lifecycle = SelectionEntryLifecycle()
    private var panel: SelectionEntryPanel?
    private var layout: SelectionEntryLayout?
    private var timerWorkItem: DispatchWorkItem?

    init(
        onTranslate: @escaping (SelectionSnapshot, NSPoint) -> Void,
        onAsk: @escaping (SelectionSnapshot, NSPoint) -> Void
    ) {
        self.onTranslate = onTranslate
        self.onAsk = onAsk
        super.init()
    }

    var isVisible: Bool { panel?.isVisible ?? false }
    var frame: NSRect? { panel?.frame }

    func show(snapshot: SelectionSnapshot) {
        let primaryHeight = primaryScreenHeight()
        let releasePoint = appKitPoint(
            fromQuartz: snapshot.releasePointInQuartz,
            primaryScreenHeight: primaryHeight
        )
        let selectionBounds = snapshot.boundsInQuartz.map {
            appKitRect(fromQuartz: $0, primaryScreenHeight: primaryHeight)
        } ?? NSRect(origin: releasePoint, size: .zero)
        let screenPoint = selectionBounds.isEmpty
            ? releasePoint
            : NSPoint(x: selectionBounds.midX, y: selectionBounds.midY)
        let visibleFrame = screenFor(point: screenPoint).visibleFrame
        let nextLayout = selectionEntryLayout(
            selectionBounds: selectionBounds,
            releasePoint: releasePoint,
            visible: visibleFrame,
            markerSize: markerStyle.visibleSize,
            expandedSize: expandedSize
        )
        layout = nextLayout
        cancelTimer()
        lifecycle.present(
            snapshot,
            pointerInsideContinuousRegion: nextLayout.markerHitFrame.contains(releasePoint)
        )
        renderCurrentPhase()
        logLine("SELECTION_ENTRY marker range=\(snapshot.rangeFingerprint != nil) bounds=\(snapshot.boundsInQuartz != nil) frame=\(NSStringFromRect(nextLayout.markerFrame))")
    }

    func pointerMoved(to point: NSPoint) {
        guard let layout, lifecycle.phase != .hidden else { return }
        let inside: Bool
        switch lifecycle.phase {
        case .expanded, .collapsePending:
            inside = layout.continuousHitRegion.contains(point)
        default:
            inside = layout.markerHitFrame.contains(point)
        }
        let before = lifecycle.phase
        let request = lifecycle.pointerMoved(isInsideContinuousRegion: inside)
        if lifecycle.phase != before { renderCurrentPhase() }
        if let request { schedule(request) }
    }

    @discardableResult
    func handleMouseDown(at point: NSPoint) -> Bool {
        guard lifecycle.phase != .hidden else { return false }
        let inside = panel?.frame.contains(point) ?? false
        if inside { return true }
        cancelTimer()
        lifecycle.outsideMouseDown()
        renderCurrentPhase()
        return false
    }

    func escapePressed() {
        guard lifecycle.phase != .hidden else { return }
        cancelTimer()
        lifecycle.escapePressed()
        renderCurrentPhase()
    }

    func selectionInvalidated() {
        guard lifecycle.phase != .hidden else { return }
        cancelTimer()
        lifecycle.selectionInvalidated()
        renderCurrentPhase()
    }

    func invalidateClipboardOnlySelection() {
        guard lifecycle.currentSnapshot?.evidenceSource == .clipboardOnly else { return }
        selectionInvalidated()
    }

    func revalidateSource(_ currentSource: SelectionSourceIdentity) {
        guard let snapshot = lifecycle.currentSnapshot,
              !SelectionSourceRevalidation.isValid(
                snapshot: snapshot,
                currentSource: currentSource
              ) else { return }
        selectionInvalidated()
    }

    func beginKeyboardRevalidation() -> SelectionEntryKeyboardRevalidationRequest? {
        SelectionEntryKeyboardHandler.beginRevalidation(for: lifecycle)
    }

    func completeKeyboardRevalidation(
        _ request: SelectionEntryKeyboardRevalidationRequest,
        currentProbe: SelectionProbe?
    ) {
        let isValid = SelectionSourceRevalidation.isValid(
            snapshot: request.snapshot,
            currentProbe: currentProbe
        )
        let previousPhase = lifecycle.phase
        let accepted = SelectionEntryKeyboardHandler.completeRevalidation(
            request,
            sourceAndSelectionAreValid: isValid,
            lifecycle: &lifecycle
        )
        guard accepted, lifecycle.phase != previousPhase else { return }
        cancelTimer()
        renderCurrentPhase()
    }

    func hide() {
        cancelTimer()
        lifecycle.hide()
        renderCurrentPhase()
    }

    func runSmokeTest(outputDirectory: String, completion: @escaping (Bool) -> Void) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let selectionAppKit = NSRect(
            x: screen.visibleFrame.midX - 120,
            y: screen.visibleFrame.midY + 40,
            width: 210,
            height: 42
        )
        let primaryHeight = primaryScreenHeight()
        let selectionQuartz = CGRect(
            x: selectionAppKit.minX,
            y: primaryHeight - selectionAppKit.maxY,
            width: selectionAppKit.width,
            height: selectionAppKit.height
        )
        let releaseQuartz = CGPoint(
            x: selectionQuartz.maxX,
            y: selectionQuartz.maxY
        )
        let snapshot = SelectionSnapshot(
            text: "用于验证选区悬停入口的示例文字",
            sourceApplication: "com.example.glint-uitest",
            focusedElementIdentity: "glint-uitest-selection",
            rangeFingerprint: "10:16",
            boundsInQuartz: selectionQuartz,
            releasePointInQuartz: releaseQuartz
        )
        show(snapshot: snapshot)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, let layout = self.layout else {
                completion(false)
                return
            }
            let markerPath = URL(fileURLWithPath: outputDirectory)
                .appendingPathComponent("selection-entry-marker.png").path
            let markerOK = self.writePanelSnapshot(to: markerPath)
            self.pointerMoved(to: NSPoint(x: layout.markerFrame.minX - 30, y: layout.markerFrame.midY))
            self.pointerMoved(to: NSPoint(x: layout.markerFrame.midX, y: layout.markerFrame.midY))

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self else {
                    completion(false)
                    return
                }
                let expandedPath = URL(fileURLWithPath: outputDirectory)
                    .appendingPathComponent("selection-entry-expanded.png").path
                let expandedOK = self.lifecycle.phase == .expanded
                    && self.writePanelSnapshot(to: expandedPath)
                    && self.panel?.canBecomeKey == false
                logLine("UITEST selection_entry marker=\(markerOK) expanded=\(expandedOK) phase=\(self.lifecycle.phase)")
                self.hide()
                completion(markerOK && expandedOK)
            }
        }
    }

    @objc private func translateClicked() {
        submit(.translate)
    }

    @objc private func askClicked() {
        submit(.ask)
    }

    private func submit(_ action: SelectionEntryAction) {
        let anchor = layout.map { NSPoint(x: $0.expandedFrame.minX, y: $0.expandedFrame.maxY) }
            ?? NSEvent.mouseLocation
        guard let submission = lifecycle.submit(action) else { return }
        cancelTimer()
        renderCurrentPhase()
        switch submission.action {
        case .translate:
            onTranslate(submission.snapshot, anchor)
        case .ask:
            onAsk(submission.snapshot, anchor)
        }
    }

    private func schedule(_ request: SelectionEntryTimerRequest) {
        cancelTimer()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let before = self.lifecycle.phase
            self.lifecycle.timerFired(request.token)
            if self.lifecycle.phase != before { self.renderCurrentPhase() }
        }
        timerWorkItem = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(request.delayMilliseconds),
            execute: item
        )
    }

    private func cancelTimer() {
        timerWorkItem?.cancel()
        timerWorkItem = nil
    }

    private func renderCurrentPhase() {
        guard let layout else {
            panel?.orderOut(nil)
            return
        }
        switch lifecycle.phase {
        case .hidden:
            panel?.orderOut(nil)
        case .marker, .hoverPending:
            showMarker(layout: layout)
        case .expanded, .collapsePending:
            showActions(frame: layout.expandedFrame)
        }
    }

    private func showMarker(layout: SelectionEntryLayout) {
        let frame = layout.markerHitFrame
        let panel = ensurePanel(frame: frame)
        panel.hasShadow = false
        panel.setFrame(frame, display: true)
        let localMarker = layout.markerFrame.offsetBy(
            dx: -frame.minX,
            dy: -frame.minY
        )
        panel.contentView = SelectionMarkerView(
            frame: NSRect(origin: .zero, size: frame.size),
            style: markerStyle,
            markerFrame: localMarker
        )
        panel.orderFrontRegardless()
    }

    private func showActions(frame: NSRect) {
        let panel = ensurePanel(frame: frame)
        panel.hasShadow = true
        panel.setFrame(frame, display: true)
        let root = SelectionActionsView(frame: NSRect(origin: .zero, size: frame.size))
        let pad: CGFloat = 4
        let gap: CGFloat = 2
        let buttonWidth: CGFloat = 76
        let buttonHeight: CGFloat = 30

        let translate = ActionPillButton(
            frame: NSRect(x: pad, y: pad, width: buttonWidth, height: buttonHeight),
            kind: .translate,
            labelText: "翻译"
        )
        translate.target = self
        translate.action = #selector(translateClicked)
        root.addSubview(translate)

        let ask = ActionPillButton(
            frame: NSRect(x: pad + buttonWidth + gap, y: pad, width: buttonWidth, height: buttonHeight),
            kind: .ask,
            labelText: "提问"
        )
        ask.target = self
        ask.action = #selector(askClicked)
        root.addSubview(ask)

        panel.contentView = root
        panel.orderFrontRegardless()
    }

    private func ensurePanel(frame: NSRect) -> SelectionEntryPanel {
        if let panel { return panel }
        let created = SelectionEntryPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        created.appearance = NSAppearance(named: .aqua)
        created.isFloatingPanel = true
        created.level = .floating
        created.hidesOnDeactivate = false
        created.becomesKeyOnlyIfNeeded = true
        created.isMovable = false
        created.isOpaque = false
        created.backgroundColor = .clear
        created.animationBehavior = .none
        created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel = created
        return created
    }

    private func screenFor(point: NSPoint) -> NSScreen {
        if let exact = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            return exact
        }
        return NSScreen.screens.min {
            squaredDistance(point, to: $0.frame) < squaredDistance(point, to: $1.frame)
        } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func squaredDistance(_ point: NSPoint, to rect: NSRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }

    private func writePanelSnapshot(to path: String) -> Bool {
        guard let content = panel?.contentView,
              let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return false }
        content.cacheDisplay(in: content.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: path).deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            return true
        } catch {
            logLine("UITEST selection_entry snapshot failed=\(error.localizedDescription)")
            return false
        }
    }
}
