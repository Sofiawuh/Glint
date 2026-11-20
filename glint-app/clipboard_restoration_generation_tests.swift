import Foundation

// Clipboard restoration generation regression tests.
// These tests model only change-count policy and never access the real pasteboard.
// Run:
//   swiftc -o /tmp/glint_clipboard_restoration_generation_test \
//     SelectionDetection.swift clipboard_restoration_generation_tests.swift \
//     -framework Foundation -framework CoreGraphics \
//     && /tmp/glint_clipboard_restoration_generation_test

enum ClipboardRestorationGenerationTestSupport {
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

enum TestClipboardRestorationGeneration {
    static func test_current_glint_copy_generation_restores_previous_clipboard() {
        ClipboardRestorationGenerationTestSupport.expect(
            ClipboardRestorationPolicy.shouldRestore(
                copiedChangeCount: 101,
                currentChangeCount: 101
            ),
            "test_current_glint_copy_generation_restores_previous_clipboard"
        )
    }

    static func test_newer_external_generation_preserves_new_clipboard_content() {
        ClipboardRestorationGenerationTestSupport.expect(
            !ClipboardRestorationPolicy.shouldRestore(
                copiedChangeCount: 101,
                currentChangeCount: 102
            ),
            "test_newer_external_generation_preserves_new_clipboard_content"
        )
    }

    static func test_valid_read_token_accepts_first_change_as_copy_result() {
        var transaction = ClipboardRestorationPolicy.CopyTransaction(
            changeCountBeforeCopy: 100
        )

        let accepted = transaction.observePasteboardChange(changeCount: 101)

        ClipboardRestorationGenerationTestSupport.expect(
            accepted && transaction.shouldRestore(currentChangeCount: 101),
            "test_valid_read_token_accepts_first_change_as_copy_result"
        )
    }

    static func test_invalidated_read_token_rejects_late_change_as_copy_result() {
        var transaction = ClipboardRestorationPolicy.CopyTransaction(
            changeCountBeforeCopy: 200
        )
        transaction.invalidateReadToken()

        let accepted = transaction.observePasteboardChange(changeCount: 201)

        ClipboardRestorationGenerationTestSupport.expect(
            !accepted && !transaction.shouldRestore(currentChangeCount: 201),
            "test_invalidated_read_token_rejects_late_change_as_copy_result"
        )
    }

    static func test_confirmed_copy_still_restores_after_read_token_invalidation() {
        var transaction = ClipboardRestorationPolicy.CopyTransaction(
            changeCountBeforeCopy: 300
        )
        let accepted = transaction.observePasteboardChange(changeCount: 301)

        transaction.invalidateReadToken()

        ClipboardRestorationGenerationTestSupport.expect(
            accepted && transaction.shouldRestore(currentChangeCount: 301),
            "test_confirmed_copy_still_restores_after_read_token_invalidation"
        )
    }

    static func test_external_update_after_confirmed_copy_prevents_restore() {
        var transaction = ClipboardRestorationPolicy.CopyTransaction(
            changeCountBeforeCopy: 400
        )
        let accepted = transaction.observePasteboardChange(changeCount: 401)

        ClipboardRestorationGenerationTestSupport.expect(
            accepted && !transaction.shouldRestore(currentChangeCount: 402),
            "test_external_update_after_confirmed_copy_prevents_restore"
        )
    }
}

@main
enum ClipboardRestorationGenerationTests {
    static func main() {
        TestClipboardRestorationGeneration
            .test_current_glint_copy_generation_restores_previous_clipboard()
        TestClipboardRestorationGeneration
            .test_newer_external_generation_preserves_new_clipboard_content()
        TestClipboardRestorationGeneration
            .test_valid_read_token_accepts_first_change_as_copy_result()
        TestClipboardRestorationGeneration
            .test_invalidated_read_token_rejects_late_change_as_copy_result()
        TestClipboardRestorationGeneration
            .test_confirmed_copy_still_restores_after_read_token_invalidation()
        TestClipboardRestorationGeneration
            .test_external_update_after_confirmed_copy_prevents_restore()

        print(
            ClipboardRestorationGenerationTestSupport.failures == 0
                ? "ALL PASS"
                : "\(ClipboardRestorationGenerationTestSupport.failures) FAILURES"
        )
        exit(ClipboardRestorationGenerationTestSupport.failures == 0 ? 0 : 1)
    }
}
