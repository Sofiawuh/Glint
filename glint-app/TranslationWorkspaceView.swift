import AppKit

final class TranslationWorkspaceView: NSView, NSTextViewDelegate {
    static let languageChoices: [(code: String, title: String)] = [
        ("zh-Hans", "简体中文"),
        ("zh-Hant", "繁体中文"),
        ("en", "英语"),
        ("ja", "日语"),
        ("ko", "韩语"),
        ("fr", "法语"),
        ("de", "德语"),
        ("es", "西班牙语"),
        ("ru", "俄语"),
        ("pt", "葡萄牙语")
    ]

    var onSourceChanged: ((String) -> Void)?
    var onTranslationChanged: ((String) -> Void)?
    var onTargetChanged: ((String) -> Void)?
    var onFormattingChanged: ((TranslationFormattingMode) -> Void)?
    var onRetranslate: (() -> Void)?
    var onSpeak: ((TranslationWorkbenchField) -> Void)?

    private let sourceView = NSTextView()
    private let translationView = NSTextView()
    private let sourceLanguageLabel = NSTextField(labelWithString: "自动识别")
    private let translationLanguageLabel = NSTextField(labelWithString: "译文")
    private let targetLanguagePopup = NSPopUpButton()
    private let formattingPopup = NSPopUpButton()
    private let sourceSpeakButton = NSButton()
    private let translationSpeakButton = NSButton()
    private let sourceCopyButton = NSButton()
    private let translationCopyButton = NSButton()
    private let copyAllButton = NSButton()
    private let retranslateButton = NSButton(title: "重新翻译", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()
    private var isProgrammaticChange = false
    private var isReadOnly = false
    private var isLoading = false

    var sourceText: String { sourceView.string }
    var translatedText: String { translationView.string }
    var targetLanguage: String {
        let index = max(0, targetLanguagePopup.indexOfSelectedItem)
        return Self.languageChoices[min(index, Self.languageChoices.count - 1)].code
    }
    var formattingMode: TranslationFormattingMode {
        formattingPopup.indexOfSelectedItem == 1 ? .strict : .smart
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(
        sourceText: String,
        translatedText: String,
        sourceLanguage: String,
        targetLanguage: String,
        formattingMode: TranslationFormattingMode,
        readOnly: Bool
    ) {
        isReadOnly = readOnly
        isProgrammaticChange = true
        sourceView.string = sourceText
        translationView.string = translatedText
        isProgrammaticChange = false
        sourceLanguageLabel.stringValue = Self.languageTitle(sourceLanguage, fallback: "自动识别")
        selectTarget(targetLanguage)
        formattingPopup.selectItem(at: formattingMode == .smart ? 0 : 1)
        applyReadOnlyState()
        sourceView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        translationView.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }

    func updateTexts(source: String, translation: String, sourceLanguage: String) {
        isProgrammaticChange = true
        sourceView.string = source
        translationView.string = translation
        isProgrammaticChange = false
        sourceLanguageLabel.stringValue = Self.languageTitle(sourceLanguage, fallback: "自动识别")
    }

    func setTargetLanguage(_ code: String) {
        selectTarget(code)
    }

    func setLoading(_ loading: Bool, message: String = "") {
        isLoading = loading
        progress.isHidden = !loading
        loading ? progress.startAnimation(nil) : progress.stopAnimation(nil)
        statusLabel.stringValue = message
        statusLabel.textColor = .secondaryLabelColor
        applyReadOnlyState()
    }

    func setStatus(_ message: String, isError: Bool = false) {
        statusLabel.stringValue = message
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
        statusLabel.toolTip = message
    }

    func setSpeakingField(_ field: TranslationWorkbenchField?) {
        sourceSpeakButton.title = field == .source ? "停止" : "朗读"
        translationSpeakButton.title = field == .translation ? "停止" : "朗读"
        sourceSpeakButton.image = symbol(field == .source ? "stop.fill" : "speaker.wave.2")
        translationSpeakButton.image = symbol(field == .translation ? "stop.fill" : "speaker.wave.2")
    }

    func focusSource() {
        window?.makeFirstResponder(sourceView)
    }

    private func build() {
        wantsLayer = true
        layer?.backgroundColor = ClaudeTheme.paperBg.cgColor

        sourceLanguageLabel.font = .systemFont(ofSize: 12, weight: .medium)
        sourceLanguageLabel.textColor = ClaudeTheme.inkMuted
        configureEditor(sourceView, accessibilityLabel: "翻译原文")
        configureEditor(translationView, accessibilityLabel: "翻译译文")

        configureActionButton(sourceSpeakButton, title: "朗读", symbolName: "speaker.wave.2", action: #selector(speakSource))
        configureActionButton(translationSpeakButton, title: "朗读", symbolName: "speaker.wave.2", action: #selector(speakTranslation))
        configureActionButton(sourceCopyButton, title: "复制", symbolName: "doc.on.doc", action: #selector(copySource))
        configureActionButton(translationCopyButton, title: "复制", symbolName: "doc.on.doc", action: #selector(copyTranslation))
        configureActionButton(copyAllButton, title: "复制全部", symbolName: "doc.on.doc.fill", action: #selector(copyAll))

        for choice in Self.languageChoices { targetLanguagePopup.addItem(withTitle: choice.title) }
        targetLanguagePopup.controlSize = .small
        targetLanguagePopup.target = self
        targetLanguagePopup.action = #selector(targetChanged)
        targetLanguagePopup.setAccessibilityLabel("目标语言")

        formattingPopup.addItems(withTitles: ["智能排版", "严格保留"])
        formattingPopup.controlSize = .small
        formattingPopup.target = self
        formattingPopup.action = #selector(formattingChanged)
        formattingPopup.setAccessibilityLabel("排版模式")

        retranslateButton.target = self
        retranslateButton.action = #selector(retranslate)
        retranslateButton.bezelStyle = .rounded
        retranslateButton.controlSize = .small
        retranslateButton.keyEquivalent = "\r"
        retranslateButton.setAccessibilityLabel("使用当前原文重新翻译")

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false
        progress.isHidden = true

        let sourceSection = makeSection(
            title: "原文",
            languageView: sourceLanguageLabel,
            buttons: [sourceSpeakButton, sourceCopyButton],
            textView: sourceView
        )
        translationLanguageLabel.font = .systemFont(ofSize: 12, weight: .medium)
        translationLanguageLabel.textColor = ClaudeTheme.inkMuted
        let translationSection = makeSection(
            title: "译文",
            languageView: translationLanguageLabel,
            buttons: [translationSpeakButton, translationCopyButton, copyAllButton],
            textView: translationView
        )

        let targetLabel = NSTextField(labelWithString: "目标")
        targetLabel.font = .systemFont(ofSize: 11, weight: .medium)
        targetLabel.textColor = ClaudeTheme.inkMuted
        let formatLabel = NSTextField(labelWithString: "排版")
        formatLabel.font = targetLabel.font
        formatLabel.textColor = targetLabel.textColor
        let footer = NSStackView(views: [
            targetLabel, targetLanguagePopup,
            formatLabel, formattingPopup,
            progress, statusLabel,
            retranslateButton
        ])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8
        footer.setHuggingPriority(.defaultHigh, for: .vertical)

        let stack = NSStackView(views: [sourceSection, translationSection, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 46, left: 20, bottom: 18, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            sourceSection.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            translationSection.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            sourceSection.heightAnchor.constraint(equalTo: translationSection.heightAnchor)
        ])
    }

    private func configureEditor(_ textView: NSTextView, accessibilityLabel: String) {
        textView.delegate = self
        textView.font = .systemFont(ofSize: 14.5)
        textView.textColor = ClaudeTheme.inkBody
        textView.backgroundColor = ClaudeTheme.paperAltBg
        textView.drawsBackground = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: 14.5),
            .foregroundColor: ClaudeTheme.inkBody,
            .paragraphStyle: MD.bodyStyle()
        ]
        textView.setAccessibilityLabel(accessibilityLabel)
    }

    private func makeSection(
        title: String,
        languageView: NSView,
        buttons: [NSButton],
        textView: NSTextView
    ) -> NSView {
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.textColor = ClaudeTheme.inkStrong
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [heading, languageView, spacer] + buttons)
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        textView.minSize = NSSize(width: 0, height: 110)

        let section = NSStackView(views: [header, scroll])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 6
        section.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.widthAnchor.constraint(equalTo: section.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: section.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 110)
        ])
        return section
    }

    private func configureActionButton(
        _ button: NSButton,
        title: String,
        symbolName: String,
        action: Selector
    ) {
        button.title = title
        button.image = symbol(symbolName)
        button.imagePosition = .imageLeading
        button.target = self
        button.action = action
        button.bezelStyle = .inline
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.setAccessibilityLabel(title)
    }

    private func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(
            .init(pointSize: 11, weight: .medium)
        )
    }

    private func applyReadOnlyState() {
        let editable = !isReadOnly && !isLoading
        sourceView.isEditable = editable
        translationView.isEditable = editable
        targetLanguagePopup.isEnabled = editable
        formattingPopup.isEnabled = editable
        retranslateButton.isEnabled = editable
        sourceSpeakButton.isEnabled = !isReadOnly && !isLoading && !sourceView.string.isEmpty
        translationSpeakButton.isEnabled = !isReadOnly && !isLoading && !translationView.string.isEmpty
        sourceCopyButton.isEnabled = !sourceView.string.isEmpty
        translationCopyButton.isEnabled = !translationView.string.isEmpty
        copyAllButton.isEnabled = !sourceView.string.isEmpty || !translationView.string.isEmpty
    }

    private func selectTarget(_ code: String) {
        let index = Self.languageChoices.firstIndex { choice in
            choice.code.caseInsensitiveCompare(code) == .orderedSame
        } ?? 0
        targetLanguagePopup.selectItem(at: index)
        translationLanguageLabel.stringValue = Self.languageChoices[index].title
    }

    private static func languageTitle(_ code: String, fallback: String) -> String {
        let normalized = code.lowercased()
        if normalized == "auto" || normalized.isEmpty { return fallback }
        return languageChoices.first { normalized.hasPrefix($0.code.lowercased()) }?.title ?? code
    }

    func textDidChange(_ notification: Notification) {
        guard !isProgrammaticChange else { return }
        if (notification.object as? NSTextView) === sourceView {
            onSourceChanged?(sourceView.string)
        } else if (notification.object as? NSTextView) === translationView {
            onTranslationChanged?(translationView.string)
        }
        applyReadOnlyState()
    }

    @objc private func targetChanged() {
        translationLanguageLabel.stringValue = Self.languageChoices[
            max(0, targetLanguagePopup.indexOfSelectedItem)
        ].title
        onTargetChanged?(targetLanguage)
    }
    @objc private func formattingChanged() { onFormattingChanged?(formattingMode) }
    @objc private func retranslate() { onRetranslate?() }
    @objc private func speakSource() { onSpeak?(.source) }
    @objc private func speakTranslation() { onSpeak?(.translation) }

    @objc private func copySource() { copy(sourceView.string, button: sourceCopyButton) }
    @objc private func copyTranslation() { copy(translationView.string, button: translationCopyButton) }
    @objc private func copyAll() {
        copy("原文\n\(sourceView.string)\n\n译文\n\(translationView.string)", button: copyAllButton)
    }

    private func copy(_ text: String, button: NSButton) {
        guard !text.isEmpty else { return }
        let payload = TranslationClipboardPayload.make(currentText: text)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(payload.plainText, forType: .string)
        item.setData(payload.rtf, forType: .rtf)
        pasteboard.writeObjects([item])
        let oldTitle = button.title
        let oldImage = button.image
        button.title = "已复制"
        button.image = symbol("checkmark")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak button] in
            button?.title = oldTitle
            button?.image = oldImage
        }
    }
}
