import AppKit
import ApplicationServices

// Azure 专用偏好设置：基础、权限、Azure 服务。
final class PrefTabButton: NSControl {
    let tabIndex: Int
    private let symbolName: String
    private let titleText: String
    private var hovering = false { didSet { needsDisplay = true } }
    private var trackingRef: NSTrackingArea?

    var isSelected = false { didSet { needsDisplay = true } }

    init(index: Int, symbol: String, title: String, target: AnyObject?, action: Selector?) {
        tabIndex = index
        symbolName = symbol
        titleText = title
        super.init(frame: NSRect(x: 0, y: 0, width: 82, height: 58))
        self.target = target
        self.action = action
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 82),
            heightAnchor.constraint(equalToConstant: 58)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

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
    override func mouseDown(with event: NSEvent) { sendAction(action, to: target) }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let card = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: card, xRadius: 10, yRadius: 10)
        if isSelected {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            path.fill()
            NSColor.controlAccentColor.withAlphaComponent(0.35).setStroke()
            path.lineWidth = 1
            path.stroke()
        } else if hovering {
            NSColor.labelColor.withAlphaComponent(0.05).setFill()
            path.fill()
        }

        let color = isSelected ? NSColor.controlAccentColor : NSColor.secondaryLabelColor
        if let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: titleText) {
            let config = NSImage.SymbolConfiguration(pointSize: 20, weight: isSelected ? .medium : .regular)
                .applying(.init(hierarchicalColor: color))
            let image = base.withSymbolConfiguration(config) ?? base
            image.draw(
                in: NSRect(x: (bounds.width - image.size.width) / 2, y: 26, width: image.size.width, height: image.size.height),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
        }

        let text = NSAttributedString(
            string: titleText,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: isSelected ? .medium : .regular),
                .foregroundColor: color
            ]
        )
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: 7))
    }
}

