import AppKit

// Text-command panel state and mouse-near layout contracts. No NSPanel is created.
//
// Intended minimal command once the production contracts exist:
//   swiftc -o /tmp/glint_text_command_panel_test \
//     TextCommandPanelLifecycle.swift Geometry.swift text_command_panel_tests.swift \
//     -framework AppKit && /tmp/glint_text_command_panel_test

enum TextCommandPanelTestSupport {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() {
            print("  ok  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
        }
    }

    static func approximatelyEqual(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) < 0.5
    }

    static func isInside(_ rect: CGRect, visibleFrame: CGRect, edgeGap: CGFloat) -> Bool {
        let safe = visibleFrame.insetBy(dx: edgeGap, dy: edgeGap)
        return rect.minX >= safe.minX - 0.5
            && rect.maxX <= safe.maxX + 0.5
            && rect.minY >= safe.minY - 0.5
            && rect.maxY <= safe.maxY + 0.5
    }
}

final class TestTextCommandPanelLayout {
    private static let size = CGSize(width: 168, height: 40)
    private static let offset: CGFloat = 12
    private static let edgeGap: CGFloat = 6

    static func test_center_pointer_places_panel_directly_to_the_lower_right() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let pointer = CGPoint(x: 500, y: 500)

        let frame = textCommandPanelFrame(
            mouseLocation: pointer,
            visibleFrame: visible,
            panelSize: size,
            offset: offset,
            edgeGap: edgeGap
        )

        TextCommandPanelTestSupport.expect(
            TextCommandPanelTestSupport.approximatelyEqual(frame.minX, 512)
                && TextCommandPanelTestSupport.approximatelyEqual(frame.maxY, 488)
                && frame.size == size,
            "TestTextCommandPanelLayout.test_center_pointer_places_panel_directly_to_the_lower_right"
        )
    }

    static func test_each_screen_edge_clamps_the_complete_panel_inside_visible_frame() {
        let visible = CGRect(x: 0, y: 70, width: 1440, height: 810)
        let pointers = [
            CGPoint(x: -20, y: 450),
            CGPoint(x: 1435, y: 450),
            CGPoint(x: 700, y: 920),
            CGPoint(x: 700, y: 75),
            CGPoint(x: 1438, y: 72)
        ]
        let frames = pointers.map {
            textCommandPanelFrame(
                mouseLocation: $0,
                visibleFrame: visible,
                panelSize: size,
                offset: offset,
                edgeGap: edgeGap
            )
        }

        TextCommandPanelTestSupport.expect(
            frames.allSatisfy {
                TextCommandPanelTestSupport.isInside(
                    $0,
                    visibleFrame: visible,
                    edgeGap: edgeGap
                )
            }
                && TextCommandPanelTestSupport.approximatelyEqual(frames[0].minX, visible.minX + edgeGap)
                && TextCommandPanelTestSupport.approximatelyEqual(frames[1].maxX, visible.maxX - edgeGap)
                && TextCommandPanelTestSupport.approximatelyEqual(frames[2].maxY, visible.maxY - edgeGap)
                && TextCommandPanelTestSupport.approximatelyEqual(frames[3].minY, visible.minY + edgeGap),
            "TestTextCommandPanelLayout.test_each_screen_edge_clamps_the_complete_panel_inside_visible_frame"
        )
    }

    static func test_negative_coordinate_monitor_clamps_without_jumping_to_primary_screen() {
        let visible = CGRect(x: -2560, y: -116, width: 2560, height: 1440)
        let pointer = CGPoint(x: -40, y: 300)

        let frame = textCommandPanelFrame(
            mouseLocation: pointer,
            visibleFrame: visible,
            panelSize: size,
            offset: offset,
            edgeGap: edgeGap
        )

        TextCommandPanelTestSupport.expect(
            TextCommandPanelTestSupport.isInside(frame, visibleFrame: visible, edgeGap: edgeGap)
                && TextCommandPanelTestSupport.approximatelyEqual(frame.maxX, -6)
                && frame.minX < 0
                && frame.maxX < 0,
            "TestTextCommandPanelLayout.test_negative_coordinate_monitor_clamps_without_jumping_to_primary_screen"
        )
    }
}

