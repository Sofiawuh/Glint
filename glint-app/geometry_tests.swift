import AppKit

// Geometry.swift 的纯几何契约测试（不创建窗口或读取真实屏幕）。
// 运行：
//   swiftc -o /tmp/glint_geometry_test Geometry.swift geometry_tests.swift \
//     -framework AppKit && /tmp/glint_geometry_test

enum GeometryTestSupport {
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

    static func rectEquals(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        approximatelyEqual(lhs.minX, rhs.minX)
            && approximatelyEqual(lhs.minY, rhs.minY)
            && approximatelyEqual(lhs.width, rhs.width)
            && approximatelyEqual(lhs.height, rhs.height)
    }

    static func isInsideSafeArea(_ rect: CGRect, visibleFrame: CGRect) -> Bool {
        let safeArea = visibleFrame.insetBy(dx: kScreenEdgeGap, dy: kScreenEdgeGap)
        return rect.minX >= safeArea.minX - 0.5
            && rect.maxX <= safeArea.maxX + 0.5
            && rect.minY >= safeArea.minY - 0.5
            && rect.maxY <= safeArea.maxY + 0.5
    }
}

final class TestClampRectToVisible {
    static func test_in_bounds_rect_preserves_origin_and_size() {
        let visible = CGRect(x: 100, y: 50, width: 1000, height: 700)
        let input = CGRect(x: 300, y: 250, width: 200, height: 120)

        let result = clampRectToVisible(input, visible: visible)

        GeometryTestSupport.expect(
            GeometryTestSupport.rectEquals(result, input),
            "TestClampRectToVisible.test_in_bounds_rect_preserves_origin_and_size"
        )
    }

    static func test_each_overflowing_edge_clamps_to_six_point_safe_area() {
        let visible = CGRect(x: 100, y: 50, width: 1000, height: 700)
        let left = clampRectToVisible(
            CGRect(x: 20, y: 250, width: 200, height: 120),
            visible: visible
        )
        let right = clampRectToVisible(
            CGRect(x: 1000, y: 250, width: 200, height: 120),
            visible: visible
        )
        let bottom = clampRectToVisible(
            CGRect(x: 300, y: -40, width: 200, height: 120),
            visible: visible
        )
        let top = clampRectToVisible(
            CGRect(x: 300, y: 700, width: 200, height: 120),
            visible: visible
        )

        GeometryTestSupport.expect(
            GeometryTestSupport.approximatelyEqual(left.minX, 106)
                && GeometryTestSupport.approximatelyEqual(left.minY, 250)
                && GeometryTestSupport.approximatelyEqual(right.maxX, 1094)
                && GeometryTestSupport.approximatelyEqual(right.minY, 250)
                && GeometryTestSupport.approximatelyEqual(bottom.minX, 300)
                && GeometryTestSupport.approximatelyEqual(bottom.minY, 56)
                && GeometryTestSupport.approximatelyEqual(top.minX, 300)
                && GeometryTestSupport.approximatelyEqual(top.maxY, 744)
                && [left, right, bottom, top].allSatisfy {
                    GeometryTestSupport.isInsideSafeArea($0, visibleFrame: visible)
                },
            "TestClampRectToVisible.test_each_overflowing_edge_clamps_to_six_point_safe_area"
        )
    }

    static func test_negative_coordinate_display_clamps_without_crossing_to_primary() {
        let visible = CGRect(x: -2560, y: -116, width: 2560, height: 1440)
        let input = CGRect(x: -80, y: 300, width: 240, height: 180)

        let result = clampRectToVisible(input, visible: visible)

        GeometryTestSupport.expect(
            GeometryTestSupport.approximatelyEqual(result.maxX, -6)
                && GeometryTestSupport.approximatelyEqual(result.minY, 300)
                && result.minX < 0
                && result.maxX < 0
                && GeometryTestSupport.isInsideSafeArea(result, visibleFrame: visible),
            "TestClampRectToVisible.test_negative_coordinate_display_clamps_without_crossing_to_primary"
        )
    }
}

