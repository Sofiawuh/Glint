import AppKit
import Foundation

// 翻译工作台方案 A 的 AppKit 展示、只读能力、复制与主动作切换黑盒契约。
// 测试只观察视图层级、控件可用性、可访问性、剪贴板结果及工作台公开动作，
// 不依赖具体颜色、间距、圆角半径或其他像素值。
//
// 预期最小运行命令：
//   swiftc -parse-as-library -o /tmp/glint_translation_workspace_presentation_contract_test \
//     TranslationFormatting.swift TranslationDocument.swift TranslationWorkbench.swift \
//     RecentResults.swift TranslationClipboard.swift Markdown.swift TranslationWorkspaceView.swift \
//     TranslationAIService.swift TranslationBlockRenderer.swift \
//     Config.swift ScreenshotHotKey.swift TextCommandHotKey.swift HotKey.swift \
//     translation_workspace_presentation_contract_tests.swift \
//     -framework AppKit -framework Carbon \
//     && /tmp/glint_translation_workspace_presentation_contract_test

enum TranslationWorkspacePresentationContractTestSupport {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() {
            print("  ok  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
        }
    }

    static func descendants<T: NSView>(of view: NSView, as type: T.Type) -> [T] {
        var matches = view.subviews.compactMap { $0 as? T }
        for child in view.subviews {
            matches.append(contentsOf: descendants(of: child, as: type))
        }
        return matches
    }

    static func contains(_ candidate: NSView, descendant: NSView) -> Bool {
        if candidate === descendant { return true }
        return candidate.subviews.contains { contains($0, descendant: descendant) }
    }

    static func editor(in view: NSView, accessibilityLabel: String) -> NSTextView? {
        descendants(of: view, as: NSTextView.self).first {
            $0.accessibilityLabel() == accessibilityLabel
        }
    }

    static func button(in view: NSView, title: String) -> NSButton? {
        descendants(of: view, as: NSButton.self).first { $0.title == title }
    }

    static func popup(in view: NSView, containing title: String) -> NSPopUpButton? {
        descendants(of: view, as: NSPopUpButton.self).first {
            $0.itemArray.contains { $0.title == title }
        }
    }

    static func actionCard(
        containing editor: NSTextView,
        excluding otherEditor: NSTextView,
        requiredButtonTitles: Set<String>
    ) -> NSView? {
        var candidate = editor.superview
        while let current = candidate {
            let titles = Set(descendants(of: current, as: NSButton.self).map(\.title))
            if !contains(current, descendant: otherEditor),
               requiredButtonTitles.isSubset(of: titles) {
                return current
            }
            candidate = current.superview
        }
        return nil
    }

    static func commonAncestor(of views: [NSView]) -> NSView? {
        guard let first = views.first else { return nil }
        var candidate: NSView? = first
        while let current = candidate {
            if views.dropFirst().allSatisfy({ contains(current, descendant: $0) }) {
                return current
            }
            candidate = current.superview
        }
        return nil
    }

    static func isVisuallyBoundedCard(_ view: NSView) -> Bool {
        if view is NSBox { return true }
        guard view.wantsLayer, let layer = view.layer else { return false }
        return layer.backgroundColor != nil || layer.borderColor != nil
    }

    static func makeView(readOnly: Bool = false) -> TranslationWorkspaceView {
        let view = TranslationWorkspaceView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 600)
        )
        view.configure(
            sourceText: "Current source paragraph.\n\n- Source item",
            translatedText: "当前译文段落。\n\n- 译文项目",
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            formattingMode: .smart,
            readOnly: readOnly
        )
        view.layoutSubtreeIfNeeded()
        return view
    }

    static func isPrimaryAction(_ button: NSButton?) -> Bool {
        button?.keyEquivalent == "\r" && button?.keyEquivalentModifierMask.isEmpty == true
    }

    struct PasteboardSnapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]

        static func capture(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
            let items = (pasteboard.pasteboardItems ?? []).map { item in
                Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                    item.data(forType: type).map { (type, $0) }
                })
            }
            return PasteboardSnapshot(items: items)
        }

        func restore(_ pasteboard: NSPasteboard) {
            pasteboard.clearContents()
            let restored = items.map { values -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in values { item.setData(data, forType: type) }
                return item
            }
            if !restored.isEmpty { pasteboard.writeObjects(restored) }
        }
    }
}

