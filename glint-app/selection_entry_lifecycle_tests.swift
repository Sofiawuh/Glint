import Foundation
import CoreGraphics

// SelectionEntryLifecycle.swift 的纯状态机黑盒契约测试；不创建 NSPanel 或真实计时器。
// 运行：
//   swiftc -o /tmp/glint_selection_entry_lifecycle_test \
//     SelectionDetection.swift SelectionEntryLifecycle.swift \
//     selection_entry_lifecycle_tests.swift \
//     -framework Foundation -framework CoreGraphics \
//     && /tmp/glint_selection_entry_lifecycle_test

enum SelectionEntryLifecycleTestSupport {
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
        text: String,
        rangeFingerprint: String,
        releasePoint: CGPoint = CGPoint(x: 500, y: 300)
    ) -> SelectionSnapshot {
        SelectionSnapshot(
            text: text,
            sourceApplication: "com.example.FictionalEditor",
            focusedElementIdentity: "fictional-editor-1",
            rangeFingerprint: rangeFingerprint,
            boundsInQuartz: CGRect(x: 420, y: 240, width: 90, height: 36),
            releasePointInQuartz: releasePoint
        )
    }
}

enum TestSelectionEntryLifecycle {
    static func test_external_click_before_read_completion_invalidates_pending_selection_result() {
        var gate = SelectionReadGenerationGate()
        let pendingRead = gate.beginRead()

        gate.invalidate()

        SelectionEntryLifecycleTestSupport.expect(
            !gate.accepts(pendingRead),
            "test_external_click_before_read_completion_invalidates_pending_selection_result"
        )
    }

    static func test_escape_before_read_completion_invalidates_pending_selection_result() {
        var gate = SelectionReadGenerationGate()
        let pendingRead = gate.beginRead()

        gate.invalidate()

        SelectionEntryLifecycleTestSupport.expect(
            !gate.accepts(pendingRead),
            "test_escape_before_read_completion_invalidates_pending_selection_result"
        )
    }

    static func test_second_selection_supersedes_first_read_and_only_latest_result_is_accepted() {
        var gate = SelectionReadGenerationGate()
        let firstRead = gate.beginRead()
        let secondRead = gate.beginRead()

        SelectionEntryLifecycleTestSupport.expect(
            !gate.accepts(firstRead) && gate.accepts(secondRead),
            "test_second_selection_supersedes_first_read_and_only_latest_result_is_accepted"
        )
    }

    static func test_initial_marker_under_pointer_does_not_automatically_begin_hover() {
        var lifecycle = SelectionEntryLifecycle()
        lifecycle.present(
            SelectionEntryLifecycleTestSupport.snapshot(text: "first", rangeFingerprint: "10:5"),
            pointerInsideContinuousRegion: true
        )

        let request = lifecycle.pointerMoved(isInsideContinuousRegion: true)
        SelectionEntryLifecycleTestSupport.expect(
            lifecycle.phase == .marker && request == nil,
            "test_initial_marker_under_pointer_does_not_automatically_begin_hover"
        )
    }

    static func test_explicit_outside_to_inside_movement_schedules_180ms_and_expands() {
        var lifecycle = SelectionEntryLifecycle()
        lifecycle.present(
            SelectionEntryLifecycleTestSupport.snapshot(text: "hover", rangeFingerprint: "20:5"),
            pointerInsideContinuousRegion: true
        )

        _ = lifecycle.pointerMoved(isInsideContinuousRegion: false)
        let request = lifecycle.pointerMoved(isInsideContinuousRegion: true)
        let isCorrectRequest = request?.kind == .expand && request?.delayMilliseconds == 180
        if let request {
            lifecycle.timerFired(request.token)
        }

        SelectionEntryLifecycleTestSupport.expect(
            isCorrectRequest && lifecycle.phase == .expanded,
            "test_explicit_outside_to_inside_movement_schedules_180ms_and_expands"
        )
    }

