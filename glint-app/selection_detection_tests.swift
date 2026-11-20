import Foundation
import CoreGraphics

// SelectionDetection.swift 的黑盒契约测试（不读取真实 AX 元素、剪贴板或用户配置）。
// 运行：
//   swiftc -o /tmp/glint_selection_detection_test \
//     SelectionDetection.swift selection_detection_tests.swift \
//     -framework Foundation -framework CoreGraphics \
//     && /tmp/glint_selection_detection_test

enum SelectionDetectionTestSupport {
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
        rangeLength: Int?,
        rangeFingerprint: String?,
        bounds: CGRect?,
        releasePoint: CGPoint = CGPoint(x: 640, y: 360)
    ) -> SelectionProbe {
        SelectionProbe(
            text: text,
            sourceApplication: "com.example.FictionalEditor",
            focusedElementIdentity: "fictional-editor-1",
            rangeLength: rangeLength,
            rangeFingerprint: rangeFingerprint,
            boundsInQuartz: bounds,
            releasePointInQuartz: releasePoint
        )
    }

    static func evaluate(
        before: SelectionProbe?,
        after: SelectionProbe,
        pressedRolePath: [String] = ["AXTextArea"],
        releasedRolePath: [String] = ["AXTextArea"]
    ) -> SelectionDetectionOutcome {
        SelectionDetection.evaluate(
            before: before,
            after: after,
            pressedRolePath: pressedRolePath,
            releasedRolePath: releasedRolePath
        )
    }
}

enum TestSelectionDetection {
    static func test_new_nonempty_range_accepts_trimmed_snapshot_without_clipboard_fallback() {
        let before = SelectionDetectionTestSupport.probe(
            text: "old",
            rangeLength: 3,
            rangeFingerprint: "12:3",
            bounds: CGRect(x: 100, y: 200, width: 30, height: 18)
        )
        let afterBounds = CGRect(x: 180, y: 220, width: 96, height: 36)
        let after = SelectionDetectionTestSupport.probe(
            text: "  selected words\n",
            rangeLength: 17,
            rangeFingerprint: "28:17",
            bounds: afterBounds,
            releasePoint: CGPoint(x: 281, y: 258)
        )

        let outcome = SelectionDetectionTestSupport.evaluate(before: before, after: after)
        if case let .accepted(snapshot) = outcome {
            SelectionDetectionTestSupport.expect(
                snapshot.text == "selected words"
                    && snapshot.sourceApplication == "com.example.FictionalEditor"
                    && snapshot.focusedElementIdentity == "fictional-editor-1"
                    && snapshot.rangeFingerprint == "28:17"
                    && snapshot.boundsInQuartz == afterBounds
                    && snapshot.releasePointInQuartz == CGPoint(x: 281, y: 258),
                "test_new_nonempty_range_accepts_trimmed_snapshot_without_clipboard_fallback"
            )
        } else {
            SelectionDetectionTestSupport.expect(
                false,
                "test_new_nonempty_range_accepts_trimmed_snapshot_without_clipboard_fallback"
            )
        }
    }

    static func test_empty_whitespace_or_zero_length_selection_is_ignored() {
        let old = SelectionDetectionTestSupport.probe(
            text: nil,
            rangeLength: nil,
            rangeFingerprint: nil,
            bounds: nil
        )
        let empty = SelectionDetectionTestSupport.probe(
            text: " \n\t ",
            rangeLength: 4,
            rangeFingerprint: "4:4",
            bounds: CGRect(x: 20, y: 40, width: 30, height: 18)
        )
        let zeroLength = SelectionDetectionTestSupport.probe(
            text: "stale text",
            rangeLength: 0,
            rangeFingerprint: "40:0",
            bounds: CGRect(x: 70, y: 90, width: 1, height: 18)
        )

        SelectionDetectionTestSupport.expect(
            SelectionDetectionTestSupport.evaluate(before: old, after: empty) == .ignored
                && SelectionDetectionTestSupport.evaluate(before: old, after: zeroLength) == .ignored,
            "test_empty_whitespace_or_zero_length_selection_is_ignored"
        )
    }

