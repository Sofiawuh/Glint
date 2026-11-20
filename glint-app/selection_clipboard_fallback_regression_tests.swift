import Foundation
import CoreGraphics

// Clipboard fallback admission regression tests.
// These tests are pure policy checks and do not access Accessibility or the real pasteboard.
// Run:
//   swiftc -o /tmp/glint_selection_clipboard_fallback_regression_test \
//     SelectionDetection.swift selection_clipboard_fallback_regression_tests.swift \
//     -framework Foundation -framework CoreGraphics \
//     && /tmp/glint_selection_clipboard_fallback_regression_test

enum SelectionClipboardFallbackRegressionTestSupport {
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
        bounds: CGRect?
    ) -> SelectionProbe {
        SelectionProbe(
            text: text,
            sourceApplication: "com.example.FictionalEditor",
            focusedElementIdentity: "fictional-editor-1",
            rangeLength: rangeLength,
            rangeFingerprint: rangeFingerprint,
            boundsInQuartz: bounds,
            releasePointInQuartz: CGPoint(x: 540, y: 320)
        )
    }
}

enum TestClipboardFallbackAdmissionRegression {
    static func test_complete_unchanged_ax_selection_rejects_fallback_for_drag_and_double_click() {
        let bounds = CGRect(x: 200, y: 160, width: 144, height: 22)
        let before = SelectionClipboardFallbackRegressionTestSupport.probe(
            text: "already selected",
            rangeLength: 16,
            rangeFingerprint: "80:16",
            bounds: bounds
        )
        let after = SelectionClipboardFallbackRegressionTestSupport.probe(
            text: "already selected",
            rangeLength: 16,
            rangeFingerprint: "80:16",
            bounds: bounds
        )
        let outcome = SelectionDetection.evaluate(
            before: before,
            after: after,
            pressedRolePath: ["AXTextArea"],
            releasedRolePath: ["AXTextArea"]
        )

        let dragAllowed = SelectionDetection.shouldAttemptClipboardFallback(
            outcome: outcome,
            clickCount: 1,
            displacement: CGPoint(x: 8, y: 0),
            pressedRolePath: ["AXTextArea"],
            releasedRolePath: ["AXTextArea"]
        )
        let doubleClickAllowed = SelectionDetection.shouldAttemptClipboardFallback(
            outcome: outcome,
            clickCount: 2,
            displacement: .zero,
            pressedRolePath: ["AXTextArea"],
            releasedRolePath: ["AXTextArea"]
        )

        SelectionClipboardFallbackRegressionTestSupport.expect(
            outcome == .ignored && !dragAllowed && !doubleClickAllowed,
            "test_complete_unchanged_ax_selection_rejects_fallback_for_drag_and_double_click"
        )
    }

    static func test_missing_or_incomplete_ax_evidence_allows_fallback_only_for_clear_gestures() {
        let missingEvidence = SelectionClipboardFallbackRegressionTestSupport.probe(
            text: nil,
            rangeLength: nil,
            rangeFingerprint: nil,
            bounds: nil
        )
        let incompleteEvidence = SelectionClipboardFallbackRegressionTestSupport.probe(
            text: "text without range evidence",
            rangeLength: nil,
            rangeFingerprint: nil,
            bounds: nil
        )
        let missingOutcome = SelectionDetection.evaluate(
            before: nil,
            after: missingEvidence,
            pressedRolePath: ["AXTextArea"],
            releasedRolePath: ["AXTextArea"]
        )
        let incompleteOutcome = SelectionDetection.evaluate(
            before: nil,
            after: incompleteEvidence,
            pressedRolePath: ["AXTextArea"],
            releasedRolePath: ["AXTextArea"]
        )

        let singleClickAllowed = SelectionDetection.shouldAttemptClipboardFallback(
            outcome: missingOutcome,
            clickCount: 1,
            displacement: .zero,
            pressedRolePath: ["AXTextArea"],
            releasedRolePath: ["AXTextArea"]
        )
        let dragAllowed = SelectionDetection.shouldAttemptClipboardFallback(
            outcome: missingOutcome,
            clickCount: 1,
            displacement: CGPoint(x: 4, y: 0),
            pressedRolePath: ["AXTextArea"],
            releasedRolePath: ["AXTextArea"]
        )
        let doubleClickAllowed = SelectionDetection.shouldAttemptClipboardFallback(
            outcome: incompleteOutcome,
            clickCount: 2,
            displacement: .zero,
            pressedRolePath: ["AXTextArea"],
            releasedRolePath: ["AXTextArea"]
        )

        SelectionClipboardFallbackRegressionTestSupport.expect(
            missingOutcome == .clipboardFallbackEligible
                && incompleteOutcome == .clipboardFallbackEligible
                && !singleClickAllowed
                && dragAllowed
                && doubleClickAllowed,
            "test_missing_or_incomplete_ax_evidence_allows_fallback_only_for_clear_gestures"
        )
    }

