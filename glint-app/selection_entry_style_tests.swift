import AppKit

// 选区入口可见方块的纯样式契约；不创建 NSPanel、NSView 或读取用户配置。
// 运行：
//   swiftc -parse-as-library -o /tmp/glint_selection_entry_style_test \
//     SelectionEntryStyle.swift selection_entry_style_tests.swift \
//     -framework AppKit \
//     && /tmp/glint_selection_entry_style_test

@main
enum SelectionEntryStyleTests {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() {
            print("  ok  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
        }
    }

    static func main() {
        let style = SelectionEntryMarkerStyle.default

        expect(
            style.shape == .roundedSquare
                && style.visibleSize == NSSize(width: 10, height: 10)
                && style.hitSize == NSSize(width: 22, height: 22)
                && (2 ... 3).contains(style.cornerRadius),
            "test_default_marker_is_ten_point_rounded_square_with_twenty_two_point_hit_area"
        )

        expect(
            style.fillRole == .terracotta
                && style.showsInteriorGlyph == false,
            "test_default_marker_is_solid_terracotta_without_starburst_or_other_glyph"
        )

        expect(
            (0.5 ... 1.5).contains(style.borderWidth)
                && style.shadowOpacity > 0
                && style.shadowOpacity <= 0.25
                && (1 ... 4).contains(style.shadowBlurRadius)
                && abs(style.shadowOffset.width) <= 2
                && abs(style.shadowOffset.height) <= 2,
            "test_default_marker_uses_light_border_and_restrained_close_shadow"
        )

        print(failures == 0 ? "ALL PASS" : "\(failures) FAILURES")
        exit(failures == 0 ? 0 : 1)
    }
}
