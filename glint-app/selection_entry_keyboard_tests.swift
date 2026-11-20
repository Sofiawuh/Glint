import Foundation
import CoreGraphics

// 选区入口键盘事件的纯领域黑盒契约；不创建 CGEvent、事件 Tap 或全局变量。
// 运行：
//   swiftc -o /tmp/glint_selection_entry_keyboard_test \
//     SelectionDetection.swift SelectionEntryLifecycle.swift \
//     SelectionEntryKeyboard.swift selection_entry_keyboard_tests.swift \
//     -framework Foundation -framework CoreGraphics \
//     && /tmp/glint_selection_entry_keyboard_test

enum SelectionEntryKeyboardTestSupport {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() {
            print("  ok  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
        }
    }

    static func snapshot(
        text: String = "selected text",
        rangeFingerprint: String = "40:13"
    ) -> SelectionSnapshot {
        SelectionSnapshot(
            text: text,
            sourceApplication: "com.example.FictionalEditor",
            focusedElementIdentity: "fictional-editor-1",
            rangeFingerprint: rangeFingerprint,
            boundsInQuartz: CGRect(x: 400, y: 240, width: 100, height: 20),
            releasePointInQuartz: CGPoint(x: 505, y: 262)
        )
    }

    static func presentedLifecycle(
        snapshot: SelectionSnapshot = snapshot()
    ) -> SelectionEntryLifecycle {
        var lifecycle = SelectionEntryLifecycle()
        lifecycle.present(
            snapshot,
            pointerInsideContinuousRegion: false
        )
        return lifecycle
    }

    static func probe(
        text: String?,
        rangeFingerprint: String?,
        bounds: CGRect?,
        rangeLength: Int = 16
    ) -> SelectionProbe {
        SelectionProbe(
            text: text,
            sourceApplication: "com.example.FictionalEditor",
            focusedElementIdentity: "fictional-editor-1",
            rangeLength: rangeLength,
            rangeFingerprint: rangeFingerprint,
            boundsInQuartz: bounds,
            releasePointInQuartz: CGPoint(x: 505, y: 262)
        )
    }
}

enum TestSelectionEntryKeyboard {
    static func test_internal_synthetic_copy_is_ignored_without_invalidating_read_or_closing_entry() {
        var gate = SelectionReadGenerationGate()
        let pendingRead = gate.beginRead()
        var lifecycle = SelectionEntryKeyboardTestSupport.presentedLifecycle()
        var revalidationCalls = 0

        let input = SelectionEntryKeyboardInput(
            keyCode: 8,
            sourceUserData: SelectionEntryKeyboardClassifier.internalSyntheticCopySourceUserData
        )
        let decision = SelectionEntryKeyboardHandler.handle(
            input,
            readGate: &gate,
            lifecycle: &lifecycle,
            revalidateSourceAndSelection: {
                revalidationCalls += 1
                return false
            }
        )

        SelectionEntryKeyboardTestSupport.expect(
            SelectionEntryKeyboardClassifier.classify(input) == .ignoreInternalSyntheticCopy
                && decision == .ignoreInternalSyntheticCopy
                && gate.accepts(pendingRead)
                && lifecycle.phase == .marker
                && lifecycle.currentSnapshot?.text == "selected text"
                && revalidationCalls == 0,
            "test_internal_synthetic_copy_is_ignored_without_invalidating_read_or_closing_entry"
        )
    }

    static func test_user_copy_without_internal_marker_is_revalidated_instead_of_ignored() {
        let input = SelectionEntryKeyboardInput(keyCode: 8, sourceUserData: 0)

        SelectionEntryKeyboardTestSupport.expect(
            SelectionEntryKeyboardClassifier.classify(input) == .revalidateSourceAndSelection,
            "test_user_copy_without_internal_marker_is_revalidated_instead_of_ignored"
        )
    }

