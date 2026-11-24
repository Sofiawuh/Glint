import Foundation

// 弹窗 / 翻译工作台固定按钮的纯值展示契约。
// 不创建窗口、不测试绘图像素；生产层需从 PopupLifecycle 的当前状态公开
// 实际按钮应使用的 SF Symbol、accessibility label 与 toolTip。
//
// 预期最小运行命令：
//   swiftc -parse-as-library -o /tmp/glint_popup_pin_control_contract_test \
//     PopupLifecycle.swift popup_pin_control_contract_tests.swift \
//     && /tmp/glint_popup_pin_control_contract_test

enum PopupPinControlContractTestSupport {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() {
            print("  ok  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
        }
    }
}

final class TestPopupPinControlPresentation {
    static func test_unpinnedAndPinnedStates_exposeMacOSPinSemanticsAndAccessibleState() {
        var lifecycle = PopupLifecycle()
        lifecycle.present(isRestorableContent: true, allowsPinning: true)
        let unpinned = lifecycle.pinControlPresentation

        let toggled = lifecycle.togglePin()
        let pinned = lifecycle.pinControlPresentation

        PopupPinControlContractTestSupport.expect(
            toggled
                && unpinned.symbolName == "pin"
                && pinned.symbolName == "pin.fill"
                && !unpinned.accessibilityLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !pinned.accessibilityLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && unpinned.accessibilityLabel != pinned.accessibilityLabel
                && unpinned.toolTip == unpinned.accessibilityLabel
                && pinned.toolTip == pinned.accessibilityLabel
                && !unpinned.accessibilityLabel.contains("取消")
                && pinned.accessibilityLabel.contains("取消"),
            "TestPopupPinControlPresentation.test_unpinnedAndPinnedStates_exposeMacOSPinSemanticsAndAccessibleState"
        )
    }
}

@main
enum PopupPinControlContractTests {
    static func main() {
        TestPopupPinControlPresentation.test_unpinnedAndPinnedStates_exposeMacOSPinSemanticsAndAccessibleState()

        print(
            PopupPinControlContractTestSupport.failures == 0
                ? "ALL PASS"
                : "\(PopupPinControlContractTestSupport.failures) FAILURES"
        )
        exit(PopupPinControlContractTestSupport.failures == 0 ? 0 : 1)
    }
}