final class TestCursorAnchoredRect {
    private static let size = CGSize(width: 152, height: 34)

    static func test_normal_position_anchors_top_left_below_and_right_of_cursor() {
        let visible = CGRect(x: 0, y: 0, width: 1800, height: 1100)
        let cursor = CGPoint(x: 900, y: 500)

        let result = rectAtCursorBottomRight(
            cursor,
            visible: visible,
            w: size.width,
            h: size.height
        )
        let compatibilityResult = rectNearPoint(
            cursor,
            visible: visible,
            w: size.width,
            h: size.height
        )

        GeometryTestSupport.expect(
            GeometryTestSupport.approximatelyEqual(result.minX, 908)
                && GeometryTestSupport.approximatelyEqual(result.maxY, 492)
                && result.size == size
                && GeometryTestSupport.rectEquals(compatibilityResult, result),
            "TestCursorAnchoredRect.test_normal_position_anchors_top_left_below_and_right_of_cursor"
        )
    }

    static func test_each_screen_edge_clamps_complete_rect_inside_visible_frame() {
        let visible = CGRect(x: 0, y: 0, width: 1800, height: 1100)
        let cursors = [
            CGPoint(x: -20, y: 500),
            CGPoint(x: 1790, y: 500),
            CGPoint(x: 900, y: 10),
            CGPoint(x: 900, y: 1120)
        ]
        let results = cursors.map {
            rectAtCursorBottomRight($0, visible: visible, w: size.width, h: size.height)
        }

        GeometryTestSupport.expect(
            GeometryTestSupport.approximatelyEqual(results[0].minX, 6)
                && GeometryTestSupport.approximatelyEqual(results[1].maxX, 1794)
                && GeometryTestSupport.approximatelyEqual(results[2].minY, 6)
                && GeometryTestSupport.approximatelyEqual(results[3].maxY, 1094)
                && results.allSatisfy {
                    GeometryTestSupport.isInsideSafeArea($0, visibleFrame: visible)
                },
            "TestCursorAnchoredRect.test_each_screen_edge_clamps_complete_rect_inside_visible_frame"
        )
    }

    static func test_negative_coordinate_display_keeps_rect_on_that_display() {
        let visible = CGRect(x: -2560, y: -116, width: 2560, height: 1440)
        let cursor = CGPoint(x: -50, y: 400)

        let result = rectNearPoint(
            cursor,
            visible: visible,
            w: size.width,
            h: size.height
        )

        GeometryTestSupport.expect(
            GeometryTestSupport.approximatelyEqual(result.maxX, -6)
                && GeometryTestSupport.approximatelyEqual(result.maxY, 392)
                && result.minX < 0
                && result.maxX < 0
                && GeometryTestSupport.isInsideSafeArea(result, visibleFrame: visible),
            "TestCursorAnchoredRect.test_negative_coordinate_display_keeps_rect_on_that_display"
        )
    }
}

final class TestScreenCoordinateConversion {
    private static let primaryHeight: CGFloat = 1117

    static func test_primary_screen_capture_converts_bottom_left_to_quartz_top_left() {
        let result = captureQuartzRect(
            localRect: CGRect(x: 100, y: 200, width: 300, height: 400),
            screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            primaryScreenHeight: primaryHeight
        )

        GeometryTestSupport.expect(
            GeometryTestSupport.rectEquals(
                result,
                CGRect(x: 100, y: 517, width: 300, height: 400)
            ),
            "TestScreenCoordinateConversion.test_primary_screen_capture_converts_bottom_left_to_quartz_top_left"
        )
    }