    static func test_unchanged_old_selection_is_not_retriggered_by_release_point_motion() {
        let bounds = CGRect(x: 410, y: 260, width: 120, height: 20)
        let before = SelectionDetectionTestSupport.probe(
            text: "unchanged",
            rangeLength: 9,
            rangeFingerprint: "90:9",
            bounds: bounds,
            releasePoint: CGPoint(x: 525, y: 278)
        )
        let after = SelectionDetectionTestSupport.probe(
            text: "unchanged",
            rangeLength: 9,
            rangeFingerprint: "90:9",
            bounds: bounds,
            releasePoint: CGPoint(x: 1200, y: 278)
        )

        SelectionDetectionTestSupport.expect(
            SelectionDetectionTestSupport.evaluate(before: before, after: after) == .ignored,
            "test_unchanged_old_selection_is_not_retriggered_by_release_point_motion"
        )
    }

    static func test_changed_range_is_accepted_even_when_selected_text_is_identical() {
        let before = SelectionDetectionTestSupport.probe(
            text: "repeat",
            rangeLength: 6,
            rangeFingerprint: "10:6",
            bounds: CGRect(x: 100, y: 100, width: 45, height: 18)
        )
        let after = SelectionDetectionTestSupport.probe(
            text: "repeat",
            rangeLength: 6,
            rangeFingerprint: "60:6",
            bounds: CGRect(x: 500, y: 100, width: 45, height: 18)
        )

        let outcome = SelectionDetectionTestSupport.evaluate(before: before, after: after)
        SelectionDetectionTestSupport.expect(
            {
                if case let .accepted(snapshot) = outcome {
                    return snapshot.rangeFingerprint == "60:6"
                }
                return false
            }(),
            "test_changed_range_is_accepted_even_when_selected_text_is_identical"
        )
    }

    static func test_excluded_control_roles_and_ancestors_never_accept_or_request_copy() {
        let excludedRoles = [
            "AXScrollBar",
            "AXSlider",
            "AXSplitter",
            "AXIncrementor",
            "AXColumnHeader",
            "AXRowHeader",
            "AXRuler",
            "AXResizeHandle",
            "AXColumnResizer",
            "AXRowResizer",
        ]
        let validText = SelectionDetectionTestSupport.probe(
            text: "must not surface",
            rangeLength: 16,
            rangeFingerprint: "20:16",
            bounds: CGRect(x: 300, y: 400, width: 120, height: 20)
        )
        let unavailableText = SelectionDetectionTestSupport.probe(
            text: nil,
            rangeLength: nil,
            rangeFingerprint: nil,
            bounds: nil
        )

        for role in excludedRoles {
            let pressedAncestorOutcome = SelectionDetectionTestSupport.evaluate(
                before: nil,
                after: validText,
                pressedRolePath: ["AXStaticText", role],
                releasedRolePath: ["AXTextArea"]
            )
            let releasedAncestorOutcome = SelectionDetectionTestSupport.evaluate(
                before: nil,
                after: unavailableText,
                pressedRolePath: ["AXTextArea"],
                releasedRolePath: ["AXStaticText", role]
            )
            SelectionDetectionTestSupport.expect(
                pressedAncestorOutcome == .ignored && releasedAncestorOutcome == .ignored,
                "test_excluded_control_roles_and_ancestors_never_accept_or_request_copy[\(role)]"
            )
        }
    }

    static func test_clipboard_fallback_is_only_eligible_for_unavailable_ax_text_on_text_roles() {
        let unavailableText = SelectionDetectionTestSupport.probe(
            text: nil,
            rangeLength: nil,
            rangeFingerprint: nil,
            bounds: nil
        )
        let blankText = SelectionDetectionTestSupport.probe(
            text: "   ",
            rangeLength: nil,
            rangeFingerprint: nil,
            bounds: nil
        )

        let textRole = SelectionDetectionTestSupport.evaluate(before: nil, after: unavailableText)
        let nonTextRole = SelectionDetectionTestSupport.evaluate(
            before: nil,
            after: unavailableText,
            pressedRolePath: ["AXButton"],
            releasedRolePath: ["AXButton"]
        )
        let knownBlankSelection = SelectionDetectionTestSupport.evaluate(before: nil, after: blankText)

        SelectionDetectionTestSupport.expect(
            textRole == .clipboardFallbackEligible
                && nonTextRole == .ignored
                && knownBlankSelection == .ignored,
            "test_clipboard_fallback_is_only_eligible_for_unavailable_ax_text_on_text_roles"
        )
    }