final class TestTranslationWorkspaceCardHierarchy {
    static func test_sourceAndTranslation_areSeparateBoundedCardsWithTheirOwnActions() {
        let view = TranslationWorkspacePresentationContractTestSupport.makeView()
        guard
            let source = TranslationWorkspacePresentationContractTestSupport.editor(
                in: view,
                accessibilityLabel: "翻译原文"
            ),
            let translation = TranslationWorkspacePresentationContractTestSupport.editor(
                in: view,
                accessibilityLabel: "翻译译文"
            ),
            let sourceCard = TranslationWorkspacePresentationContractTestSupport.actionCard(
                containing: source,
                excluding: translation,
                requiredButtonTitles: ["排版", "润色", "朗读", "复制"]
            ),
            let translationCard = TranslationWorkspacePresentationContractTestSupport.actionCard(
                containing: translation,
                excluding: source,
                requiredButtonTitles: ["排版", "润色", "朗读", "复制"]
            )
        else {
            TranslationWorkspacePresentationContractTestSupport.expect(
                false,
                "TestTranslationWorkspaceCardHierarchy.test_sourceAndTranslation_areSeparateBoundedCardsWithTheirOwnActions"
            )
            return
        }

        TranslationWorkspacePresentationContractTestSupport.expect(
            sourceCard !== translationCard
                && TranslationWorkspacePresentationContractTestSupport.isVisuallyBoundedCard(sourceCard)
                && TranslationWorkspacePresentationContractTestSupport.isVisuallyBoundedCard(translationCard),
            "TestTranslationWorkspaceCardHierarchy.test_sourceAndTranslation_areSeparateBoundedCardsWithTheirOwnActions"
        )
    }

    static func test_translationCardHeader_containsTargetLanguageSelector() {
        let view = TranslationWorkspacePresentationContractTestSupport.makeView()
        guard
            let source = TranslationWorkspacePresentationContractTestSupport.editor(
                in: view,
                accessibilityLabel: "翻译原文"
            ),
            let translation = TranslationWorkspacePresentationContractTestSupport.editor(
                in: view,
                accessibilityLabel: "翻译译文"
            ),
            let target = TranslationWorkspacePresentationContractTestSupport.popup(
                in: view,
                containing: "简体中文"
            ),
            let translationCard = TranslationWorkspacePresentationContractTestSupport.actionCard(
                containing: translation,
                excluding: source,
                requiredButtonTitles: ["排版", "润色", "朗读", "复制"]
            )
        else {
            TranslationWorkspacePresentationContractTestSupport.expect(
                false,
                "TestTranslationWorkspaceCardHierarchy.test_translationCardHeader_containsTargetLanguageSelector"
            )
            return
        }

        let translationTitle = TranslationWorkspacePresentationContractTestSupport.descendants(
            of: translationCard,
            as: NSTextField.self
        ).first { $0.stringValue == "译文" }
        let titleBar = translationTitle.flatMap {
            TranslationWorkspacePresentationContractTestSupport.commonAncestor(of: [$0, target])
        }

        TranslationWorkspacePresentationContractTestSupport.expect(
            TranslationWorkspacePresentationContractTestSupport.contains(
                translationCard,
                descendant: target
            )
                && titleBar != nil
                && !TranslationWorkspacePresentationContractTestSupport.contains(
                    titleBar!,
                    descendant: translation
                ),
            "TestTranslationWorkspaceCardHierarchy.test_translationCardHeader_containsTargetLanguageSelector"
        )
    }
}