final class TestTextCommandPanelLifecycle {
    static func test_successful_request_immediately_exposes_translate_and_ask_without_marker_or_hover_stage() {
        var lifecycle = TextCommandPanelLifecycle()
        let request = lifecycle.beginRequest()
        let accepted = lifecycle.completeRequest(
            request,
            text: "first selection",
            mouseLocation: CGPoint(x: 400, y: 300)
        )

        TextCommandPanelTestSupport.expect(
            accepted
                && lifecycle.state == .visible(
                    text: "first selection",
                    mouseLocation: CGPoint(x: 400, y: 300),
                    actions: [.translate, .ask]
                ),
            "TestTextCommandPanelLifecycle.test_successful_request_immediately_exposes_translate_and_ask_without_marker_or_hover_stage"
        )
    }

    static func test_new_request_replaces_visible_snapshot_and_late_old_result_is_rejected() {
        var lifecycle = TextCommandPanelLifecycle()
        let first = lifecycle.beginRequest()
        _ = lifecycle.completeRequest(
            first,
            text: "old selection",
            mouseLocation: CGPoint(x: 100, y: 100)
        )
        let second = lifecycle.beginRequest()
        let lateFirstAccepted = lifecycle.completeRequest(
            first,
            text: "late old selection",
            mouseLocation: CGPoint(x: 150, y: 150)
        )
        let secondAccepted = lifecycle.completeRequest(
            second,
            text: "new selection",
            mouseLocation: CGPoint(x: 800, y: 600)
        )

        TextCommandPanelTestSupport.expect(
            !lateFirstAccepted
                && secondAccepted
                && lifecycle.state == .visible(
                    text: "new selection",
                    mouseLocation: CGPoint(x: 800, y: 600),
                    actions: [.translate, .ask]
                ),
            "TestTextCommandPanelLifecycle.test_new_request_replaces_visible_snapshot_and_late_old_result_is_rejected"
        )
    }

    static func test_external_click_and_escape_each_close_visible_panel() {
        var outsideClickLifecycle = TextCommandPanelLifecycle()
        let outsideRequest = outsideClickLifecycle.beginRequest()
        _ = outsideClickLifecycle.completeRequest(
            outsideRequest,
            text: "outside click",
            mouseLocation: .zero
        )
        outsideClickLifecycle.handleOutsideClick()

        var escapeLifecycle = TextCommandPanelLifecycle()
        let escapeRequest = escapeLifecycle.beginRequest()
        _ = escapeLifecycle.completeRequest(
            escapeRequest,
            text: "escape",
            mouseLocation: .zero
        )
        escapeLifecycle.handleEscape()

        TextCommandPanelTestSupport.expect(
            outsideClickLifecycle.state == .hidden
                && escapeLifecycle.state == .hidden,
            "TestTextCommandPanelLifecycle.test_external_click_and_escape_each_close_visible_panel"
        )
    }

    static func test_action_submission_returns_current_text_once_and_closes_panel() {
        var lifecycle = TextCommandPanelLifecycle()
        let request = lifecycle.beginRequest()
        _ = lifecycle.completeRequest(
            request,
            text: "immutable selection",
            mouseLocation: CGPoint(x: 200, y: 180)
        )

        let first = lifecycle.submit(.translate)
        let second = lifecycle.submit(.translate)

        TextCommandPanelTestSupport.expect(
            first == TextCommandPanelSubmission(action: .translate, text: "immutable selection")
                && second == nil
                && lifecycle.state == .hidden,
            "TestTextCommandPanelLifecycle.test_action_submission_returns_current_text_once_and_closes_panel"
        )
    }
}

@main
struct TextCommandPanelTests {
    static func main() {
        TestTextCommandPanelLayout.test_center_pointer_places_panel_directly_to_the_lower_right()
        TestTextCommandPanelLayout.test_each_screen_edge_clamps_the_complete_panel_inside_visible_frame()
        TestTextCommandPanelLayout.test_negative_coordinate_monitor_clamps_without_jumping_to_primary_screen()
        TestTextCommandPanelLifecycle.test_successful_request_immediately_exposes_translate_and_ask_without_marker_or_hover_stage()
        TestTextCommandPanelLifecycle.test_new_request_replaces_visible_snapshot_and_late_old_result_is_rejected()
        TestTextCommandPanelLifecycle.test_external_click_and_escape_each_close_visible_panel()
        TestTextCommandPanelLifecycle.test_action_submission_returns_current_text_once_and_closes_panel()

        if TextCommandPanelTestSupport.failures > 0 {
            print("\n\(TextCommandPanelTestSupport.failures) text-command panel test(s) failed")
            exit(1)
        }
        print("\nAll text-command panel tests passed")
    }
}