    static func test_clipboard_fallback_rejects_nonempty_copy_without_selection_change_evidence() {
        let unavailableText = SelectionDetectionTestSupport.probe(
            text: nil,
            rangeLength: nil,
            rangeFingerprint: nil,
            bounds: nil
        )
        let eligibility = SelectionDetectionTestSupport.evaluate(
            before: nil,
            after: unavailableText,
            pressedRolePath: ["AXTextArea"],
            releasedRolePath: ["AXTextArea"]
        )
        let snapshot: SelectionSnapshot? = SelectionDetection.clipboardSnapshot(
            text: "copied but unproven",
            selectionEvidence: unavailableText,
            evidenceChanged: false
        )

        SelectionDetectionTestSupport.expect(
            eligibility == .clipboardFallbackEligible && snapshot == nil,
            "test_clipboard_fallback_rejects_nonempty_copy_without_selection_change_evidence"
        )
    }

    static func test_clipboard_fallback_accepts_nonempty_copy_with_explicit_selection_change_evidence() {
        let before = SelectionDetectionTestSupport.probe(
            text: nil,
            rangeLength: 0,
            rangeFingerprint: "40:0",
            bounds: nil
        )
        let releasePoint = CGPoint(x: 420, y: 330)
        let afterBounds = CGRect(x: 300, y: 280, width: 116, height: 36)
        let after = SelectionDetectionTestSupport.probe(
            text: nil,
            rangeLength: 16,
            rangeFingerprint: "80:16",
            bounds: afterBounds,
            releasePoint: releasePoint
        )
        let evidenceChanged = SelectionDetection.reliableSelectionEvidenceChanged(
            before: before,
            after: after
        )
        let snapshot: SelectionSnapshot? = SelectionDetection.clipboardSnapshot(
            text: "  copied selection\n",
            selectionEvidence: after,
            evidenceChanged: evidenceChanged
        )

        SelectionDetectionTestSupport.expect(
            evidenceChanged
                && snapshot?.text == "copied selection"
                && snapshot?.sourceApplication == "com.example.FictionalEditor"
                && snapshot?.focusedElementIdentity == "fictional-editor-1"
                && snapshot?.rangeFingerprint == "80:16"
                && snapshot?.boundsInQuartz == afterBounds
                && snapshot?.releasePointInQuartz == releasePoint,
            "test_clipboard_fallback_accepts_nonempty_copy_with_explicit_selection_change_evidence"
        )
    }

    static func test_clipboard_fallback_preserves_whichever_range_or_bounds_evidence_is_available() {
        let rangeOnlyEvidence = SelectionDetectionTestSupport.probe(
            text: nil,
            rangeLength: 12,
            rangeFingerprint: "120:12",
            bounds: nil
        )
        let boundsOnlyRect = CGRect(x: 520, y: 300, width: 84, height: 18)
        let boundsOnlyEvidence = SelectionDetectionTestSupport.probe(
            text: nil,
            rangeLength: 12,
            rangeFingerprint: nil,
            bounds: boundsOnlyRect
        )

        let rangeOnlySnapshot: SelectionSnapshot? = SelectionDetection.clipboardSnapshot(
            text: "range evidence",
            selectionEvidence: rangeOnlyEvidence,
            evidenceChanged: true
        )
        let boundsOnlySnapshot: SelectionSnapshot? = SelectionDetection.clipboardSnapshot(
            text: "bounds evidence",
            selectionEvidence: boundsOnlyEvidence,
            evidenceChanged: true
        )

        SelectionDetectionTestSupport.expect(
            rangeOnlySnapshot?.rangeFingerprint == "120:12"
                && rangeOnlySnapshot?.boundsInQuartz == nil
                && boundsOnlySnapshot?.rangeFingerprint == nil
                && boundsOnlySnapshot?.boundsInQuartz == boundsOnlyRect,
            "test_clipboard_fallback_preserves_whichever_range_or_bounds_evidence_is_available"
        )
    }