final class TestTranslationWorkspaceAdaptiveEditors {
    static func test_shortContent_configurationAdoptsApproximately430PointCompactHeight() {
        let view = TranslationWorkspaceView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 600)
        )
        let initialPresentationHeight = view.frame.height
        view.configure(
            sourceText: "Short source.",
            translatedText: "短译文。",
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            formattingMode: .smart,
            readOnly: false
        )
        view.layoutSubtreeIfNeeded()
        let adoptedHeight = view.frame.height
        let compactFittingHeight = view.fittingSize.height

        TranslationWorkspacePresentationContractTestSupport.expect(
            abs(compactFittingHeight - 430) <= 1
                && abs(adoptedHeight - 430) <= 1
                && adoptedHeight < initialPresentationHeight
                && adoptedHeight == compactFittingHeight,
            "TestTranslationWorkspaceAdaptiveEditors.test_shortContent_configurationAdoptsApproximately430PointCompactHeight"
        )
    }

    static func test_longContent_prefersApproximately760PointInitialHeight() {
        let view = TranslationWorkspaceView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 570)
        )
        let source = (1...80).map { "Synthetic source paragraph \($0)." }.joined(separator: "\n")
        let translation = (1...80).map { "虚构译文段落 \($0)。" }.joined(separator: "\n")
        view.configure(
            sourceText: source,
            translatedText: translation,
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            formattingMode: .smart,
            readOnly: false
        )
        view.layoutSubtreeIfNeeded()

        let preferredHeight = view.fittingSize.height
        if abs(preferredHeight - 760) > 1 {
            print("      expected preferred height ≈760, actual \(preferredHeight)")
        }
        TranslationWorkspacePresentationContractTestSupport.expect(
            abs(preferredHeight - 760) <= 1,
            "TestTranslationWorkspaceAdaptiveEditors.test_longContent_prefersApproximately760PointInitialHeight"
        )
    }

    static func test_900By760Workspace_givesEachIndependentEditorAtLeast240VisiblePoints() {
        let view = TranslationWorkspaceView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 760)
        )
        let source = (1...160).map { "Synthetic source paragraph \($0)." }.joined(separator: "\n")
        let translation = (1...180).map { "虚构译文段落 \($0)。" }.joined(separator: "\n")
        view.configure(
            sourceText: source,
            translatedText: translation,
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            formattingMode: .smart,
            readOnly: false
        )
        view.layoutSubtreeIfNeeded()

        let scrolls = TranslationWorkspacePresentationContractTestSupport.descendants(
            of: view,
            as: NSScrollView.self
        )
        let visibleHeights = scrolls.map { $0.contentView.bounds.height }
        let documents = scrolls.compactMap(\.documentView)
        let hasRequiredHeights = visibleHeights.allSatisfy { $0 >= 240 }
        if !hasRequiredHeights {
            print("      expected two visible heights ≥240, actual \(visibleHeights)")
        }

        TranslationWorkspacePresentationContractTestSupport.expect(
            scrolls.count == 2
                && Set(documents.map(ObjectIdentifier.init)).count == 2
                && hasRequiredHeights,
            "TestTranslationWorkspaceAdaptiveEditors.test_900By760Workspace_givesEachIndependentEditorAtLeast240VisiblePoints"
        )
    }

    static func test_longContent_keepsTwoIndependentVerticalScrollRegions() {
        let view = TranslationWorkspaceView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 520)
        )
        let source = (1...160).map { "Source paragraph \($0)" }.joined(separator: "\n")
        let translation = (1...180).map { "译文段落 \($0)" }.joined(separator: "\n")
        view.configure(
            sourceText: source,
            translatedText: translation,
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            formattingMode: .smart,
            readOnly: false
        )
        view.layoutSubtreeIfNeeded()

        let scrolls = TranslationWorkspacePresentationContractTestSupport.descendants(
            of: view,
            as: NSScrollView.self
        )
        let documents = scrolls.compactMap(\.documentView)
        let independentlyScrollable = scrolls.count == 2
            && Set(documents.map(ObjectIdentifier.init)).count == 2
            && scrolls.allSatisfy { scroll in
                scroll.hasVerticalScroller
                    && (scroll.documentView?.bounds.height ?? 0) > scroll.contentView.bounds.height
            }

        TranslationWorkspacePresentationContractTestSupport.expect(
            independentlyScrollable,
            "TestTranslationWorkspaceAdaptiveEditors.test_longContent_keepsTwoIndependentVerticalScrollRegions"
        )
    }

    static func test_smallScreenSizedWorkspace_staysInsideSafeBoundsWithoutHorizontalScroll() {
        let safeWidth: CGFloat = 676
        let safeHeight: CGFloat = 536
        let view = TranslationWorkspaceView(
            frame: NSRect(x: 0, y: 0, width: safeWidth, height: safeHeight)
        )
        let source = (1...100).map { "Synthetic source paragraph \($0)." }.joined(separator: "\n")
        let translation = (1...100).map { "虚构译文段落 \($0)。" }.joined(separator: "\n")
        view.configure(
            sourceText: source,
            translatedText: translation,
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            formattingMode: .smart,
            readOnly: false
        )
        view.layoutSubtreeIfNeeded()

        let scrolls = TranslationWorkspacePresentationContractTestSupport.descendants(
            of: view,
            as: NSScrollView.self
        )
        TranslationWorkspacePresentationContractTestSupport.expect(
            view.frame.width <= safeWidth
                && view.frame.height <= safeHeight
                && scrolls.count == 2
                && scrolls.allSatisfy { !$0.hasHorizontalScroller },
            "TestTranslationWorkspaceAdaptiveEditors.test_smallScreenSizedWorkspace_staysInsideSafeBoundsWithoutHorizontalScroll"
        )
    }
}

