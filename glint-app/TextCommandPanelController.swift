import AppKit

private final class TextCommandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

private final class TextCommandSurfaceView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        ClaudeTheme.paperBg.setFill()
        path.fill()
        ClaudeTheme.pillBorder.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

private final class TextCommandHintView: NSView {
    let message: String

    init(frame frameRect: NSRect, message: String) {
        self.message = message
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
        ClaudeTheme.paperBg.setFill()
        path.fill()
        ClaudeTheme.pillBorder.setStroke()
        path.lineWidth = 1
        path.stroke()

        let attributed = NSAttributedString(
            string: message,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: ClaudeTheme.inkBody
            ]
        )
        let size = attributed.size()
        attributed.draw(at: NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        ))
    }
}

final class TextCommandPanelController: NSObject {
    private let actionSize = NSSize(width: 168, height: 40)
    private let hintSize = NSSize(width: 224, height: 36)
    private let onTranslate: (String, NSPoint) -> Void
    private let onAsk: (String, NSPoint) -> Void

    private var lifecycle = TextCommandPanelLifecycle()
    private var panel: TextCommandPanel?
    private var hintDismissWorkItem: DispatchWorkItem?

    init(
        onTranslate: @escaping (String, NSPoint) -> Void,
        onAsk: @escaping (String, NSPoint) -> Void
    ) {
        self.onTranslate = onTranslate
        self.onAsk = onAsk
        super.init()
    }

    var isVisible: Bool { panel?.isVisible ?? false }
    var frame: NSRect? { panel?.frame }

    func beginRequest() -> TextCommandPanelRequest {
        cancelHintDismissal()
        panel?.orderOut(nil)
        return lifecycle.beginRequest()
    }

    @discardableResult
    func showActions(
        text: String,
        request: TextCommandPanelRequest,
        mouseLocation: NSPoint
    ) -> Bool {
        guard lifecycle.completeRequest(
            request,
            text: text,
            mouseLocation: mouseLocation
        ) else { return false }

        cancelHintDismissal()
        guard let frame = frameNearMouse(mouseLocation, size: actionSize) else {
            lifecycle.hide()
            return false
        }
        let panel = ensurePanel(frame: frame)
        panel.setFrame(frame, display: true)
        panel.hasShadow = true

        let root = TextCommandSurfaceView(
            frame: NSRect(origin: .zero, size: actionSize)
        )
        let translate = ActionPillButton(
            frame: NSRect(x: 4, y: 4, width: 76, height: 32),
            kind: .translate,
            labelText: "翻译"
        )
        translate.target = self
        translate.action = #selector(translateClicked)
        translate.setAccessibilityLabel("翻译选中文字")
        root.addSubview(translate)

        let ask = ActionPillButton(
            frame: NSRect(x: 88, y: 4, width: 76, height: 32),
            kind: .ask,
            labelText: "提问"
        )
        ask.target = self
        ask.action = #selector(askClicked)
        ask.setAccessibilityLabel("用选中文字提问")
        root.addSubview(ask)

        panel.contentView = root
        panel.orderFrontRegardless()
        logLine("TEXT_COMMAND_PANEL show frame=\(NSStringFromRect(frame))")
        return true
    }

    @discardableResult
    func showNoTextHint(
        request: TextCommandPanelRequest,
        mouseLocation: NSPoint
    ) -> Bool {
        guard lifecycle.completeWithoutText(request) else { return false }
        cancelHintDismissal()
        guard let frame = frameNearMouse(mouseLocation, size: hintSize) else {
            lifecycle.hide()
            return false
        }
        let panel = ensurePanel(frame: frame)
        panel.setFrame(frame, display: true)
        panel.hasShadow = true
        panel.contentView = TextCommandHintView(
            frame: NSRect(origin: .zero, size: hintSize),
            message: "没有读取到文字，请先选中文字"
        )
        panel.orderFrontRegardless()

        let item = DispatchWorkItem { [weak self, weak panel] in
            guard self?.panel === panel else { return }
            panel?.orderOut(nil)
        }
        hintDismissWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: item)
        logLine("TEXT_COMMAND_PANEL no-text hint frame=\(NSStringFromRect(frame))")
        return true
    }

    @discardableResult
    func handleMouseDown(at point: NSPoint) -> Bool {
        guard isVisible else { return false }
        if panel?.frame.contains(point) == true { return true }
        cancelHintDismissal()
        lifecycle.handleOutsideClick()
        panel?.orderOut(nil)
        return false
    }

    func escapePressed() {
        guard isVisible else { return }
        cancelHintDismissal()
        lifecycle.handleEscape()
        panel?.orderOut(nil)
    }

    func hide() {
        cancelHintDismissal()
        lifecycle.hide()
        panel?.orderOut(nil)
    }

    func runSmokeTest(outputDirectory: String, completion: @escaping (Bool) -> Void) {
        let request = beginRequest()
        guard let visibleFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame else {
            completion(false)
            return
        }
        let pointer = NSPoint(x: visibleFrame.midX, y: visibleFrame.midY)
        guard showActions(
            text: "用于验证文字命令面板的示例文字",
            request: request,
            mouseLocation: pointer
        ) else {
            completion(false)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self,
                  let content = self.panel?.contentView,
                  let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds),
                  self.panel?.canBecomeKey == false else {
                completion(false)
                return
            }
            content.cacheDisplay(in: content.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else {
                completion(false)
                return
            }
            let path = URL(fileURLWithPath: outputDirectory)
                .appendingPathComponent("text-command-panel.png")
            do {
                try FileManager.default.createDirectory(
                    at: path.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: path, options: .atomic)
                self.hide()
                completion(true)
            } catch {
                logLine("UITEST text_command_panel snapshot failed=\(error.localizedDescription)")
                completion(false)
            }
        }
    }

    @objc private func translateClicked() {
        submit(.translate)
    }

    @objc private func askClicked() {
        submit(.ask)
    }

    private func submit(_ action: TextCommandPanelAction) {
        let anchor = panel.map {
            NSPoint(x: $0.frame.minX, y: $0.frame.maxY)
        } ?? NSEvent.mouseLocation
        guard let submission = lifecycle.submit(action) else { return }
        cancelHintDismissal()
        panel?.orderOut(nil)
        switch submission.action {
        case .translate:
            onTranslate(submission.text, anchor)
        case .ask:
            onAsk(submission.text, anchor)
        }
    }

    private func frameNearMouse(_ point: NSPoint, size: NSSize) -> NSRect? {
        let screens = NSScreen.screens
        guard let visibleFrame = textCommandPanelVisibleFrame(
            mouseLocation: point,
            availableVisibleFrames: screens.map(\.visibleFrame),
            mainVisibleFrame: NSScreen.main?.visibleFrame
        ) else { return nil }
        return textCommandPanelFrame(
            mouseLocation: point,
            visibleFrame: visibleFrame,
            panelSize: size
        )
    }

    private func ensurePanel(frame: NSRect) -> TextCommandPanel {
        if let panel { return panel }
        let created = TextCommandPanel(
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

    private func cancelHintDismissal() {
        hintDismissWorkItem?.cancel()
        hintDismissWorkItem = nil
    }
}
