import Foundation

enum PopupLifecycleTestSupport {
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

@main
enum PopupLifecycleTests {
    static func main() {
        var lifecycle = PopupLifecycle()

        lifecycle.present(isRestorableContent: true, allowsPinning: false)
        PopupLifecycleTestSupport.expect(
            !lifecycle.togglePin() && !lifecycle.isPinned,
            "紧凑提问卡片不允许钉住"
        )
        PopupLifecycleTestSupport.expect(
            lifecycle.outsideClick() == .hide
                && lifecycle.state == .hiddenRestorable
                && lifecycle.canRestore,
            "紧凑提问卡片外部点击后隐藏并可恢复"
        )
        PopupLifecycleTestSupport.expect(
            lifecycle.restore() && lifecycle.state == .visible && !lifecycle.canRestore,
            "恢复入口重新显示紧凑提问卡片"
        )

        lifecycle.present(isRestorableContent: true, allowsPinning: true)
        PopupLifecycleTestSupport.expect(
            lifecycle.outsideClick() == .hide
                && lifecycle.state == .hiddenRestorable
                && lifecycle.canRestore,
            "展开内容窗外部点击后隐藏并可恢复"
        )
        PopupLifecycleTestSupport.expect(
            lifecycle.restore() && lifecycle.state == .visible && !lifecycle.canRestore,
            "恢复入口重新显示展开内容窗"
        )
        PopupLifecycleTestSupport.expect(
            lifecycle.togglePin() && lifecycle.isPinned,
            "展开内容窗允许钉住"
        )
        PopupLifecycleTestSupport.expect(
            lifecycle.outsideClick() == .none && lifecycle.state == .visible,
            "钉住的展开内容窗忽略外部点击"
        )
        PopupLifecycleTestSupport.expect(
            lifecycle.newSelection() == .ignore,
            "钉住的展开内容窗不会被新划词替换"
        )

        _ = lifecycle.togglePin()
        _ = lifecycle.outsideClick()
        PopupLifecycleTestSupport.expect(
            lifecycle.state == .hiddenRestorable
                && lifecycle.canRestore
                && lifecycle.newSelection() == .replace,
            "未钉住的隐藏可恢复窗口允许新划词替换"
        )

        lifecycle.present(isRestorableContent: false, allowsPinning: false)
        PopupLifecycleTestSupport.expect(
            !lifecycle.togglePin() && !lifecycle.isPinned,
            "快捷划词胶囊不允许钉住"
        )
        PopupLifecycleTestSupport.expect(
            lifecycle.outsideClick() == .dismiss
                && lifecycle.state == .dismissed
                && !lifecycle.canRestore
                && !lifecycle.restore(),
            "快捷划词胶囊外部点击后直接关闭且不可恢复"
        )

        lifecycle.present(isRestorableContent: true, allowsPinning: true)
        _ = lifecycle.togglePin()
        lifecycle.dismiss()
        PopupLifecycleTestSupport.expect(
            lifecycle.state == .dismissed
                && !lifecycle.isPinned
                && !lifecycle.canRestore
                && !lifecycle.restore()
                && !lifecycle.togglePin(),
            "明确关闭清除图钉与恢复状态"
        )

        print(PopupLifecycleTestSupport.failures == 0 ? "ALL PASS" : "\(PopupLifecycleTestSupport.failures) FAILURES")
        exit(PopupLifecycleTestSupport.failures == 0 ? 0 : 1)
    }
}