    static func test_negative_uneven_secondary_screen_uses_global_multiscreen_coordinates() {
        let secondary = CGRect(x: -2560, y: -116, width: 2560, height: 1440)
        let middle = captureQuartzRect(
            localRect: CGRect(x: 500, y: 300, width: 600, height: 400),
            screenFrame: secondary,
            primaryScreenHeight: primaryHeight
        )
        let abovePrimary = captureQuartzRect(
            localRect: CGRect(x: 100, y: 1250, width: 200, height: 150),
            screenFrame: secondary,
            primaryScreenHeight: primaryHeight
        )

        GeometryTestSupport.expect(
            GeometryTestSupport.rectEquals(
                middle,
                CGRect(x: -2060, y: 533, width: 600, height: 400)
            )
                && GeometryTestSupport.rectEquals(
                    abovePrimary,
                    CGRect(x: -2460, y: -167, width: 200, height: 150)
                ),
            "TestScreenCoordinateConversion.test_negative_uneven_secondary_screen_uses_global_multiscreen_coordinates"
        )
    }

    static func test_appkit_point_and_rect_convert_quartz_coordinates_back() {
        let point = appKitPoint(
            fromQuartz: CGPoint(x: -2460, y: -167),
            primaryScreenHeight: primaryHeight
        )
        let quartzRect = CGRect(x: -2060, y: 533, width: 600, height: 400)
        let rect = appKitRect(fromQuartz: quartzRect, primaryScreenHeight: primaryHeight)

        GeometryTestSupport.expect(
            GeometryTestSupport.approximatelyEqual(point.x, -2460)
                && GeometryTestSupport.approximatelyEqual(point.y, 1284)
                && GeometryTestSupport.rectEquals(
                    rect,
                    CGRect(x: -2060, y: 184, width: 600, height: 400)
                ),
            "TestScreenCoordinateConversion.test_appkit_point_and_rect_convert_quartz_coordinates_back"
        )
    }

    static func test_capture_and_appkit_rect_round_trip_returns_global_selection() {
        let screen = CGRect(x: -2560, y: -116, width: 2560, height: 1440)
        let localSelection = CGRect(x: 500, y: 300, width: 600, height: 400)
        let quartzRect = captureQuartzRect(
            localRect: localSelection,
            screenFrame: screen,
            primaryScreenHeight: primaryHeight
        )

        let result = appKitRect(fromQuartz: quartzRect, primaryScreenHeight: primaryHeight)
        let expectedGlobalSelection = localSelection.offsetBy(dx: screen.minX, dy: screen.minY)

        GeometryTestSupport.expect(
            GeometryTestSupport.rectEquals(result, expectedGlobalSelection),
            "TestScreenCoordinateConversion.test_capture_and_appkit_rect_round_trip_returns_global_selection"
        )
    }
}

@main
struct GeometryTests {
    static func main() {
        TestClampRectToVisible.test_in_bounds_rect_preserves_origin_and_size()
        TestClampRectToVisible.test_each_overflowing_edge_clamps_to_six_point_safe_area()
        TestClampRectToVisible.test_negative_coordinate_display_clamps_without_crossing_to_primary()
        TestCursorAnchoredRect.test_normal_position_anchors_top_left_below_and_right_of_cursor()
        TestCursorAnchoredRect.test_each_screen_edge_clamps_complete_rect_inside_visible_frame()
        TestCursorAnchoredRect.test_negative_coordinate_display_keeps_rect_on_that_display()
        TestScreenCoordinateConversion.test_primary_screen_capture_converts_bottom_left_to_quartz_top_left()
        TestScreenCoordinateConversion.test_negative_uneven_secondary_screen_uses_global_multiscreen_coordinates()
        TestScreenCoordinateConversion.test_appkit_point_and_rect_convert_quartz_coordinates_back()
        TestScreenCoordinateConversion.test_capture_and_appkit_rect_round_trip_returns_global_selection()

        if GeometryTestSupport.failures > 0 {
            print("\n\(GeometryTestSupport.failures) geometry test(s) failed")
            exit(1)
        }
        print("\nAll geometry tests passed")
    }
}
