import Foundation
import CoreGraphics

// Cross-app selection compatibility black-box tests.
// These tests use only pure data and never access real Accessibility elements,
// pasteboard contents, application configuration, or user-selected text.
// Run:
//   swiftc -o /tmp/glint_selection_compatibility_test \
//     SelectionDetection.swift selection_compatibility_tests.swift \
//     -framework Foundation -framework CoreGraphics \
//     && /tmp/glint_selection_compatibility_test

enum SelectionCompatibilityTestSupport {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() {
            print("  ok  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
        }
    }

    static func probe(
        text: String?,
        sourceApplication: String? = "com.example.FictionalEditor",
        focusedElementIdentity: String? = "fictional-editor-1",
        rangeLength: Int?,
        rangeFingerprint: String?,
        bounds: CGRect?,
        releasePoint: CGPoint = CGPoint(x: 640, y: 360)
    ) -> SelectionProbe {
        SelectionProbe(
            text: text,
            sourceApplication: sourceApplication,
            focusedElementIdentity: focusedElementIdentity,
            rangeLength: rangeLength,
            rangeFingerprint: rangeFingerprint,
            boundsInQuartz: bounds,
            releasePointInQuartz: releasePoint
        )
    }

    static func candidate(
        origin: SelectionProbeOrigin,
        role: String,
        text: String?,
        rangeLength: Int? = nil,
        rangeFingerprint: String? = nil,
        bounds: CGRect? = nil
    ) -> SelectionProbeCandidate {
        SelectionProbeCandidate(
            origin: origin,
            role: role,
            probe: probe(
                text: text,
                rangeLength: rangeLength,
                rangeFingerprint: rangeFingerprint,
                bounds: bounds
            )
        )
    }

    static func capture(
        before: Int = 40,
        after: Int = 41,
        text: String? = "portable selection",
        types: [String] = ["public.utf8-plain-text"]
    ) -> ClipboardFallbackCapture {
        ClipboardFallbackCapture(
            changeCountBefore: before,
            changeCountAfter: after,
            text: text,
            types: types
        )
    }

    static func clipboardSnapshot(
        text: String,
        sourceApplication: String = "com.example.FictionalEditor",
        focusedElementIdentity: String? = "fictional-editor-1",
        releasePoint: CGPoint
    ) -> SelectionSnapshot? {
        SelectionDetection.clipboardOnlySnapshot(
            capture: capture(text: text),
            sourceApplication: sourceApplication,
            focusedElementIdentity: focusedElementIdentity,
            releasePointInQuartz: releasePoint
        )
    }
}

enum TestSelectionCandidateRanking {
    static func test_hit_candidate_with_selection_beats_empty_focused_candidate() {
        let focused = SelectionCompatibilityTestSupport.candidate(
            origin: .focusedElement,
            role: "AXTextArea",
            text: nil
        )
        let hit = SelectionCompatibilityTestSupport.candidate(
            origin: .hitElement,
            role: "AXStaticText",
            text: "selected at release point",
            rangeLength: 25,
            rangeFingerprint: "90:25",
            bounds: CGRect(x: 220, y: 180, width: 164, height: 36)
        )

        SelectionCompatibilityTestSupport.expect(
            SelectionDetection.bestCandidate(from: [focused, hit]) == hit,
            "test_hit_candidate_with_selection_beats_empty_focused_candidate"
        )
    }

    static func test_parent_web_area_with_selection_beats_empty_focused_and_hit_candidates() {
        let focused = SelectionCompatibilityTestSupport.candidate(
            origin: .focusedElement,
            role: "AXGroup",
            text: nil
        )
        let hit = SelectionCompatibilityTestSupport.candidate(
            origin: .hitElement,
            role: "AXStaticText",
            text: nil
        )
        let parentWebArea = SelectionCompatibilityTestSupport.candidate(
            origin: .hitAncestor(depth: 1),
            role: "AXWebArea",
            text: "selection exposed by parent",
            rangeLength: 27,
            rangeFingerprint: "140:27",
            bounds: CGRect(x: 180, y: 260, width: 208, height: 54)
        )

        SelectionCompatibilityTestSupport.expect(
            SelectionDetection.bestCandidate(from: [focused, hit, parentWebArea]) == parentWebArea,
            "test_parent_web_area_with_selection_beats_empty_focused_and_hit_candidates"
        )
    }

    static func test_range_and_bounds_candidate_beats_text_only_candidate() {
        let textOnly = SelectionCompatibilityTestSupport.candidate(
            origin: .focusedElement,
            role: "AXTextArea",
            text: "same readable text"
        )
        let complete = SelectionCompatibilityTestSupport.candidate(
            origin: .hitAncestor(depth: 2),
            role: "AXDocument",
            text: "same readable text",
            rangeLength: 18,
            rangeFingerprint: "400:18",
            bounds: CGRect(x: 500, y: 310, width: 136, height: 18)
        )

        SelectionCompatibilityTestSupport.expect(
            SelectionDetection.bestCandidate(from: [textOnly, complete]) == complete,
            "test_range_and_bounds_candidate_beats_text_only_candidate"
        )
    }
}