final class TestTranslationWorkspaceFixedFooter {
    static func test_footerGroupsStatusRetranslationProcessingModeAndManualAIWithoutCopyAll() {
        let view = TranslationWorkspacePresentationContractTestSupport.makeView()
        view.setStatus("Synthetic ready status")
        guard
            let retranslate = TranslationWorkspacePresentationContractTestSupport.button(
                in: view,
                title: "重新翻译"
            ),
            let pairAI = TranslationWorkspacePresentationContractTestSupport.button(
                in: view,
                title: "一键智能排版"
            ),
            let processing = TranslationWorkspacePresentationContractTestSupport.popup(
                in: view,
                containing: "智能润色"
            ),
            let status = TranslationWorkspacePresentationContractTestSupport.descendants(
                of: view,
                as: NSTextField.self
            ).first(where: { $0.stringValue == "Synthetic ready status" }),
            let footer = TranslationWorkspacePresentationContractTestSupport.commonAncestor(
                of: [retranslate, pairAI, processing, status]
            )
        else {
            TranslationWorkspacePresentationContractTestSupport.expect(
                false,
                "TestTranslationWorkspaceFixedFooter.test_footerGroupsStatusRetranslationProcessingModeAndManualAIWithoutCopyAll"
            )
            return
        }

        let hasCopyAllButton = TranslationWorkspacePresentationContractTestSupport.button(
            in: view,
            title: "复制全部"
        ) != nil
        TranslationWorkspacePresentationContractTestSupport.expect(
            TranslationWorkspacePresentationContractTestSupport.descendants(
                of: footer,
                as: NSTextView.self
            ).isEmpty
                && TranslationWorkspacePresentationContractTestSupport.contains(
                    footer,
                    descendant: status
                )
                && !hasCopyAllButton,
            "TestTranslationWorkspaceFixedFooter.test_footerGroupsStatusRetranslationProcessingModeAndManualAIWithoutCopyAll"
        )
    }
}