    static func test_escape_invalidates_pending_read_and_closes_entry() {
        var gate = SelectionReadGenerationGate()
        let pendingRead = gate.beginRead()
        var lifecycle = SelectionEntryKeyboardTestSupport.presentedLifecycle()
        var revalidationCalls = 0

        let input = SelectionEntryKeyboardInput(keyCode: 53, sourceUserData: 0)
        let decision = SelectionEntryKeyboardHandler.handle(
            input,
            readGate: &gate,
            lifecycle: &lifecycle,
            revalidateSourceAndSelection: {
                revalidationCalls += 1
                return true
            }
        )

        SelectionEntryKeyboardTestSupport.expect(
            SelectionEntryKeyboardClassifier.classify(input) == .dismissEntry
                && decision == .dismissEntry
                && !gate.accepts(pendingRead)
                && lifecycle.phase == .hidden
                && lifecycle.currentSnapshot == nil
                && revalidationCalls == 0,
            "test_escape_invalidates_pending_read_and_closes_entry"
        )
    }

    static func test_non_escape_user_key_keeps_entry_when_source_and_selection_revalidate() {
        var gate = SelectionReadGenerationGate()
        let pendingRead = gate.beginRead()
        var lifecycle = SelectionEntryKeyboardTestSupport.presentedLifecycle()
        var revalidationCalls = 0

        let decision = SelectionEntryKeyboardHandler.handle(
            SelectionEntryKeyboardInput(keyCode: 0, sourceUserData: 0),
            readGate: &gate,
            lifecycle: &lifecycle,
            revalidateSourceAndSelection: {
                revalidationCalls += 1
                return true
            }
        )

        SelectionEntryKeyboardTestSupport.expect(
            decision == .revalidateSourceAndSelection
                && !gate.accepts(pendingRead)
                && lifecycle.phase == .marker
                && lifecycle.currentSnapshot?.text == "selected text"
                && revalidationCalls == 1,
            "test_non_escape_user_key_keeps_entry_when_source_and_selection_revalidate"
        )
    }

    static func test_non_escape_user_key_closes_entry_when_source_or_selection_is_invalid() {
        var gate = SelectionReadGenerationGate()
        let pendingRead = gate.beginRead()
        var lifecycle = SelectionEntryKeyboardTestSupport.presentedLifecycle()
        var revalidationCalls = 0

        let decision = SelectionEntryKeyboardHandler.handle(
            SelectionEntryKeyboardInput(keyCode: 49, sourceUserData: 0),
            readGate: &gate,
            lifecycle: &lifecycle,
            revalidateSourceAndSelection: {
                revalidationCalls += 1
                return false
            }
        )

        SelectionEntryKeyboardTestSupport.expect(
            decision == .revalidateSourceAndSelection
                && !gate.accepts(pendingRead)
                && lifecycle.phase == .hidden
                && lifecycle.currentSnapshot == nil
                && revalidationCalls == 1,
            "test_non_escape_user_key_closes_entry_when_source_or_selection_is_invalid"
        )
    }

    static func test_delayed_revalidation_rejects_stale_result_after_new_snapshot_replaces_entry() {
        let original = SelectionEntryKeyboardTestSupport.snapshot(
            text: "original selection",
            rangeFingerprint: "80:18"
        )
        let replacement = SelectionEntryKeyboardTestSupport.snapshot(
            text: "replacement selection",
            rangeFingerprint: "140:21"
        )
        var lifecycle = SelectionEntryKeyboardTestSupport.presentedLifecycle(snapshot: original)
        let request: SelectionEntryKeyboardRevalidationRequest? =
            SelectionEntryKeyboardHandler.beginRevalidation(for: lifecycle)

        lifecycle.present(replacement, pointerInsideContinuousRegion: false)
        let accepted = request.map {
            SelectionEntryKeyboardHandler.completeRevalidation(
                $0,
                sourceAndSelectionAreValid: false,
                lifecycle: &lifecycle
            )
        }

        SelectionEntryKeyboardTestSupport.expect(
            request?.snapshot == original
                && accepted == false
                && lifecycle.phase == .marker
                && lifecycle.currentSnapshot == replacement,
            "test_delayed_revalidation_rejects_stale_result_after_new_snapshot_replaces_entry"
        )
    }