enum TestClipboardFallbackAdmission {
    static func test_unknown_roles_allow_real_drag_double_click_and_triple_click_fallback() {
        let dragAllowed = SelectionDetection.allowsClipboardFallback(
            clickCount: 1,
            displacement: CGPoint(x: 24, y: 3),
            pressedRolePath: ["AXGroup", "AXUnknown"],
            releasedRolePath: ["AXGroup", "AXUnknown"]
        )
        let doubleClickAllowed = SelectionDetection.allowsClipboardFallback(
            clickCount: 2,
            displacement: .zero,
            pressedRolePath: ["AXGroup", "AXUnknown"],
            releasedRolePath: ["AXGroup", "AXUnknown"]
        )
        let tripleClickAllowed = SelectionDetection.allowsClipboardFallback(
            clickCount: 3,
            displacement: .zero,
            pressedRolePath: ["AXGroup", "AXUnknown"],
            releasedRolePath: ["AXGroup", "AXUnknown"]
        )

        SelectionCompatibilityTestSupport.expect(
            dragAllowed && doubleClickAllowed && tripleClickAllowed,
            "test_unknown_roles_allow_real_drag_double_click_and_triple_click_fallback"
        )
    }

    static func test_zero_displacement_single_click_rejects_fallback() {
        let isAllowed: Bool = SelectionDetection.allowsClipboardFallback(
            clickCount: 1,
            displacement: .zero,
            pressedRolePath: ["AXGroup", "AXUnknown"],
            releasedRolePath: ["AXGroup", "AXUnknown"]
        )

        SelectionCompatibilityTestSupport.expect(
            isAllowed == false,
            "test_zero_displacement_single_click_rejects_fallback"
        )
    }

    static func test_excluded_control_ancestors_always_reject_fallback() {
        let excludedRoles = [
            "AXScrollBar",
            "AXScrollAreaThumb",
            "AXScrollBarThumb",
            "AXSlider",
            "AXSplitter",
            "AXIncrementor",
            "AXColumnHeader",
            "AXRowHeader",
            "AXRuler",
            "AXResizeHandle",
            "AXColumnResizeHandle",
            "AXRowResizeHandle",
            "AXColumnResizer",
            "AXRowResizer",
            "AXResizer",
            "AXGrowArea",
            "AXWindowResizeHandle",
            "AXToolbarDragArea",
        ]

        for role in excludedRoles {
            let pressedAllowed: Bool = SelectionDetection.allowsClipboardFallback(
                clickCount: 1,
                displacement: CGPoint(x: 32, y: 4),
                pressedRolePath: ["AXStaticText", role],
                releasedRolePath: ["AXUnknown"]
            )
            let releasedAllowed: Bool = SelectionDetection.allowsClipboardFallback(
                clickCount: 2,
                displacement: .zero,
                pressedRolePath: ["AXUnknown"],
                releasedRolePath: ["AXStaticText", role]
            )

            SelectionCompatibilityTestSupport.expect(
                pressedAllowed == false && releasedAllowed == false,
                "test_excluded_control_ancestors_always_reject_fallback[\(role)]"
            )
        }
    }
}

enum TestClipboardFallbackResult {
    static func test_unchanged_clipboard_change_count_rejects_result() {
        let snapshot = SelectionDetection.clipboardOnlySnapshot(
            capture: SelectionCompatibilityTestSupport.capture(before: 80, after: 80),
            sourceApplication: "com.example.FictionalEditor",
            focusedElementIdentity: nil,
            releasePointInQuartz: CGPoint(x: 720, y: 440)
        )

        SelectionCompatibilityTestSupport.expect(
            snapshot == nil,
            "test_unchanged_clipboard_change_count_rejects_result"
        )
    }

    static func test_blank_clipboard_text_rejects_result() {
        let snapshot = SelectionDetection.clipboardOnlySnapshot(
            capture: SelectionCompatibilityTestSupport.capture(text: " \n\t "),
            sourceApplication: "com.example.FictionalEditor",
            focusedElementIdentity: nil,
            releasePointInQuartz: CGPoint(x: 720, y: 440)
        )

        SelectionCompatibilityTestSupport.expect(
            snapshot == nil,
            "test_blank_clipboard_text_rejects_result"
        )
    }

    static func test_file_url_file_list_and_image_types_reject_result_even_with_text() {
        let disallowedTypeSets = [
            ["public.utf8-plain-text", "public.file-url"],
            ["public.utf8-plain-text", "NSFilenamesPboardType"],
            ["public.utf8-plain-text", "public.png"],
            ["public.utf8-plain-text", "public.tiff"],
        ]

        for types in disallowedTypeSets {
            let snapshot = SelectionDetection.clipboardOnlySnapshot(
                capture: SelectionCompatibilityTestSupport.capture(types: types),
                sourceApplication: "com.example.FictionalEditor",
                focusedElementIdentity: nil,
                releasePointInQuartz: CGPoint(x: 720, y: 440)
            )

            SelectionCompatibilityTestSupport.expect(
                snapshot == nil,
                "test_file_url_file_list_and_image_types_reject_result_even_with_text[\(types.last ?? "missing")]"
            )
        }
    }