final class TestTranslationWorkspaceCopyAll {
    static func test_normalAndReadOnlyViews_exposeCopyAllActionWithoutFooterButton() {
        let pasteboard = NSPasteboard.general
        let snapshot = TranslationWorkspacePresentationContractTestSupport.PasteboardSnapshot.capture(
            pasteboard
        )
        defer { snapshot.restore(pasteboard) }
        let normal = TranslationWorkspacePresentationContractTestSupport.makeView(readOnly: false)
        let readOnly = TranslationWorkspacePresentationContractTestSupport.makeView(readOnly: true)

        let normalCopy = TranslationWorkspacePresentationContractTestSupport.button(
            in: normal,
            title: "复制全部"
        )
        let readOnlyCopy = TranslationWorkspacePresentationContractTestSupport.button(
            in: readOnly,
            title: "复制全部"
        )

        TranslationWorkspacePresentationContractTestSupport.expect(
            normalCopy == nil
                && readOnlyCopy == nil
                && normal.copyAllToPasteboard()
                && readOnly.copyAllToPasteboard(),
            "TestTranslationWorkspaceCopyAll.test_normalAndReadOnlyViews_exposeCopyAllActionWithoutFooterButton"
        )
    }

    static func test_copyAll_readsCurrentEditorsAndPreservesPlainTextAndRTFStructure() {
        let pasteboard = NSPasteboard.general
        let snapshot = TranslationWorkspacePresentationContractTestSupport.PasteboardSnapshot.capture(
            pasteboard
        )
        defer { snapshot.restore(pasteboard) }

        let view = TranslationWorkspacePresentationContractTestSupport.makeView()
        guard
            let source = TranslationWorkspacePresentationContractTestSupport.editor(
                in: view,
                accessibilityLabel: "翻译原文"
            ),
            let translation = TranslationWorkspacePresentationContractTestSupport.editor(
                in: view,
                accessibilityLabel: "翻译译文"
            )
        else {
            TranslationWorkspacePresentationContractTestSupport.expect(
                false,
                "TestTranslationWorkspaceCopyAll.test_copyAll_readsCurrentEditorsAndPreservesPlainTextAndRTFStructure"
            )
            return
        }

        let currentSource = "Edited heading\n\n- Current source item"
        let currentTranslation = "编辑后的标题\n\n- 当前译文项目"
        source.string = currentSource
        translation.string = currentTranslation
        source.textStorage?.addAttribute(
            .font,
            value: NSFont.boldSystemFont(ofSize: 17),
            range: (currentSource as NSString).range(of: "Edited heading")
        )
        let listStyle = NSMutableParagraphStyle()
        listStyle.headIndent = 24
        translation.textStorage?.addAttribute(
            .paragraphStyle,
            value: listStyle,
            range: (currentTranslation as NSString).range(of: "- 当前译文项目")
        )

        let copied = view.copyAllToPasteboard()

        let expected = "原文\n\(currentSource)\n\n译文\n\(currentTranslation)"
        let plainText = pasteboard.string(forType: .string)
        let richText = pasteboard.data(forType: .rtf).flatMap {
            try? NSAttributedString(
                data: $0,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
        }
        let headingRange = (richText?.string as NSString?)?.range(of: "Edited heading")
            ?? NSRange(location: NSNotFound, length: 0)
        let listRange = (richText?.string as NSString?)?.range(of: "- 当前译文项目")
            ?? NSRange(location: NSNotFound, length: 0)
        let headingFont = headingRange.location == NSNotFound
            ? nil
            : richText?.attribute(.font, at: headingRange.location, effectiveRange: nil) as? NSFont
        let copiedListStyle = listRange.location == NSNotFound
            ? nil
            : richText?.attribute(
                .paragraphStyle,
                at: listRange.location,
                effectiveRange: nil
            ) as? NSParagraphStyle

        TranslationWorkspacePresentationContractTestSupport.expect(
            copied
                && plainText == expected
                && richText?.string == expected
                && headingFont?.fontDescriptor.symbolicTraits.contains(.bold) == true
                && (copiedListStyle?.headIndent ?? 0) > 0,
            "TestTranslationWorkspaceCopyAll.test_copyAll_readsCurrentEditorsAndPreservesPlainTextAndRTFStructure"
        )
    }
}

final class TestTranslationWorkspaceReadOnlyCapabilities {
    static func test_recentResult_disablesEditingAndCloudActionsButKeepsCopyAndSpeech() {
        let view = TranslationWorkspacePresentationContractTestSupport.makeView(readOnly: true)
        let editors = TranslationWorkspacePresentationContractTestSupport.descendants(
            of: view,
            as: NSTextView.self
        )
        let buttons = TranslationWorkspacePresentationContractTestSupport.descendants(
            of: view,
            as: NSButton.self
        )
        let popups = TranslationWorkspacePresentationContractTestSupport.descendants(
            of: view,
            as: NSPopUpButton.self
        )
        let copyButtons = buttons.filter { $0.title == "复制" }
        let speechButtons = buttons.filter { $0.title == "朗读" }
        let cloudButtons = buttons.filter {
            ["排版", "润色", "重新翻译", "一键智能排版", "一键智能润色"].contains($0.title)
        }

        TranslationWorkspacePresentationContractTestSupport.expect(
            editors.count == 2
                && editors.allSatisfy { !$0.isEditable }
                && popups.allSatisfy { !$0.isEnabled }
                && cloudButtons.allSatisfy { !$0.isEnabled || $0.isHidden }
                && copyButtons.count == 2
                && copyButtons.allSatisfy(\.isEnabled)
                && speechButtons.count == 2
                && speechButtons.allSatisfy(\.isEnabled),
            "TestTranslationWorkspaceReadOnlyCapabilities.test_recentResult_disablesEditingAndCloudActionsButKeepsCopyAndSpeech"
        )
    }
}

final class TestTranslationWorkspacePrimaryAction {
    static func test_completedTranslation_emphasizesPairAIUntilSourceBecomesDirtyThenEmphasizesRetranslation() {
        let view = TranslationWorkspacePresentationContractTestSupport.makeView()
        guard
            let source = TranslationWorkspacePresentationContractTestSupport.editor(
                in: view,
                accessibilityLabel: "翻译原文"
            ),
            let pairAI = TranslationWorkspacePresentationContractTestSupport.button(
                in: view,
                title: "一键智能排版"
            ),
            let retranslate = TranslationWorkspacePresentationContractTestSupport.button(
                in: view,
                title: "重新翻译"
            )
        else {
            TranslationWorkspacePresentationContractTestSupport.expect(
                false,
                "TestTranslationWorkspacePrimaryAction.test_completedTranslation_emphasizesPairAIUntilSourceBecomesDirtyThenEmphasizesRetranslation"
            )
            return
        }

        let completionStateIsCorrect = TranslationWorkspacePresentationContractTestSupport.isPrimaryAction(pairAI)
            && !TranslationWorkspacePresentationContractTestSupport.isPrimaryAction(retranslate)
        source.string = "Dirty source that invalidates the displayed translation."
        view.textDidChange(Notification(name: NSText.didChangeNotification, object: source))

        TranslationWorkspacePresentationContractTestSupport.expect(
            completionStateIsCorrect
                && TranslationWorkspacePresentationContractTestSupport.isPrimaryAction(retranslate)
                && !TranslationWorkspacePresentationContractTestSupport.isPrimaryAction(pairAI)
                && !pairAI.isEnabled,
            "TestTranslationWorkspacePrimaryAction.test_completedTranslation_emphasizesPairAIUntilSourceBecomesDirtyThenEmphasizesRetranslation"
        )
    }