    static func test_quick_pass_under_180ms_cancels_pending_expansion() {
        var lifecycle = SelectionEntryLifecycle()
        lifecycle.present(
            SelectionEntryLifecycleTestSupport.snapshot(text: "quick", rangeFingerprint: "30:5"),
            pointerInsideContinuousRegion: false
        )
        let request = lifecycle.pointerMoved(isInsideContinuousRegion: true)
        _ = lifecycle.pointerMoved(isInsideContinuousRegion: false)
        if let request {
            lifecycle.timerFired(request.token)
        }

        SelectionEntryLifecycleTestSupport.expect(
            request?.delayMilliseconds == 180 && lifecycle.phase == .marker,
            "test_quick_pass_under_180ms_cancels_pending_expansion"
        )
    }

    static func test_expanded_entry_collapses_to_marker_after_400ms_outside() {
        var lifecycle = expandedLifecycle(text: "collapse", fingerprint: "40:8")
        let request = lifecycle.pointerMoved(isInsideContinuousRegion: false)
        let isCorrectRequest = request?.kind == .collapse && request?.delayMilliseconds == 400
        if let request {
            lifecycle.timerFired(request.token)
        }

        SelectionEntryLifecycleTestSupport.expect(
            isCorrectRequest && lifecycle.phase == .marker,
            "test_expanded_entry_collapses_to_marker_after_400ms_outside"
        )
    }

    static func test_reenter_before_400ms_cancels_pending_collapse() {
        var lifecycle = expandedLifecycle(text: "return", fingerprint: "50:6")
        let request = lifecycle.pointerMoved(isInsideContinuousRegion: false)
        _ = lifecycle.pointerMoved(isInsideContinuousRegion: true)
        if let request {
            lifecycle.timerFired(request.token)
        }

        SelectionEntryLifecycleTestSupport.expect(
            request?.delayMilliseconds == 400 && lifecycle.phase == .expanded,
            "test_reenter_before_400ms_cancels_pending_collapse"
        )
    }

    static func test_continuous_hit_region_keeps_expanded_entry_open_between_marker_and_actions() {
        var lifecycle = expandedLifecycle(text: "bridge", fingerprint: "60:6")
        let request = lifecycle.pointerMoved(isInsideContinuousRegion: true)

        SelectionEntryLifecycleTestSupport.expect(
            request == nil && lifecycle.phase == .expanded,
            "test_continuous_hit_region_keeps_expanded_entry_open_between_marker_and_actions"
        )
    }

    static func test_old_generation_timer_cannot_expand_replacement_selection() {
        var lifecycle = SelectionEntryLifecycle()
        lifecycle.present(
            SelectionEntryLifecycleTestSupport.snapshot(text: "old", rangeFingerprint: "70:3"),
            pointerInsideContinuousRegion: false
        )
        let oldRequest = lifecycle.pointerMoved(isInsideContinuousRegion: true)

        lifecycle.present(
            SelectionEntryLifecycleTestSupport.snapshot(text: "new", rangeFingerprint: "90:3"),
            pointerInsideContinuousRegion: false
        )
        if let oldRequest {
            lifecycle.timerFired(oldRequest.token)
        }

        SelectionEntryLifecycleTestSupport.expect(
            lifecycle.phase == .marker
                && lifecycle.currentSnapshot?.text == "new"
                && lifecycle.currentSnapshot?.rangeFingerprint == "90:3",
            "test_old_generation_timer_cannot_expand_replacement_selection"
        )
    }

    static func test_new_selection_replaces_expanded_entry_and_requires_fresh_hover() {
        var lifecycle = expandedLifecycle(text: "old expanded", fingerprint: "100:12")
        lifecycle.present(
            SelectionEntryLifecycleTestSupport.snapshot(text: "replacement", rangeFingerprint: "140:11"),
            pointerInsideContinuousRegion: true
        )
        let immediateMove = lifecycle.pointerMoved(isInsideContinuousRegion: true)

        SelectionEntryLifecycleTestSupport.expect(
            lifecycle.phase == .marker
                && lifecycle.currentSnapshot?.text == "replacement"
                && immediateMove == nil,
            "test_new_selection_replaces_expanded_entry_and_requires_fresh_hover"
        )
    }