    static func test_ax_text_without_bounds_uses_release_point_after_selection_change() {
        let before = SelectionDetectionTestSupport.probe(
            text: "before",
            rangeLength: 6,
            rangeFingerprint: "2:6",
            bounds: nil
        )
        let releasePoint = CGPoint(x: -320, y: 740)
        let after = SelectionDetectionTestSupport.probe(
            text: "after",
            rangeLength: 5,
            rangeFingerprint: "20:5",
            bounds: nil,
            releasePoint: releasePoint
        )

        let outcome = SelectionDetectionTestSupport.evaluate(before: before, after: after)
        SelectionDetectionTestSupport.expect(
            {
                if case let .accepted(snapshot) = outcome {
                    return snapshot.boundsInQuartz == nil
                        && snapshot.releasePointInQuartz == releasePoint
                }
                return false
            }(),
            "test_ax_text_without_bounds_uses_release_point_after_selection_change"
        )
    }

    static func test_matching_application_and_focused_element_keep_presented_snapshot_valid() {
        let snapshot = SelectionSnapshot(
            text: "still selected",
            sourceApplication: "com.example.FictionalEditor",
            focusedElementIdentity: "fictional-editor-1",
            rangeFingerprint: "240:14",
            boundsInQuartz: CGRect(x: 220, y: 180, width: 105, height: 18),
            releasePointInQuartz: CGPoint(x: 330, y: 200)
        )
        let currentSource = SelectionSourceIdentity(
            sourceApplication: "com.example.FictionalEditor",
            focusedElementIdentity: "fictional-editor-1"
        )

        SelectionDetectionTestSupport.expect(
            SelectionSourceRevalidation.isValid(snapshot: snapshot, currentSource: currentSource),
            "test_matching_application_and_focused_element_keep_presented_snapshot_valid"
        )
    }

    static func test_changed_frontmost_application_invalidates_presented_snapshot() {
        let snapshot = SelectionSnapshot(
            text: "app changed",
            sourceApplication: "com.example.FictionalEditor",
            focusedElementIdentity: "fictional-editor-1",
            rangeFingerprint: "260:11",
            boundsInQuartz: CGRect(x: 240, y: 200, width: 90, height: 18),
            releasePointInQuartz: CGPoint(x: 335, y: 220)
        )
        let currentSource = SelectionSourceIdentity(
            sourceApplication: "com.example.OtherApplication",
            focusedElementIdentity: "fictional-editor-1"
        )

        SelectionDetectionTestSupport.expect(
            !SelectionSourceRevalidation.isValid(snapshot: snapshot, currentSource: currentSource),
            "test_changed_frontmost_application_invalidates_presented_snapshot"
        )
    }

    static func test_changed_focused_element_invalidates_presented_snapshot() {
        let snapshot = SelectionSnapshot(
            text: "focus changed",
            sourceApplication: "com.example.FictionalEditor",
            focusedElementIdentity: "fictional-editor-1",
            rangeFingerprint: "280:13",
            boundsInQuartz: CGRect(x: 260, y: 220, width: 96, height: 18),
            releasePointInQuartz: CGPoint(x: 360, y: 240)
        )
        let currentSource = SelectionSourceIdentity(
            sourceApplication: "com.example.FictionalEditor",
            focusedElementIdentity: "fictional-editor-2"
        )

        SelectionDetectionTestSupport.expect(
            !SelectionSourceRevalidation.isValid(snapshot: snapshot, currentSource: currentSource),
            "test_changed_focused_element_invalidates_presented_snapshot"
        )
    }