    static func test_dirtySource_preventsPairAIFromUsingTheStaleTranslation() {
        var workbench = TranslationWorkbenchState(
            historyID: "fictional-stale-translation-history",
            sourceText: "Source matching the completed translation.",
            translatedText: "与原文匹配的已完成译文。",
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            formattingMode: .smart
        )
        workbench.editSource("Edited source whose translation is now stale.")

        let stalePairRequest = workbench.beginPairAIProcessing(mode: .smart)
        let retranslationRequest = workbench.beginRetranslation()

        TranslationWorkspacePresentationContractTestSupport.expect(
            stalePairRequest == nil
                && retranslationRequest?.sourceText == "Edited source whose translation is now stale.",
            "TestTranslationWorkspacePrimaryAction.test_dirtySource_preventsPairAIFromUsingTheStaleTranslation"
        )
    }
}

final class TestTranslationWorkspaceAccessibility {
    static func test_allButtonsAndSelectors_haveAccessibilityLabels() {
        let view = TranslationWorkspacePresentationContractTestSupport.makeView()
        let buttons = TranslationWorkspacePresentationContractTestSupport.descendants(
            of: view,
            as: NSButton.self
        )
        let popups = TranslationWorkspacePresentationContractTestSupport.descendants(
            of: view,
            as: NSPopUpButton.self
        )
        let controls: [NSView] = buttons.map { $0 as NSView } + popups.map { $0 as NSView }

        TranslationWorkspacePresentationContractTestSupport.expect(
            !controls.isEmpty && controls.allSatisfy {
                !($0.accessibilityLabel() ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
            },
            "TestTranslationWorkspaceAccessibility.test_allButtonsAndSelectors_haveAccessibilityLabels"
        )
    }
}

@main
enum TranslationWorkspacePresentationContractTests {
    static func main() {
        _ = NSApplication.shared
        TestTranslationWorkspaceCardHierarchy.test_sourceAndTranslation_areSeparateBoundedCardsWithTheirOwnActions()
        TestTranslationWorkspaceCardHierarchy.test_translationCardHeader_containsTargetLanguageSelector()
        TestTranslationWorkspaceAdaptiveEditors.test_shortContent_configurationAdoptsApproximately430PointCompactHeight()
        TestTranslationWorkspaceAdaptiveEditors.test_longContent_prefersApproximately760PointInitialHeight()
        TestTranslationWorkspaceAdaptiveEditors.test_900By760Workspace_givesEachIndependentEditorAtLeast240VisiblePoints()
        TestTranslationWorkspaceAdaptiveEditors.test_longContent_keepsTwoIndependentVerticalScrollRegions()
        TestTranslationWorkspaceAdaptiveEditors.test_smallScreenSizedWorkspace_staysInsideSafeBoundsWithoutHorizontalScroll()
        TestTranslationWorkspaceFixedFooter.test_footerGroupsStatusRetranslationProcessingModeAndManualAIWithoutCopyAll()
        TestTranslationWorkspaceCopyAll.test_normalAndReadOnlyViews_exposeCopyAllActionWithoutFooterButton()
        TestTranslationWorkspaceCopyAll.test_copyAll_readsCurrentEditorsAndPreservesPlainTextAndRTFStructure()
        TestTranslationWorkspaceReadOnlyCapabilities.test_recentResult_disablesEditingAndCloudActionsButKeepsCopyAndSpeech()
        TestTranslationWorkspacePrimaryAction.test_completedTranslation_emphasizesPairAIUntilSourceBecomesDirtyThenEmphasizesRetranslation()
        TestTranslationWorkspacePrimaryAction.test_dirtySource_preventsPairAIFromUsingTheStaleTranslation()
        TestTranslationWorkspaceAccessibility.test_allButtonsAndSelectors_haveAccessibilityLabels()

        print(
            TranslationWorkspacePresentationContractTestSupport.failures == 0
                ? "ALL PASS"
                : "\(TranslationWorkspacePresentationContractTestSupport.failures) FAILURES"
        )
        exit(TranslationWorkspacePresentationContractTestSupport.failures == 0 ? 0 : 1)
    }
}
