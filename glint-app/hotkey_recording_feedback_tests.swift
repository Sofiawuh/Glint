import Carbon
import Foundation

// Pure feedback contract shared by both settings hot-key recorders.
// This executable must not launch AppKit, load the user's config, or register a hot key.
//
// Intended minimal command once the production contract exists:
//   swiftc -o /tmp/glint_hotkey_recording_feedback_test \
//     ScreenshotHotKey.swift hotkey_recording_feedback_tests.swift \
//     -framework Carbon -framework Foundation \
//     && /tmp/glint_hotkey_recording_feedback_test

enum HotKeyRecordingFeedbackTestSupport {
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

final class TestHotKeyRecordingFeedback {
    static func test_invalidDecision_returnsExactSingleKeyGuidance() {
        let status = HotKeyRecordingFeedback.status(
            after: .invalid,
            current: "旧状态"
        )

        HotKeyRecordingFeedbackTestSupport.expect(
            status == "可单独按 ` 或 F1–F20；其他按键需搭配修饰键"
                && status == HotKeyRecordingFeedback.invalidSingleKeyMessage,
            "TestHotKeyRecordingFeedback.test_invalidDecision_returnsExactSingleKeyGuidance"
        )
    }

    static func test_waitForKeyDecision_preservesCurrentGuidance() {
        let current = "可单独按 ` 或 F1–F20；其他按键需搭配修饰键"
        let status = HotKeyRecordingFeedback.status(
            after: .waitForKey,
            current: current
        )

        HotKeyRecordingFeedbackTestSupport.expect(
            status == current,
            "TestHotKeyRecordingFeedback.test_waitForKeyDecision_preservesCurrentGuidance"
        )
    }

    static func test_terminalDecisions_clearPreviousGuidance() {
        let current = "可单独按 ` 或 F1–F20；其他按键需搭配修饰键"
        let committed = ScreenshotHotKey(
            keyCode: UInt32(kVK_F12),
            modifiers: 0
        )
        let decisions: [ScreenshotHotKey.RecordingDecision] = [
            .cancel,
            .restoreDefault,
            .commit(committed)
        ]

        HotKeyRecordingFeedbackTestSupport.expect(
            decisions.allSatisfy {
                HotKeyRecordingFeedback.status(after: $0, current: current).isEmpty
            },
            "TestHotKeyRecordingFeedback.test_terminalDecisions_clearPreviousGuidance"
        )
    }
}

@main
enum HotKeyRecordingFeedbackTests {
    static func main() {
        TestHotKeyRecordingFeedback.test_invalidDecision_returnsExactSingleKeyGuidance()
        TestHotKeyRecordingFeedback.test_waitForKeyDecision_preservesCurrentGuidance()
        TestHotKeyRecordingFeedback.test_terminalDecisions_clearPreviousGuidance()

        print(
            HotKeyRecordingFeedbackTestSupport.failures == 0
                ? "ALL PASS"
                : "\(HotKeyRecordingFeedbackTestSupport.failures) FAILURES"
        )
        exit(HotKeyRecordingFeedbackTestSupport.failures == 0 ? 0 : 1)
    }
}