    static func test_mouse_release_observes_new_selection_without_movement_threshold() {
        var tracker = SelectionObservationTracker()
        let clickCounts = [1, 2, 3]
        var acceptedFingerprints: [String] = []

        for clickCount in clickCounts {
            let fingerprint = "\(clickCount * 100):\(clickCount + 3)"
            let request = tracker.beginObservation(
                .mouseRelease(clickCount: clickCount, displacement: .zero)
            )
            let decision = tracker.completeObservation(
                request,
                probe: SelectionDetectionTestSupport.probe(
                    text: clickCount == 1 ? "drag selection" : (clickCount == 2 ? "word" : "paragraph"),
                    rangeLength: clickCount + 3,
                    rangeFingerprint: fingerprint,
                    bounds: CGRect(x: 200 + clickCount * 80, y: 260, width: 72, height: 22)
                )
            )

            if case let .present(snapshot) = decision {
                acceptedFingerprints.append(snapshot.rangeFingerprint ?? "")
            }
        }

        SelectionDetectionTestSupport.expect(
            acceptedFingerprints == ["100:4", "200:5", "300:6"],
            "test_mouse_release_observes_new_selection_without_movement_threshold"
        )
    }

    static func test_keyboard_extension_and_select_all_present_only_changed_selection() {
        var tracker = SelectionObservationTracker()
        let extended = SelectionDetectionTestSupport.probe(
            text: "extended",
            rangeLength: 8,
            rangeFingerprint: "40:8",
            bounds: CGRect(x: 300, y: 220, width: 80, height: 20)
        )
        let selectedAll = SelectionDetectionTestSupport.probe(
            text: "selected all text",
            rangeLength: 17,
            rangeFingerprint: "0:17",
            bounds: CGRect(x: 120, y: 160, width: 520, height: 360)
        )

        let extensionRequest = tracker.beginObservation(.keyboardSelection(.extendSelection))
        let extensionDecision = tracker.completeObservation(extensionRequest, probe: extended)
        let unchangedRequest = tracker.beginObservation(.keyboardSelection(.extendSelection))
        let unchangedDecision = tracker.completeObservation(unchangedRequest, probe: extended)
        let selectAllRequest = tracker.beginObservation(.keyboardSelection(.selectAll))
        let selectAllDecision = tracker.completeObservation(selectAllRequest, probe: selectedAll)

        SelectionDetectionTestSupport.expect(
            {
                guard case let .present(extensionSnapshot) = extensionDecision,
                      case .unchanged = unchangedDecision,
                      case let .present(selectAllSnapshot) = selectAllDecision
                else { return false }
                return extensionSnapshot.rangeFingerprint == "40:8"
                    && selectAllSnapshot.rangeFingerprint == "0:17"
            }(),
            "test_keyboard_extension_and_select_all_present_only_changed_selection"
        )
    }

    static func test_keyboard_empty_or_zero_range_clears_stable_selection() {
        let selected = SelectionDetectionTestSupport.probe(
            text: "selected",
            rangeLength: 8,
            rangeFingerprint: "90:8",
            bounds: CGRect(x: 480, y: 260, width: 76, height: 20)
        )
        let empty = SelectionDetectionTestSupport.probe(
            text: " \n ",
            rangeLength: 3,
            rangeFingerprint: "90:3",
            bounds: CGRect(x: 480, y: 260, width: 20, height: 20)
        )
        let zeroRange = SelectionDetectionTestSupport.probe(
            text: "stale selected text",
            rangeLength: 0,
            rangeFingerprint: "90:0",
            bounds: CGRect(x: 480, y: 260, width: 1, height: 20)
        )

        var emptyTracker = SelectionObservationTracker()
        let initialEmptyTrackerRequest = emptyTracker.beginObservation(
            .keyboardSelection(.extendSelection)
        )
        _ = emptyTracker.completeObservation(initialEmptyTrackerRequest, probe: selected)
        let emptyRequest = emptyTracker.beginObservation(.keyboardSelection(.extendSelection))
        let emptyDecision = emptyTracker.completeObservation(emptyRequest, probe: empty)

        var zeroTracker = SelectionObservationTracker()
        let initialZeroTrackerRequest = zeroTracker.beginObservation(
            .keyboardSelection(.selectAll)
        )
        _ = zeroTracker.completeObservation(initialZeroTrackerRequest, probe: selected)
        let zeroRequest = zeroTracker.beginObservation(.keyboardSelection(.extendSelection))
        let zeroDecision = zeroTracker.completeObservation(zeroRequest, probe: zeroRange)

        SelectionDetectionTestSupport.expect(
            {
                guard case .clear = emptyDecision, case .clear = zeroDecision else { return false }
                return emptyTracker.stableSelection == nil && zeroTracker.stableSelection == nil
            }(),
            "test_keyboard_empty_or_zero_range_clears_stable_selection"
        )
    }

