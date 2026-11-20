import Foundation
import CoreGraphics

// Clipboard-only deduplication invalidation regression tests.
// These tests use immutable snapshots and do not access Accessibility or the real pasteboard.
// Run:
//   swiftc -o /tmp/glint_selection_clipboard_dedup_invalidation_test \
//     SelectionDetection.swift selection_clipboard_dedup_invalidation_tests.swift \
//     -framework Foundation -framework CoreGraphics \
//     && /tmp/glint_selection_clipboard_dedup_invalidation_test

enum SelectionClipboardDedupInvalidationTestSupport {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() {
            print("  ok  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
        }
    }

    static func clipboardSnapshot(releaseX: CGFloat) -> SelectionSnapshot {
        SelectionSnapshot(
            text: "repeatable clipboard selection",
            sourceApplication: "com.example.FictionalBrowser",
            focusedElementIdentity: "fictional-browser-node",
            rangeFingerprint: nil,
            boundsInQuartz: nil,
            releasePointInQuartz: CGPoint(x: releaseX, y: 360),
            evidenceSource: .clipboardOnly
        )
    }

    static func accessibilitySnapshot() -> SelectionSnapshot {
        SelectionSnapshot(
            text: "stable accessibility selection",
            sourceApplication: "com.example.FictionalEditor",
            focusedElementIdentity: "fictional-editor-node",
            rangeFingerprint: "40:30",
            boundsInQuartz: CGRect(x: 200, y: 180, width: 210, height: 22),
            releasePointInQuartz: CGPoint(x: 415, y: 204),
            evidenceSource: .accessibility
        )
    }
}

enum TestClipboardOnlyDedupInvalidation {
    static func test_escape_ordinary_key_and_mouse_down_allow_same_clipboard_selection_again() {
        let invalidations: [SelectionDeduplicationInvalidation] = [
            .escape,
            .ordinaryKey,
            .mouseDown,
        ]

        for invalidation in invalidations {
            var tracker = SelectionObservationTracker()
            let firstRequest = tracker.beginObservation(
                .mouseRelease(clickCount: 2, displacement: .zero)
            )
            let firstDecision = tracker.completeObservation(
                firstRequest,
                snapshot: SelectionClipboardDedupInvalidationTestSupport
                    .clipboardSnapshot(releaseX: 420)
            )

            tracker.invalidateClipboardOnlyDeduplication(for: invalidation)

            let repeatedRequest = tracker.beginObservation(
                .mouseRelease(clickCount: 1, displacement: CGPoint(x: 12, y: 0))
            )
            let repeatedDecision = tracker.completeObservation(
                repeatedRequest,
                snapshot: SelectionClipboardDedupInvalidationTestSupport
                    .clipboardSnapshot(releaseX: 780)
            )

            SelectionClipboardDedupInvalidationTestSupport.expect(
                {
                    guard case .present = firstDecision,
                          case .present = repeatedDecision else { return false }
                    return true
                }(),
                "test_escape_ordinary_key_and_mouse_down_allow_same_clipboard_selection_again[\(invalidation)]"
            )
        }
    }

    static func test_clipboard_invalidation_keeps_accessibility_deduplication_baseline() {
        let invalidations: [SelectionDeduplicationInvalidation] = [
            .escape,
            .ordinaryKey,
            .mouseDown,
        ]

        for invalidation in invalidations {
            var tracker = SelectionObservationTracker()
            let snapshot = SelectionClipboardDedupInvalidationTestSupport.accessibilitySnapshot()
            let firstRequest = tracker.beginObservation(
                .mouseRelease(clickCount: 1, displacement: CGPoint(x: 10, y: 0))
            )
            let firstDecision = tracker.completeObservation(firstRequest, snapshot: snapshot)

            tracker.invalidateClipboardOnlyDeduplication(for: invalidation)

            let repeatedRequest = tracker.beginObservation(
                .mouseRelease(clickCount: 2, displacement: .zero)
            )
            let repeatedDecision = tracker.completeObservation(repeatedRequest, snapshot: snapshot)

            SelectionClipboardDedupInvalidationTestSupport.expect(
                {
                    guard case .present = firstDecision,
                          case .unchanged = repeatedDecision else { return false }
                    return true
                }(),
                "test_clipboard_invalidation_keeps_accessibility_deduplication_baseline[\(invalidation)]"
            )
        }
    }
}

@main
enum SelectionClipboardDedupInvalidationTests {
    static func main() {
        TestClipboardOnlyDedupInvalidation
            .test_escape_ordinary_key_and_mouse_down_allow_same_clipboard_selection_again()
        TestClipboardOnlyDedupInvalidation
            .test_clipboard_invalidation_keeps_accessibility_deduplication_baseline()

        print(
            SelectionClipboardDedupInvalidationTestSupport.failures == 0
                ? "ALL PASS"
                : "\(SelectionClipboardDedupInvalidationTestSupport.failures) FAILURES"
        )
        exit(SelectionClipboardDedupInvalidationTestSupport.failures == 0 ? 0 : 1)
    }
}
