import Foundation

// On-demand selected-text extraction contracts. The tests use value snapshots only:
// no real Accessibility calls, key events or system pasteboard access.
//
// Intended minimal command once the production contracts exist:
//   swiftc -o /tmp/glint_selected_text_extractor_test \
//     SelectedTextExtractor.swift selected_text_extractor_tests.swift \
//     -framework Foundation && /tmp/glint_selected_text_extractor_test

enum SelectedTextExtractorTestSupport {
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

final class TestSelectedTextExtractorPriorityAndFiltering {
    static func test_nonempty_ax_text_is_trimmed_and_selected_without_requesting_copy() {
        let decision = SelectedTextExtractor.begin(axSelectedText: "  AX selected text\n")

        SelectedTextExtractorTestSupport.expect(
            decision == .selected(
                TextCommandSelectedText(text: "AX selected text", source: .accessibility)
            ),
            "TestSelectedTextExtractorPriorityAndFiltering.test_nonempty_ax_text_is_trimmed_and_selected_without_requesting_copy"
        )
    }

    static func test_missing_or_blank_ax_text_requests_protected_copy_fallback() {
        let missing = SelectedTextExtractor.begin(axSelectedText: nil)
        let blank = SelectedTextExtractor.begin(axSelectedText: " \n\t ")

        SelectedTextExtractorTestSupport.expect(
            missing == .copyRequired && blank == .copyRequired,
            "TestSelectedTextExtractorPriorityAndFiltering.test_missing_or_blank_ax_text_requests_protected_copy_fallback"
        )
    }

    static func test_changed_plain_text_copy_is_trimmed_and_accepted() {
        let capture = TextCommandClipboardCapture(
            changeCountBefore: 20,
            changeCountAfter: 21,
            text: "  copied text  ",
            types: ["public.utf8-plain-text"]
        )

        let result = SelectedTextExtractor.completeClipboard(capture)

        SelectedTextExtractorTestSupport.expect(
            result == TextCommandSelectedText(text: "copied text", source: .clipboard),
            "TestSelectedTextExtractorPriorityAndFiltering.test_changed_plain_text_copy_is_trimmed_and_accepted"
        )
    }

    static func test_unchanged_blank_file_and_image_copy_results_are_rejected() {
        let unchanged = TextCommandClipboardCapture(
            changeCountBefore: 20,
            changeCountAfter: 20,
            text: "old text",
            types: ["public.utf8-plain-text"]
        )
        let blank = TextCommandClipboardCapture(
            changeCountBefore: 20,
            changeCountAfter: 21,
            text: " \n ",
            types: ["public.utf8-plain-text"]
        )
        let fileURL = TextCommandClipboardCapture(
            changeCountBefore: 20,
            changeCountAfter: 21,
            text: "file:///tmp/report.pdf",
            types: ["public.file-url", "public.utf8-plain-text"]
        )
        let fileList = TextCommandClipboardCapture(
            changeCountBefore: 20,
            changeCountAfter: 21,
            text: "/tmp/report.pdf",
            types: ["NSFilenamesPboardType", "public.utf8-plain-text"]
        )
        let image = TextCommandClipboardCapture(
            changeCountBefore: 20,
            changeCountAfter: 21,
            text: "image description",
            types: ["public.png", "public.utf8-plain-text"]
        )

        SelectedTextExtractorTestSupport.expect(
            SelectedTextExtractor.completeClipboard(unchanged) == nil
                && SelectedTextExtractor.completeClipboard(blank) == nil
                && SelectedTextExtractor.completeClipboard(fileURL) == nil
                && SelectedTextExtractor.completeClipboard(fileList) == nil
                && SelectedTextExtractor.completeClipboard(image) == nil,
            "TestSelectedTextExtractorPriorityAndFiltering.test_unchanged_blank_file_and_image_copy_results_are_rejected"
        )
    }
}

final class TestTextCommandClipboardTransaction {
    private static let originalItems = [
        TextCommandPasteboardItem(dataByType: [
            "public.utf8-plain-text": Data("original text".utf8),
            "public.rtf": Data([0x7B, 0x5C, 0x72, 0x74, 0x66, 0x31, 0x7D])
        ]),
        TextCommandPasteboardItem(dataByType: [
            "com.example.custom": Data([0x00, 0x01, 0xFE, 0xFF])
        ])
    ]

    static func test_owned_copy_generation_restores_every_original_item_type_and_byte() {
        var transaction = TextCommandClipboardTransaction(
            originalItems: originalItems,
            changeCountBeforeCopy: 40
        )
        let accepted = transaction.observeCopy(changeCount: 41)

        let restoration = transaction.restorationItems(currentChangeCount: 41)

        SelectedTextExtractorTestSupport.expect(
            accepted
                && restoration == originalItems,
            "TestTextCommandClipboardTransaction.test_owned_copy_generation_restores_every_original_item_type_and_byte"
        )
    }

    static func test_third_party_clipboard_update_is_preserved_instead_of_overwritten_by_backup() {
        var transaction = TextCommandClipboardTransaction(
            originalItems: originalItems,
            changeCountBeforeCopy: 40
        )
        _ = transaction.observeCopy(changeCount: 41)

        let restoration = transaction.restorationItems(currentChangeCount: 42)

        SelectedTextExtractorTestSupport.expect(
            restoration == nil,
            "TestTextCommandClipboardTransaction.test_third_party_clipboard_update_is_preserved_instead_of_overwritten_by_backup"
        )
    }

    static func test_unchanged_or_invalidated_read_never_claims_clipboard_ownership() {
        var unchanged = TextCommandClipboardTransaction(
            originalItems: originalItems,
            changeCountBeforeCopy: 40
        )
        let unchangedAccepted = unchanged.observeCopy(changeCount: 40)

        var invalidated = TextCommandClipboardTransaction(
            originalItems: originalItems,
            changeCountBeforeCopy: 40
        )
        invalidated.invalidateReadToken()
        let invalidatedAccepted = invalidated.observeCopy(changeCount: 41)

        SelectedTextExtractorTestSupport.expect(
            !unchangedAccepted
                && unchanged.restorationItems(currentChangeCount: 40) == nil
                && !invalidatedAccepted
                && invalidated.restorationItems(currentChangeCount: 41) == nil,
            "TestTextCommandClipboardTransaction.test_unchanged_or_invalidated_read_never_claims_clipboard_ownership"
        )
    }
}

@main
struct SelectedTextExtractorTests {
    static func main() {
        TestSelectedTextExtractorPriorityAndFiltering.test_nonempty_ax_text_is_trimmed_and_selected_without_requesting_copy()
        TestSelectedTextExtractorPriorityAndFiltering.test_missing_or_blank_ax_text_requests_protected_copy_fallback()
        TestSelectedTextExtractorPriorityAndFiltering.test_changed_plain_text_copy_is_trimmed_and_accepted()
        TestSelectedTextExtractorPriorityAndFiltering.test_unchanged_blank_file_and_image_copy_results_are_rejected()
        TestTextCommandClipboardTransaction.test_owned_copy_generation_restores_every_original_item_type_and_byte()
        TestTextCommandClipboardTransaction.test_third_party_clipboard_update_is_preserved_instead_of_overwritten_by_backup()
        TestTextCommandClipboardTransaction.test_unchanged_or_invalidated_read_never_claims_clipboard_ownership()

        if SelectedTextExtractorTestSupport.failures > 0 {
            print("\n\(SelectedTextExtractorTestSupport.failures) selected-text extractor test(s) failed")
            exit(1)
        }
        print("\nAll selected-text extractor tests passed")
    }
}
