import AppKit

final class TranslationWorkspaceView: NSView, NSTextViewDelegate {
    static let compactPreferredHeight: CGFloat = 430
    static let longDocumentPreferredHeight: CGFloat = 760

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
    var onAIAction: ((TranslationWorkbenchField, TranslationFormattingMode) -> Void)?
    var onPairAIAction: ((TranslationFormattingMode) -> Void)?
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
    private let sourceFormatButton = NSButton()
    private let sourcePolishButton = NSButton()
    private let translationFormatButton = NSButton()
    private let translationPolishButton = NSButton()
    private let pairAIButton = NSButton()
    private let retranslateButton = NSButton(title: "重新翻译", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()
    private var isProgrammaticChange = false
    private var isReadOnly = false
    private var isLoading = false
    private var aiFieldInFlight: TranslationWorkbenchField?
    private var isPairAIProcessing = false
    private var sourceIsDirty = false
    private var preferredContentHeight: CGFloat?

    override var fittingSize: NSSize {
        NSSize(
            width: max(frame.width, 660),
            height: preferredContentHeight ?? max(frame.height, 520)
        )
    }

    static func preferredHeight(source: String, translation: String) -> CGFloat {
        let longest = max(source.count, translation.count)
        let lines = max(
            source.components(separatedBy: .newlines).count,
            translation.components(separatedBy: .newlines).count
        )
        return longest <= 1_600 && lines <= 14
            ? compactPreferredHeight
            : longDocumentPreferredHeight
    }

    static func initialPresentationHeight(
        source: String,
        translation: String,
        savedHeight: CGFloat,
        availableHeight: CGFloat
    ) -> CGFloat {
        let safeAvailableHeight = max(0, availableHeight - 24)
        return min(
            max(savedHeight, preferredHeight(source: source, translation: translation)),
            safeAvailableHeight
        )
    }

    var sourceText: String { sourceView.string }
    var translatedText: String { translationView.string }
    var targetLanguage: String {
        let index = targetLanguagePopup.indexOfSelectedItem
        guard index > 0 else { return "auto" }
        return Self.languageChoices[min(index - 1, Self.languageChoices.count - 1)].code
    }
    var targetMode: TranslationTargetMode {
        targetLanguagePopup.indexOfSelectedItem == 0 ? .automatic : .fixed
    }
    var formattingMode: TranslationFormattingMode {
        switch formattingPopup.indexOfSelectedItem {
        case 0: return .strict
        case 2: return .polish
        default: return .smart
        }
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
        targetMode: TranslationTargetMode = .fixed,
        readOnly: Bool
    ) {
        isReadOnly = readOnly
        sourceIsDirty = false
        isProgrammaticChange = true
        setPlainText(sourceText, in: sourceView)
        setPlainText(translatedText, in: translationView)
        isProgrammaticChange = false
        sourceLanguageLabel.stringValue = Self.languageTitle(sourceLanguage, fallback: "自动识别")
        selectTarget(targetLanguage, mode: targetMode)
        selectFormattingMode(formattingMode)
        applyReadOnlyState()
        updateAdaptiveHeight(source: sourceText, translation: translatedText)
        sourceView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        translationView.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }

    func updateTexts(source: String, translation: String, sourceLanguage: String) {
        isProgrammaticChange = true
        setPlainText(source, in: sourceView)
        setPlainText(translation, in: translationView)
        isProgrammaticChange = false
        sourceIsDirty = false
        sourceLanguageLabel.stringValue = Self.languageTitle(sourceLanguage, fallback: "自动识别")
        updateAdaptiveHeight(source: source, translation: translation)
        applyReadOnlyState()
    }

    func setTargetLanguage(_ code: String, mode: TranslationTargetMode = .fixed) {
        selectTarget(code, mode: mode)
    }

    func updateReports(
        source: TranslationRenderedReport,
        translation: TranslationRenderedReport,
        sourceLanguage: String
    ) {
        isProgrammaticChange = true
        sourceView.textStorage?.setAttributedString(source.attributedText)
        translationView.textStorage?.setAttributedString(translation.attributedText)
        isProgrammaticChange = false
        sourceIsDirty = false
        sourceLanguageLabel.stringValue = Self.languageTitle(sourceLanguage, fallback: "自动识别")
        updateAdaptiveHeight(source: source.attributedText.string, translation: translation.attributedText.string)
        applyReadOnlyState()
    }

    func updateReport(
        _ report: TranslationRenderedReport,
        field: TranslationWorkbenchField,
        sourceLanguage: String
    ) {
        isProgrammaticChange = true
        if field == .source {
            sourceView.textStorage?.setAttributedString(report.attributedText)
        } else {
            translationView.textStorage?.setAttributedString(report.attributedText)
        }
        isProgrammaticChange = false
        if field == .source { sourceIsDirty = true }
        sourceLanguageLabel.stringValue = Self.languageTitle(sourceLanguage, fallback: "自动识别")
        applyReadOnlyState()
    }

    func setLoading(_ loading: Bool, message: String = "") {
        isLoading = loading
        progress.isHidden = !loading
        loading ? progress.startAnimation(nil) : progress.stopAnimation(nil)
        statusLabel.stringValue = message
        statusLabel.textColor = .secondaryLabelColor
        applyReadOnlyState()
    }

    func setAIProcessing(
        field: TranslationWorkbenchField?,
        message: String = ""
    ) {
        aiFieldInFlight = field
        statusLabel.stringValue = message
        statusLabel.textColor = .secondaryLabelColor
        applyReadOnlyState()
    }

    func setPairAIProcessing(_ processing: Bool, message: String = "") {
        isPairAIProcessing = processing
        if !isLoading {
            progress.isHidden = !processing
            processing ? progress.startAnimation(nil) : progress.stopAnimation(nil)
        }
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
        configureActionButton(sourceFormatButton, title: "排版", symbolName: "text.alignleft", action: #selector(formatSource))
        configureActionButton(sourcePolishButton, title: "润色", symbolName: "sparkles", action: #selector(polishSource))
        configureActionButton(translationFormatButton, title: "排版", symbolName: "text.alignleft", action: #selector(formatTranslation))
        configureActionButton(translationPolishButton, title: "润色", symbolName: "sparkles", action: #selector(polishTranslation))
        targetLanguagePopup.addItem(withTitle: "自动识别（中文 → 英语，其他 → 简体中文）")
        for choice in Self.languageChoices { targetLanguagePopup.addItem(withTitle: choice.title) }
        targetLanguagePopup.controlSize = .small
        targetLanguagePopup.target = self
        targetLanguagePopup.action = #selector(targetChanged)
        targetLanguagePopup.setAccessibilityLabel("目标语言")

        formattingPopup.addItems(withTitles: ["严格保留", "智能排版", "智能润色"])
        formattingPopup.controlSize = .small
        formattingPopup.target = self
        formattingPopup.action = #selector(formattingChanged)
        formattingPopup.setAccessibilityLabel("排版模式")

        pairAIButton.target = self
        pairAIButton.action = #selector(processPairWithAI)
        pairAIButton.bezelStyle = .rounded
        pairAIButton.controlSize = .small
        pairAIButton.font = .systemFont(ofSize: 11, weight: .semibold)
        pairAIButton.image = symbol("sparkles")
        pairAIButton.imagePosition = .imageLeading
        pairAIButton.setAccessibilityLabel("一键智能排版")

        retranslateButton.target = self
        retranslateButton.action = #selector(retranslate)
        retranslateButton.bezelStyle = .rounded
        retranslateButton.controlSize = .small
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
            languageViews: [sourceLanguageLabel],
            buttons: [sourceFormatButton, sourcePolishButton, sourceSpeakButton, sourceCopyButton],
            textView: sourceView
        )
        let translationSection = makeSection(
            title: "译文",
            languageViews: [targetLanguagePopup],
            buttons: [translationFormatButton, translationPolishButton, translationSpeakButton, translationCopyButton],
            textView: translationView
        )

        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [
            progress, statusLabel,
            footerSpacer,
            retranslateButton,
            formattingPopup,
            pairAIButton
        ])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8
        footer.setHuggingPriority(.defaultHigh, for: .vertical)
        footer.wantsLayer = true
        footer.layer?.backgroundColor = ClaudeTheme.paperAltBg.cgColor
        footer.layer?.cornerRadius = 10
        footer.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)

        let stack = NSStackView(views: [sourceSection, translationSection, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 46, left: 18, bottom: 16, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            sourceSection.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -36),
            translationSection.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -36),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -36),
            sourceSection.heightAnchor.constraint(equalTo: translationSection.heightAnchor)
        ])
    }

    private func configureEditor(_ textView: NSTextView, accessibilityLabel: String) {
        textView.delegate = self
        textView.font = .systemFont(ofSize: 14.5)
        textView.textColor = ClaudeTheme.inkBody
        textView.backgroundColor = ClaudeTheme.paperAltBg
        textView.drawsBackground = true
        textView.isRichText = true
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
        languageViews: [NSView],
        buttons: [NSButton],
        textView: NSTextView
    ) -> NSView {
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.textColor = ClaudeTheme.inkStrong
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [heading] + languageViews + [spacer] + buttons)
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
        textView.minSize = NSSize(width: 0, height: 96)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: max(1, scroll.contentSize.width),
            height: CGFloat.greatestFiniteMagnitude
        )

        let section = NSStackView(views: [header, scroll])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 10
        section.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        section.wantsLayer = true
        section.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        section.layer?.borderColor = ClaudeTheme.windowBorder.cgColor
        section.layer?.borderWidth = 1
        section.layer?.cornerRadius = 12
        section.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.widthAnchor.constraint(equalTo: section.widthAnchor, constant: -24),
            scroll.widthAnchor.constraint(equalTo: section.widthAnchor, constant: -24),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 96)
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
        targetLanguagePopup.isEnabled = editable && !isPairAIProcessing
        formattingPopup.isEnabled = editable && !isPairAIProcessing
        retranslateButton.isEnabled = editable
        sourceSpeakButton.isEnabled = !isLoading && !sourceView.string.isEmpty
        translationSpeakButton.isEnabled = !isLoading && !translationView.string.isEmpty
        sourceCopyButton.isEnabled = !sourceView.string.isEmpty
        translationCopyButton.isEnabled = !translationView.string.isEmpty
        for button in [sourceFormatButton, sourcePolishButton, translationFormatButton, translationPolishButton] {
            button.isEnabled = !isReadOnly
                && !isLoading
                && aiFieldInFlight == nil
                && !isPairAIProcessing
        }
        updatePairAIButton()
    }

    private func selectTarget(_ code: String, mode: TranslationTargetMode) {
        if mode == .automatic {
            targetLanguagePopup.selectItem(at: 0)
            return
        }
        let index = Self.languageChoices.firstIndex { choice in
            choice.code.caseInsensitiveCompare(code) == .orderedSame
        } ?? 0
        targetLanguagePopup.selectItem(at: index + 1)
    }

    private func selectFormattingMode(_ mode: TranslationFormattingMode) {
        switch mode {
        case .strict: formattingPopup.selectItem(at: 0)
        case .smart: formattingPopup.selectItem(at: 1)
        case .polish: formattingPopup.selectItem(at: 2)
        }
        updatePairAIButton()
    }

    private func updatePairAIButton() {
        let mode = formattingMode
        pairAIButton.title = mode == .polish ? "一键智能润色" : "一键智能排版"
        pairAIButton.setAccessibilityLabel(pairAIButton.title)
        pairAIButton.isHidden = isReadOnly || mode == .strict
        pairAIButton.isEnabled = !pairAIButton.isHidden
            && !isLoading
            && aiFieldInFlight == nil
            && !isPairAIProcessing
            && !sourceIsDirty
            && !sourceView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !translationView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        pairAIButton.keyEquivalent = pairAIButton.isEnabled ? "\r" : ""
        pairAIButton.keyEquivalentModifierMask = []
        retranslateButton.keyEquivalent = sourceIsDirty && retranslateButton.isEnabled ? "\r" : ""
        retranslateButton.keyEquivalentModifierMask = []
    }

    private func updateAdaptiveHeight(source: String, translation: String) {
        let preferredHeight = Self.preferredHeight(source: source, translation: translation)
        preferredContentHeight = preferredHeight
        if preferredHeight == Self.compactPreferredHeight, frame.height > preferredHeight {
            frame.size.height = preferredHeight
        }
    }

    private static func languageTitle(_ code: String, fallback: String) -> String {
        let normalized = code.lowercased()
        if normalized == "auto" || normalized.isEmpty { return fallback }
        return languageChoices.first { normalized.hasPrefix($0.code.lowercased()) }?.title ?? code
    }

    func textDidChange(_ notification: Notification) {
        guard !isProgrammaticChange else { return }
        if (notification.object as? NSTextView) === sourceView {
            sourceIsDirty = true
            onSourceChanged?(sourceView.string)
        } else if (notification.object as? NSTextView) === translationView {
            onTranslationChanged?(translationView.string)
        }
        updateAdaptiveHeight(source: sourceView.string, translation: translationView.string)
        applyReadOnlyState()
    }

    @objc private func targetChanged() {
        onTargetChanged?(targetLanguage)
    }
    @objc private func formattingChanged() {
        updatePairAIButton()
        onFormattingChanged?(formattingMode)
    }
    @objc private func retranslate() { onRetranslate?() }
    @objc private func processPairWithAI() { onPairAIAction?(formattingMode) }
    @objc private func speakSource() { onSpeak?(.source) }
    @objc private func speakTranslation() { onSpeak?(.translation) }
    @objc private func formatSource() { onAIAction?(.source, .smart) }
    @objc private func polishSource() { onAIAction?(.source, .polish) }
    @objc private func formatTranslation() { onAIAction?(.translation, .smart) }
    @objc private func polishTranslation() { onAIAction?(.translation, .polish) }

    @objc private func copySource() { copy(sourceView.attributedString(), button: sourceCopyButton) }
    @objc private func copyTranslation() { copy(translationView.attributedString(), button: translationCopyButton) }
    @discardableResult
    func copyAllToPasteboard() -> Bool {
        guard !sourceView.string.isEmpty || !translationView.string.isEmpty else { return false }
        let combined = NSMutableAttributedString(string: "原文\n", attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold)
        ])
        combined.append(sourceView.attributedString())
        combined.append(NSAttributedString(string: "\n\n译文\n", attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold)
        ]))
        combined.append(translationView.attributedString())
        return writeToPasteboard(combined)
    }

    private func copy(_ text: NSAttributedString, button: NSButton) {
        guard writeToPasteboard(text) else { return }
        let oldTitle = button.title
        let oldImage = button.image
        button.title = "已复制"
        button.image = symbol("checkmark")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak button] in
            button?.title = oldTitle
            button?.image = oldImage
        }
    }

    private func writeToPasteboard(_ text: NSAttributedString) -> Bool {
        guard text.length > 0 else { return false }
        let payload = TranslationClipboardPayload.make(currentAttributedText: text)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(payload.plainText, forType: .string)
        item.setData(payload.rtf, forType: .rtf)
        pasteboard.writeObjects([item])
        return true
    }

    private func setPlainText(_ text: String, in textView: NSTextView) {
        let report = TranslationBlockRenderer.render(blocks: [.paragraph(text)])
        textView.textStorage?.setAttributedString(report.attributedText)
    }
}