    static func test_delayed_revalidation_keeps_unchanged_snapshot_when_still_valid() {
        let original = SelectionEntryKeyboardTestSupport.snapshot(
            text: "still selected",
            rangeFingerprint: "200:14"
        )
        var lifecycle = SelectionEntryKeyboardTestSupport.presentedLifecycle(snapshot: original)
        let request: SelectionEntryKeyboardRevalidationRequest? =
            SelectionEntryKeyboardHandler.beginRevalidation(for: lifecycle)
        let accepted = request.map {
            SelectionEntryKeyboardHandler.completeRevalidation(
                $0,
                sourceAndSelectionAreValid: true,
                lifecycle: &lifecycle
            )
        }

        SelectionEntryKeyboardTestSupport.expect(
            request?.snapshot == original
                && accepted == true
                && lifecycle.phase == .marker
                && lifecycle.currentSnapshot == original,
            "test_delayed_revalidation_keeps_unchanged_snapshot_when_still_valid"
        )
    }

    static func test_delayed_revalidation_closes_unchanged_snapshot_when_invalid() {
        let original = SelectionEntryKeyboardTestSupport.snapshot(
            text: "no longer selected",
            rangeFingerprint: "240:18"
        )
        var lifecycle = SelectionEntryKeyboardTestSupport.presentedLifecycle(snapshot: original)
        let request: SelectionEntryKeyboardRevalidationRequest? =
            SelectionEntryKeyboardHandler.beginRevalidation(for: lifecycle)
        let accepted = request.map {
            SelectionEntryKeyboardHandler.completeRevalidation(
                $0,
                sourceAndSelectionAreValid: false,
                lifecycle: &lifecycle
            )
        }

        SelectionEntryKeyboardTestSupport.expect(
            request?.snapshot == original
                && accepted == true
                && lifecycle.phase == .hidden
                && lifecycle.currentSnapshot == nil,
            "test_delayed_revalidation_closes_unchanged_snapshot_when_invalid"
        )
    }

    static func test_clipboard_snapshot_matching_probe_keeps_entry_during_user_key_revalidation() {
        let bounds = CGRect(x: 400, y: 240, width: 100, height: 20)
        let selectionEvidence = SelectionEntryKeyboardTestSupport.probe(
            text: nil,
            rangeFingerprint: "320:16",
            bounds: bounds
        )
        let snapshot: SelectionSnapshot? = SelectionDetection.clipboardSnapshot(
            text: "copied selection",
            selectionEvidence: selectionEvidence,
            evidenceChanged: true
        )
        let matchingProbe = SelectionEntryKeyboardTestSupport.probe(
            text: "copied selection",
            rangeFingerprint: "320:16",
            bounds: bounds
        )

        var lifecycle = snapshot.map {
            SelectionEntryKeyboardTestSupport.presentedLifecycle(snapshot: $0)
        } ?? SelectionEntryLifecycle()
        let request = SelectionEntryKeyboardHandler.beginRevalidation(for: lifecycle)
        let isValid = snapshot.map {
            SelectionSourceRevalidation.isValid(snapshot: $0, currentProbe: matchingProbe)
        } ?? false
        let accepted = request.map {
            SelectionEntryKeyboardHandler.completeRevalidation(
                $0,
                sourceAndSelectionAreValid: isValid,
                lifecycle: &lifecycle
            )
        }

        SelectionEntryKeyboardTestSupport.expect(
            SelectionEntryKeyboardClassifier.classify(
                SelectionEntryKeyboardInput(keyCode: 0, sourceUserData: 0)
            ) == .revalidateSourceAndSelection
                && snapshot?.rangeFingerprint == "320:16"
                && snapshot?.boundsInQuartz == bounds
                && isValid
                && accepted == true
                && lifecycle.phase == .marker
                && lifecycle.currentSnapshot == snapshot,
            "test_clipboard_snapshot_matching_probe_keeps_entry_during_user_key_revalidation"
        )
    }