    static func test_clipboard_only_snapshot_preserves_application_and_release_point() {
        let releasePoint = CGPoint(x: -340, y: 760)
        let snapshot = SelectionCompatibilityTestSupport.clipboardSnapshot(
            text: "  portable selection\n",
            sourceApplication: "com.example.FictionalBrowser",
            focusedElementIdentity: nil,
            releasePoint: releasePoint
        )

        SelectionCompatibilityTestSupport.expect(
            snapshot?.text == "portable selection"
                && snapshot?.sourceApplication == "com.example.FictionalBrowser"
                && snapshot?.focusedElementIdentity == nil
                && snapshot?.rangeFingerprint == nil
                && snapshot?.boundsInQuartz == nil
                && snapshot?.releasePointInQuartz == releasePoint
                && snapshot?.evidenceSource == .clipboardOnly,
            "test_clipboard_only_snapshot_preserves_application_and_release_point"
        )
    }

    static func test_same_clipboard_only_text_and_application_do_not_retrigger() {
        let first = SelectionCompatibilityTestSupport.clipboardSnapshot(
            text: "same portable selection",
            sourceApplication: "com.example.FictionalBrowser",
            focusedElementIdentity: "browser-node-1",
            releasePoint: CGPoint(x: 500, y: 320)
        )
        let repeated = SelectionCompatibilityTestSupport.clipboardSnapshot(
            text: "same portable selection",
            sourceApplication: "com.example.FictionalBrowser",
            focusedElementIdentity: "browser-node-2",
            releasePoint: CGPoint(x: 920, y: 680)
        )
        let otherApplication = SelectionCompatibilityTestSupport.clipboardSnapshot(
            text: "same portable selection",
            sourceApplication: "com.example.OtherApplication",
            focusedElementIdentity: "other-node-1",
            releasePoint: CGPoint(x: 920, y: 680)
        )

        var tracker = SelectionObservationTracker()
        guard let first, let repeated, let otherApplication else {
            SelectionCompatibilityTestSupport.expect(
                false,
                "test_same_clipboard_only_text_and_application_do_not_retrigger"
            )
            return
        }

        let firstRequest = tracker.beginObservation(.mouseRelease(clickCount: 1, displacement: CGPoint(x: 18, y: 2)))
        let firstDecision = tracker.completeObservation(firstRequest, snapshot: first)
        let repeatedRequest = tracker.beginObservation(.mouseRelease(clickCount: 2, displacement: .zero))
        let repeatedDecision = tracker.completeObservation(repeatedRequest, snapshot: repeated)
        let otherApplicationRequest = tracker.beginObservation(.mouseRelease(clickCount: 2, displacement: .zero))
        let otherApplicationDecision = tracker.completeObservation(otherApplicationRequest, snapshot: otherApplication)

        SelectionCompatibilityTestSupport.expect(
            {
                guard case .present = firstDecision,
                      case .unchanged = repeatedDecision,
                      case .present = otherApplicationDecision
                else { return false }
                return true
            }(),
            "test_same_clipboard_only_text_and_application_do_not_retrigger"
        )
    }
}

@main
struct SelectionCompatibilityTestRunner {
    static func main() {
        TestSelectionCandidateRanking.test_hit_candidate_with_selection_beats_empty_focused_candidate()
        TestSelectionCandidateRanking.test_parent_web_area_with_selection_beats_empty_focused_and_hit_candidates()
        TestSelectionCandidateRanking.test_range_and_bounds_candidate_beats_text_only_candidate()

        TestClipboardFallbackAdmission.test_unknown_roles_allow_real_drag_double_click_and_triple_click_fallback()
        TestClipboardFallbackAdmission.test_zero_displacement_single_click_rejects_fallback()
        TestClipboardFallbackAdmission.test_excluded_control_ancestors_always_reject_fallback()

        TestClipboardFallbackResult.test_unchanged_clipboard_change_count_rejects_result()
        TestClipboardFallbackResult.test_blank_clipboard_text_rejects_result()
        TestClipboardFallbackResult.test_file_url_file_list_and_image_types_reject_result_even_with_text()
        TestClipboardFallbackResult.test_clipboard_only_snapshot_preserves_application_and_release_point()
        TestClipboardFallbackResult.test_same_clipboard_only_text_and_application_do_not_retrigger()

        print(
            SelectionCompatibilityTestSupport.failures == 0
                ? "ALL PASS"
                : "\(SelectionCompatibilityTestSupport.failures) FAILURES"
        )
        if SelectionCompatibilityTestSupport.failures > 0 {
            exit(1)
        }
    }
}