    static func test_unknown_role_path_with_missing_ax_evidence_allows_only_clear_gestures() {
        let missingEvidence = SelectionClipboardFallbackRegressionTestSupport.probe(
            text: nil,
            rangeLength: nil,
            rangeFingerprint: nil,
            bounds: nil
        )
        let rolePath = ["AXGroup", "AXUnknown"]
        let outcome = SelectionDetection.evaluate(
            before: nil,
            after: missingEvidence,
            pressedRolePath: rolePath,
            releasedRolePath: rolePath
        )

        let singleClickAllowed = SelectionDetection.shouldAttemptClipboardFallback(
            outcome: outcome,
            clickCount: 1,
            displacement: .zero,
            pressedRolePath: rolePath,
            releasedRolePath: rolePath
        )
        let dragAllowed = SelectionDetection.shouldAttemptClipboardFallback(
            outcome: outcome,
            clickCount: 1,
            displacement: CGPoint(x: 4, y: 0),
            pressedRolePath: rolePath,
            releasedRolePath: rolePath
        )
        let doubleClickAllowed = SelectionDetection.shouldAttemptClipboardFallback(
            outcome: outcome,
            clickCount: 2,
            displacement: .zero,
            pressedRolePath: rolePath,
            releasedRolePath: rolePath
        )

        SelectionClipboardFallbackRegressionTestSupport.expect(
            outcome == .clipboardFallbackEligible
                && !singleClickAllowed
                && dragAllowed
                && doubleClickAllowed,
            "test_unknown_role_path_with_missing_ax_evidence_allows_only_clear_gestures"
        )
    }

    static func test_explicit_nontext_control_with_missing_ax_evidence_remains_ignored() {
        let missingEvidence = SelectionClipboardFallbackRegressionTestSupport.probe(
            text: nil,
            rangeLength: nil,
            rangeFingerprint: nil,
            bounds: nil
        )
        let outcome = SelectionDetection.evaluate(
            before: nil,
            after: missingEvidence,
            pressedRolePath: ["AXButton"],
            releasedRolePath: ["AXButton"]
        )
        let doubleClickAllowed = SelectionDetection.shouldAttemptClipboardFallback(
            outcome: outcome,
            clickCount: 2,
            displacement: .zero,
            pressedRolePath: ["AXButton"],
            releasedRolePath: ["AXButton"]
        )

        SelectionClipboardFallbackRegressionTestSupport.expect(
            outcome == .ignored && !doubleClickAllowed,
            "test_explicit_nontext_control_with_missing_ax_evidence_remains_ignored"
        )
    }
}

@main
enum SelectionClipboardFallbackRegressionTests {
    static func main() {
        TestClipboardFallbackAdmissionRegression
            .test_complete_unchanged_ax_selection_rejects_fallback_for_drag_and_double_click()
        TestClipboardFallbackAdmissionRegression
            .test_missing_or_incomplete_ax_evidence_allows_fallback_only_for_clear_gestures()
        TestClipboardFallbackAdmissionRegression
            .test_unknown_role_path_with_missing_ax_evidence_allows_only_clear_gestures()
        TestClipboardFallbackAdmissionRegression
            .test_explicit_nontext_control_with_missing_ax_evidence_remains_ignored()

        print(
            SelectionClipboardFallbackRegressionTestSupport.failures == 0
                ? "ALL PASS"
                : "\(SelectionClipboardFallbackRegressionTestSupport.failures) FAILURES"
        )
        exit(SelectionClipboardFallbackRegressionTestSupport.failures == 0 ? 0 : 1)
    }
}