    static func test_external_click_escape_and_invalid_selection_hide_entry() {
        let snapshot = SelectionEntryLifecycleTestSupport.snapshot(
            text: "dismiss",
            rangeFingerprint: "160:7"
        )

        var outsideClickLifecycle = SelectionEntryLifecycle()
        outsideClickLifecycle.present(snapshot, pointerInsideContinuousRegion: false)
        outsideClickLifecycle.outsideMouseDown()

        var escapeLifecycle = SelectionEntryLifecycle()
        escapeLifecycle.present(snapshot, pointerInsideContinuousRegion: false)
        escapeLifecycle.escapePressed()

        var invalidLifecycle = SelectionEntryLifecycle()
        invalidLifecycle.present(snapshot, pointerInsideContinuousRegion: false)
        invalidLifecycle.selectionInvalidated()

        SelectionEntryLifecycleTestSupport.expect(
            outsideClickLifecycle.phase == .hidden
                && outsideClickLifecycle.currentSnapshot == nil
                && escapeLifecycle.phase == .hidden
                && escapeLifecycle.currentSnapshot == nil
                && invalidLifecycle.phase == .hidden
                && invalidLifecycle.currentSnapshot == nil,
            "test_external_click_escape_and_invalid_selection_hide_entry"
        )
    }

    static func test_action_submission_returns_current_snapshot_once_and_hides_entry() {
        var translateLifecycle = expandedLifecycle(text: "translate me", fingerprint: "180:12")
        let translation = translateLifecycle.submit(.translate)
        let duplicate = translateLifecycle.submit(.translate)

        var askLifecycle = expandedLifecycle(text: "ask me", fingerprint: "200:6")
        let question = askLifecycle.submit(.ask)

        SelectionEntryLifecycleTestSupport.expect(
            translation?.action == .translate
                && translation?.snapshot.text == "translate me"
                && duplicate == nil
                && translateLifecycle.phase == .hidden
                && translateLifecycle.currentSnapshot == nil
                && question?.action == .ask
                && question?.snapshot.text == "ask me"
                && askLifecycle.phase == .hidden,
            "test_action_submission_returns_current_snapshot_once_and_hides_entry"
        )
    }

    private static func expandedLifecycle(
        text: String,
        fingerprint: String
    ) -> SelectionEntryLifecycle {
        var lifecycle = SelectionEntryLifecycle()
        lifecycle.present(
            SelectionEntryLifecycleTestSupport.snapshot(
                text: text,
                rangeFingerprint: fingerprint
            ),
            pointerInsideContinuousRegion: false
        )
        if let request = lifecycle.pointerMoved(isInsideContinuousRegion: true) {
            lifecycle.timerFired(request.token)
        }
        return lifecycle
    }
}

@main
enum SelectionEntryLifecycleTests {
    static func main() {
        TestSelectionEntryLifecycle.test_external_click_before_read_completion_invalidates_pending_selection_result()
        TestSelectionEntryLifecycle.test_escape_before_read_completion_invalidates_pending_selection_result()
        TestSelectionEntryLifecycle.test_second_selection_supersedes_first_read_and_only_latest_result_is_accepted()
        TestSelectionEntryLifecycle.test_initial_marker_under_pointer_does_not_automatically_begin_hover()
        TestSelectionEntryLifecycle.test_explicit_outside_to_inside_movement_schedules_180ms_and_expands()
        TestSelectionEntryLifecycle.test_quick_pass_under_180ms_cancels_pending_expansion()
        TestSelectionEntryLifecycle.test_expanded_entry_collapses_to_marker_after_400ms_outside()
        TestSelectionEntryLifecycle.test_reenter_before_400ms_cancels_pending_collapse()
        TestSelectionEntryLifecycle.test_continuous_hit_region_keeps_expanded_entry_open_between_marker_and_actions()
        TestSelectionEntryLifecycle.test_old_generation_timer_cannot_expand_replacement_selection()
        TestSelectionEntryLifecycle.test_new_selection_replaces_expanded_entry_and_requires_fresh_hover()
        TestSelectionEntryLifecycle.test_external_click_escape_and_invalid_selection_hide_entry()
        TestSelectionEntryLifecycle.test_action_submission_returns_current_snapshot_once_and_hides_entry()

        print(
            SelectionEntryLifecycleTestSupport.failures == 0
                ? "ALL PASS"
                : "\(SelectionEntryLifecycleTestSupport.failures) FAILURES"
        )
        exit(SelectionEntryLifecycleTestSupport.failures == 0 ? 0 : 1)
    }
}