final class SettingsController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var tabButtons: [PrefTabButton] = []
    private var tabViews: [NSView] = []
    private let contentContainer = NSView()
    private var currentTabIndex = 0

    private let launchAtLoginCheck = NSButton(checkboxWithTitle: "在开机时启动", target: nil, action: nil)
    private let azureSummaryLabel = NSTextField(labelWithString: "")

    private let axStatusLabel = NSTextField(labelWithString: "")
    private let scrStatusLabel = NSTextField(labelWithString: "")

    private let translatorEndpointField = NSTextField()
    private let translatorKeyField = NSSecureTextField()
    private let translatorRegionField = NSTextField()
    private let translatorProbeButton = NSButton(title: "测试连接", target: nil, action: nil)
    private let translatorProbeStatus = NSTextField(labelWithString: "")

    private let gptEndpointField = NSTextField()
    private let gptKeyField = NSSecureTextField()
    private let gptDeploymentField = NSTextField()
    private let gptVisionCheck = NSButton(checkboxWithTitle: "支持截图/图片理解", target: nil, action: nil)
    private let gptProbeButton = NSButton(title: "测试连接", target: nil, action: nil)
    private let gptProbeStatus = NSTextField(labelWithString: "")

    private var translatorProbeGeneration = 0
    private var gptProbeGeneration = 0

    var windowObject: NSWindow? { window }

    func show(tab: Int? = nil) {
        if window == nil { build() }
        loadFields()
        launchAtLoginCheck.state = LaunchAtLogin.isEnabled() ? .on : .off
        refreshPermissions()
        selectTab(tab ?? currentTabIndex)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.center()
    }

    func selectTab(_ index: Int) {
        guard index >= 0, index < tabViews.count else { return }
        currentTabIndex = index
        for (i, button) in tabButtons.enumerated() { button.isSelected = i == index }
        for (i, view) in tabViews.enumerated() { view.isHidden = i != index }
        refreshPermissions()
    }

    private func build() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 555),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Glint 设置"
        win.isReleasedWhenClosed = false
        win.hidesOnDeactivate = false
        win.level = .floating
        win.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        win.delegate = self

        let basic = PrefTabButton(index: 0, symbol: "gearshape", title: "基础", target: self, action: #selector(onTabClicked(_:)))
        let permissions = PrefTabButton(index: 1, symbol: "checkmark.shield", title: "权限", target: self, action: #selector(onTabClicked(_:)))
        let azure = PrefTabButton(index: 2, symbol: "cloud", title: "Azure", target: self, action: #selector(onTabClicked(_:)))
        tabButtons = [basic, permissions, azure]

        let tabBar = NSStackView(views: tabButtons)
        tabBar.orientation = .horizontal
        tabBar.spacing = 18
        tabBar.alignment = .centerY
        tabBar.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.alphaValue = 0.45
        separator.translatesAutoresizingMaskIntoConstraints = false

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        tabViews = [buildBasicTab(), buildPermissionsTab(), buildAzureTab()]
        for view in tabViews {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentContainer.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
                view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
                view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor)
            ])
        }

        let content = NSView()
        content.addSubview(tabBar)
        content.addSubview(separator)
        content.addSubview(contentContainer)
        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            tabBar.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            separator.topAnchor.constraint(equalTo: tabBar.bottomAnchor, constant: 10),
            separator.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            separator.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            contentContainer.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 6),
            contentContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        win.contentView = content
        window = win
    }

    @objc private func onTabClicked(_ sender: PrefTabButton) { selectTab(sender.tabIndex) }

    private func buildBasicTab() -> NSView {
        launchAtLoginCheck.target = self
        launchAtLoginCheck.action = #selector(onLaunchAtLoginToggled)
        launchAtLoginCheck.font = .systemFont(ofSize: 13)

        azureSummaryLabel.font = .systemFont(ofSize: 13, weight: .medium)
        let configure = NSButton(title: "配置 Azure…", target: self, action: #selector(onGoToAzureTab))
        configure.bezelStyle = .rounded
        configure.controlSize = .small
        let azureRow = NSStackView(views: [azureSummaryLabel, configure])
        azureRow.orientation = .horizontal
        azureRow.spacing = 10

        let hotkey = NSTextField(wrappingLabelWithString: "⌃⌥E（Control + Option + E）框选截图，划词后可直接翻译或提问。")
        hotkey.font = .systemFont(ofSize: 13)
        hotkey.preferredMaxLayoutWidth = 390

        return pageStack([
            prefRow(label: "启动", content: launchAtLoginCheck),
            prefRow(label: "快捷键", content: hotkey, alignTop: true),
            prefRow(label: "Azure", content: azureRow)
        ], top: 34)
    }

    private func buildPermissionsTab() -> NSView {
        axStatusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        scrStatusLabel.font = .systemFont(ofSize: 13, weight: .medium)

        let axButton = NSButton(title: "打开系统设置…", target: self, action: #selector(onOpenAX))
        let screenButton = NSButton(title: "打开系统设置…", target: self, action: #selector(onOpenScreenRecording))
        let recheck = NSButton(title: "重新检测", target: self, action: #selector(onRecheckPermissions))
        for button in [axButton, screenButton, recheck] {
            button.bezelStyle = .rounded
            button.controlSize = .small
        }

        let ax = NSStackView(views: [axStatusLabel, axButton])
        ax.orientation = .horizontal; ax.spacing = 10
        let screen = NSStackView(views: [scrStatusLabel, screenButton])
        screen.orientation = .horizontal; screen.spacing = 10
        return pageStack([
            prefRow(label: "辅助功能", content: ax),
            prefRow(label: "屏幕录制", content: screen),
            prefRow(label: "状态", content: recheck)
        ], top: 34)
    }

    private func buildAzureTab() -> NSView {
        configureField(translatorEndpointField, placeholder: "https://api.cognitive.microsofttranslator.com")
        configureField(translatorKeyField, placeholder: "Translator Key")
        configureField(translatorRegionField, placeholder: "例如 eastasia；全局单服务资源可留空")
        configureField(gptEndpointField, placeholder: "https://<resource>.openai.azure.com/openai/v1")
        configureField(gptKeyField, placeholder: "Azure OpenAI Key")
        configureField(gptDeploymentField, placeholder: "Azure Deployment Name")

        configureProbeButton(translatorProbeButton, action: #selector(testTranslatorConnection))
        configureProbeButton(gptProbeButton, action: #selector(testGPTConnection))
        configureStatusLabel(translatorProbeStatus)
        configureStatusLabel(gptProbeStatus)

        let translatorActions = NSStackView(views: [translatorProbeButton, translatorProbeStatus])
        translatorActions.orientation = .horizontal; translatorActions.spacing = 10; translatorActions.alignment = .centerY
        let gptActions = NSStackView(views: [gptProbeButton, gptProbeStatus])
        gptActions.orientation = .horizontal; gptActions.spacing = 10; gptActions.alignment = .centerY

        let translatorSection = section(title: "Azure Text Translation", rows: [
            fieldRow("Endpoint", translatorEndpointField),
            fieldRow("API Key", translatorKeyField),
            fieldRow("Region", translatorRegionField),
            indentRow(translatorActions)
        ])
        let gptSection = section(title: "Azure GPT（OpenAI v1）", rows: [
            fieldRow("Endpoint", gptEndpointField),
            fieldRow("API Key", gptKeyField),
            fieldRow("部署名称", gptDeploymentField),
            indentRow(gptVisionCheck),
            indentRow(gptActions)
        ])

        let note = NSTextField(wrappingLabelWithString: "“测试连接”使用当前输入值发起最小真实请求，不会自动保存，可能产生极少量 Azure 用量。")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = 530

        let save = NSButton(title: "保存", target: self, action: #selector(saveSettings))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        let close = NSButton(title: "关闭", target: self, action: #selector(closeWin))
        close.bezelStyle = .rounded
        let bottom = NSStackView(views: [hSpacer(), close, save])
        bottom.orientation = .horizontal; bottom.spacing = 8

        let stack = NSStackView(views: [translatorSection, gptSection, note, hSpacer(), separator(), bottom])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 28, bottom: 14, right: 28)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            translatorSection.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -56),
            gptSection.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -56),
            bottom.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -56)
        ])
        return container
    }

    private func configureField(_ field: NSTextField, placeholder: String) {
        field.font = .systemFont(ofSize: 12)
        field.placeholderString = placeholder
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 390).isActive = true
    }

    private func configureProbeButton(_ button: NSButton, action: Selector) {
        button.target = self
        button.action = action
        button.bezelStyle = .rounded
        button.controlSize = .small
    }

    private func configureStatusLabel(_ label: NSTextField) {
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 350).isActive = true
    }

    private func loadFields() {
        let config = AppConfig.shared
        translatorEndpointField.stringValue = config.translator.endpoint
        translatorKeyField.stringValue = config.translator.apiKey
        translatorRegionField.stringValue = config.translator.region
        gptEndpointField.stringValue = config.azureOpenAI.endpoint
        gptKeyField.stringValue = config.azureOpenAI.apiKey
        gptDeploymentField.stringValue = config.azureOpenAI.deploymentName
        gptVisionCheck.state = config.azureOpenAI.supportsVision ? .on : .off
        translatorProbeStatus.stringValue = ""
        gptProbeStatus.stringValue = ""
    }

    private func formTranslatorConfig() -> AzureTranslatorConfig {
        AzureTranslatorConfig(
            endpoint: translatorEndpointField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: translatorKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            region: translatorRegionField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func formGPTConfig() -> AzureOpenAIConfig {
        AzureOpenAIConfig(
            endpoint: gptEndpointField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: gptKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            deploymentName: gptDeploymentField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            supportsVision: gptVisionCheck.state == .on
        )
    }

    @objc private func testTranslatorConnection() {
        let config = formTranslatorConfig()
        guard let request = config.buildProbeRequest() else {
            setProbeResult(translatorProbeStatus, button: translatorProbeButton, message: "请检查 Endpoint 和 Key", success: false)
            return
        }
        translatorProbeGeneration += 1
        let generation = translatorProbeGeneration
        beginProbe(translatorProbeStatus, button: translatorProbeButton)
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self, generation == self.translatorProbeGeneration else { return }
                if let error {
                    self.setProbeResult(self.translatorProbeStatus, button: self.translatorProbeButton, message: "网络错误：\(error.localizedDescription)", success: false)
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200..<300).contains(status), let data, config.parseResponse(data: data) != nil {
                    self.setProbeResult(self.translatorProbeStatus, button: self.translatorProbeButton, message: "✓ Translator 连接成功", success: true)
                } else {
                    self.setProbeResult(self.translatorProbeStatus, button: self.translatorProbeButton, message: config.parseError(statusCode: status, data: data), success: false)
                }
            }
        }.resume()
    }

    @objc private func testGPTConnection() {
        let config = formGPTConfig()
        guard let request = config.buildProbeRequest() else {
            setProbeResult(gptProbeStatus, button: gptProbeButton, message: "请检查 Endpoint、Key 和部署名称", success: false)
            return
        }
        gptProbeGeneration += 1
        let generation = gptProbeGeneration
        beginProbe(gptProbeStatus, button: gptProbeButton)
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self, generation == self.gptProbeGeneration else { return }
                if let error {
                    self.setProbeResult(self.gptProbeStatus, button: self.gptProbeButton, message: "网络错误：\(error.localizedDescription)", success: false)
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200..<300).contains(status), let data, config.parseResponse(data: data) != nil {
                    self.setProbeResult(self.gptProbeStatus, button: self.gptProbeButton, message: "✓ Azure GPT 连接成功", success: true)
                } else {
                    self.setProbeResult(self.gptProbeStatus, button: self.gptProbeButton, message: config.parseError(statusCode: status, data: data), success: false)
                }
            }
        }.resume()
    }

    private func beginProbe(_ label: NSTextField, button: NSButton) {
        button.isEnabled = false
        label.textColor = .secondaryLabelColor
        label.stringValue = "正在测试…"
    }

    private func setProbeResult(_ label: NSTextField, button: NSButton, message: String, success: Bool) {
        button.isEnabled = true
        label.textColor = success ? .systemGreen : .systemRed
        label.stringValue = message
        label.toolTip = message
    }

    @objc private func saveSettings() {
        let translator = formTranslatorConfig()
        let gpt = formGPTConfig()
        guard AppConfig.shared.setAzureServices(translator: translator, azureOpenAI: gpt) else {
            alert("保存失败：无法写入 ~/.config/glint/config.json，请检查目录权限或磁盘空间。")
            return
        }
        gAppDelegate?.refreshMenu()
        window?.close()
    }

    func refreshPermissions() {
        let axOK = AXIsProcessTrusted()
        axStatusLabel.stringValue = axOK ? "✓ 已授权" : "⚠️ 未授权"
        axStatusLabel.textColor = axOK ? .systemGreen : .systemOrange
        let screenOK = RegionCapture.hasScreenRecordingPermission()
        scrStatusLabel.stringValue = screenOK ? "✓ 已授权" : "⚠️ 未授权"
        scrStatusLabel.textColor = screenOK ? .systemGreen : .systemOrange

        let translatorReady = !AppConfig.shared.translator.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let deployment = AppConfig.shared.azureOpenAI.deploymentName.trimmingCharacters(in: .whitespacesAndNewlines)
        let translatorText = translatorReady ? "Translator 已配置" : "Translator 未配置"
        let gptText = deployment.isEmpty ? "GPT 未配置" : "GPT：\(deployment)"
        azureSummaryLabel.stringValue = "\(translatorText) · \(gptText)"
    }

    @objc private func onLaunchAtLoginToggled() {
        let wanted = launchAtLoginCheck.state == .on
        if !LaunchAtLogin.setEnabled(wanted) {
            launchAtLoginCheck.state = LaunchAtLogin.isEnabled() ? .on : .off
            alert("无法修改开机启动配置，请检查 ~/Library/LaunchAgents 目录权限。")
        }
    }

    @objc private func onOpenAX() { gAppDelegate?.openAXSettings() }
    @objc private func onOpenScreenRecording() { gAppDelegate?.openScreenRecordingSettings() }
    @objc private func onRecheckPermissions() { gAppDelegate?.recheck(); refreshPermissions() }
    @objc private func onGoToAzureTab() { selectTab(2) }
    @objc private func closeWin() { window?.close() }

    func windowDidBecomeKey(_ notification: Notification) { refreshPermissions() }
    func windowWillClose(_ notification: Notification) {
        translatorProbeGeneration += 1
        gptProbeGeneration += 1
        translatorProbeButton.isEnabled = true
        gptProbeButton.isEnabled = true
    }

    private func pageStack(_ rows: [NSView], top: CGFloat) -> NSView {
        let spacer = hSpacer()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        let stack = NSStackView(views: rows + [spacer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 24
        stack.edgeInsets = NSEdgeInsets(top: top, left: 54, bottom: 24, right: 54)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
        return container
    }

    private func section(title: String, rows: [NSView]) -> NSStackView {
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        let stack = NSStackView(views: [heading] + rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        return stack
    }

    private func prefRow(label: String, content: NSView, alignTop: Bool = false) -> NSStackView {
        let title = NSTextField(labelWithString: label)
        title.font = .systemFont(ofSize: 13)
        title.textColor = .secondaryLabelColor
        title.alignment = .right
        title.translatesAutoresizingMaskIntoConstraints = false
        title.widthAnchor.constraint(equalToConstant: 88).isActive = true
        let row = NSStackView(views: [title, content])
        row.orientation = .horizontal
        row.spacing = 14
        row.alignment = alignTop ? .top : .centerY
        return row
    }

    private func fieldRow(_ label: String, _ field: NSView) -> NSStackView {
        let title = NSTextField(labelWithString: label)
        title.font = .systemFont(ofSize: 12)
        title.textColor = .secondaryLabelColor
        title.alignment = .right
        title.translatesAutoresizingMaskIntoConstraints = false
        title.widthAnchor.constraint(equalToConstant: 86).isActive = true
        let row = NSStackView(views: [title, field])
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY
        return row
    }

    private func indentRow(_ view: NSView) -> NSStackView {
        let pad = NSView()
        pad.translatesAutoresizingMaskIntoConstraints = false
        pad.widthAnchor.constraint(equalToConstant: 96).isActive = true
        let row = NSStackView(views: [pad, view])
        row.orientation = .horizontal
        row.alignment = .centerY
        return row
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.alphaValue = 0.45
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 530).isActive = true
        return box
    }

    private func hSpacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    private func alert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "好的")
        alert.runModal()
    }
}