    static func test_clipboard_snapshot_changed_range_or_bounds_closes_entry_during_user_key_revalidation() {
        let bounds = CGRect(x: 400, y: 240, width: 100, height: 20)
        let selectionEvidence = SelectionEntryKeyboardTestSupport.probe(
            text: nil,
            rangeFingerprint: "360:16",
            bounds: bounds
        )
        let snapshot: SelectionSnapshot? = SelectionDetection.clipboardSnapshot(
            text: "copied selection",
            selectionEvidence: selectionEvidence,
            evidenceChanged: true
        )
        let changedRangeProbe = SelectionEntryKeyboardTestSupport.probe(
            text: "copied selection",
            rangeFingerprint: "420:16",
            bounds: bounds
        )
        let changedBoundsProbe = SelectionEntryKeyboardTestSupport.probe(
            text: "copied selection",
            rangeFingerprint: "360:16",
            bounds: bounds.offsetBy(dx: 24, dy: 0)
        )

        var changedRangeLifecycle = snapshot.map {
            SelectionEntryKeyboardTestSupport.presentedLifecycle(snapshot: $0)
        } ?? SelectionEntryLifecycle()
        let changedRangeRequest = SelectionEntryKeyboardHandler.beginRevalidation(
            for: changedRangeLifecycle
        )
        let rangeIsValid = snapshot.map {
            SelectionSourceRevalidation.isValid(snapshot: $0, currentProbe: changedRangeProbe)
        } ?? false
        let rangeAccepted = changedRangeRequest.map {
            SelectionEntryKeyboardHandler.completeRevalidation(
                $0,
                sourceAndSelectionAreValid: rangeIsValid,
                lifecycle: &changedRangeLifecycle
            )
        }

        var changedBoundsLifecycle = snapshot.map {
            SelectionEntryKeyboardTestSupport.presentedLifecycle(snapshot: $0)
        } ?? SelectionEntryLifecycle()
        let changedBoundsRequest = SelectionEntryKeyboardHandler.beginRevalidation(
            for: changedBoundsLifecycle
        )
        let boundsAreValid = snapshot.map {
            SelectionSourceRevalidation.isValid(snapshot: $0, currentProbe: changedBoundsProbe)
        } ?? false
        let boundsAccepted = changedBoundsRequest.map {
            SelectionEntryKeyboardHandler.completeRevalidation(
                $0,
                sourceAndSelectionAreValid: boundsAreValid,
                lifecycle: &changedBoundsLifecycle
            )
        }

        SelectionEntryKeyboardTestSupport.expect(
            !rangeIsValid
                && rangeAccepted == true
                && changedRangeLifecycle.phase == .hidden
                && changedRangeLifecycle.currentSnapshot == nil
                && !boundsAreValid
                && boundsAccepted == true
                && changedBoundsLifecycle.phase == .hidden
                && changedBoundsLifecycle.currentSnapshot == nil,
            "test_clipboard_snapshot_changed_range_or_bounds_closes_entry_during_user_key_revalidation"
        )
    }
}

@main
enum SelectionEntryKeyboardTests {
    static func main() {
        TestSelectionEntryKeyboard.test_internal_synthetic_copy_is_ignored_without_invalidating_read_or_closing_entry()
        TestSelectionEntryKeyboard.test_user_copy_without_internal_marker_is_revalidated_instead_of_ignored()
        TestSelectionEntryKeyboard.test_escape_invalidates_pending_read_and_closes_entry()
        TestSelectionEntryKeyboard.test_non_escape_user_key_keeps_entry_when_source_and_selection_revalidate()
        TestSelectionEntryKeyboard.test_non_escape_user_key_closes_entry_when_source_or_selection_is_invalid()
        TestSelectionEntryKeyboard.test_delayed_revalidation_rejects_stale_result_after_new_snapshot_replaces_entry()
        TestSelectionEntryKeyboard.test_delayed_revalidation_keeps_unchanged_snapshot_when_still_valid()
        TestSelectionEntryKeyboard.test_delayed_revalidation_closes_unchanged_snapshot_when_invalid()
        TestSelectionEntryKeyboard.test_clipboard_snapshot_matching_probe_keeps_entry_during_user_key_revalidation()
        TestSelectionEntryKeyboard.test_clipboard_snapshot_changed_range_or_bounds_closes_entry_during_user_key_revalidation()

        print(
            SelectionEntryKeyboardTestSupport.failures == 0
                ? "ALL PASS"
                : "\(SelectionEntryKeyboardTestSupport.failures) FAILURES"
        )
        exit(SelectionEntryKeyboardTestSupport.failures == 0 ? 0 : 1)
    }
}