    static func test_late_observation_cannot_replace_newer_stable_selection() {
        var tracker = SelectionObservationTracker()
        let oldRequest = tracker.beginObservation(
            .mouseRelease(clickCount: 2, displacement: .zero)
        )
        let newRequest = tracker.beginObservation(
            .keyboardSelection(.selectAll)
        )
        let newProbe = SelectionDetectionTestSupport.probe(
            text: "new selection",
            rangeLength: 13,
            rangeFingerprint: "200:13",
            bounds: CGRect(x: 600, y: 220, width: 120, height: 20)
        )
        let oldProbe = SelectionDetectionTestSupport.probe(
            text: "old selection",
            rangeLength: 13,
            rangeFingerprint: "20:13",
            bounds: CGRect(x: 200, y: 220, width: 120, height: 20)
        )

        let newDecision = tracker.completeObservation(newRequest, probe: newProbe)
        let staleDecision = tracker.completeObservation(oldRequest, probe: oldProbe)

        SelectionDetectionTestSupport.expect(
            {
                guard case let .present(snapshot) = newDecision,
                      case .stale = staleDecision
                else { return false }
                return snapshot.rangeFingerprint == "200:13"
                    && tracker.stableSelection?.rangeFingerprint == "200:13"
            }(),
            "test_late_observation_cannot_replace_newer_stable_selection"
        )
    }
}

@main
enum SelectionDetectionTests {
    static func main() {
        TestSelectionDetection.test_new_nonempty_range_accepts_trimmed_snapshot_without_clipboard_fallback()
        TestSelectionDetection.test_empty_whitespace_or_zero_length_selection_is_ignored()
        TestSelectionDetection.test_unchanged_old_selection_is_not_retriggered_by_release_point_motion()
        TestSelectionDetection.test_changed_range_is_accepted_even_when_selected_text_is_identical()
        TestSelectionDetection.test_excluded_control_roles_and_ancestors_never_accept_or_request_copy()
        TestSelectionDetection.test_clipboard_fallback_is_only_eligible_for_unavailable_ax_text_on_text_roles()
        TestSelectionDetection.test_clipboard_fallback_rejects_nonempty_copy_without_selection_change_evidence()
        TestSelectionDetection.test_clipboard_fallback_accepts_nonempty_copy_with_explicit_selection_change_evidence()
        TestSelectionDetection.test_clipboard_fallback_preserves_whichever_range_or_bounds_evidence_is_available()
        TestSelectionDetection.test_ax_text_without_bounds_uses_release_point_after_selection_change()
        TestSelectionDetection.test_matching_application_and_focused_element_keep_presented_snapshot_valid()
        TestSelectionDetection.test_changed_frontmost_application_invalidates_presented_snapshot()
        TestSelectionDetection.test_changed_focused_element_invalidates_presented_snapshot()
        TestSelectionDetection.test_mouse_release_observes_new_selection_without_movement_threshold()
        TestSelectionDetection.test_keyboard_extension_and_select_all_present_only_changed_selection()
        TestSelectionDetection.test_keyboard_empty_or_zero_range_clears_stable_selection()
        TestSelectionDetection.test_late_observation_cannot_replace_newer_stable_selection()

        print(
            SelectionDetectionTestSupport.failures == 0
                ? "ALL PASS"
                : "\(SelectionDetectionTestSupport.failures) FAILURES"
        )
        exit(SelectionDetectionTestSupport.failures == 0 ? 0 : 1)
    }
}
