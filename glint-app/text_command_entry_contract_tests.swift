import Carbon
import Foundation

// App input-routing contract for the explicit text-command entry. This is deliberately
// event-level: selection gestures and pointer movement are inert; only the dedicated
// hot key may begin a text read. The screenshot route remains an independent action.
//
// Intended minimal command once the production contract exists:
//   swiftc -o /tmp/glint_text_command_entry_contract_test \
//     ScreenshotHotKey.swift TextCommandEntryPolicy.swift \
//     text_command_entry_contract_tests.swift -framework Carbon -framework Foundation \
//     && /tmp/glint_text_command_entry_contract_test

enum TextCommandEntryContractTestSupport {
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

final class TestTextCommandEntryRouting {
    static func test_selection_gestures_keyboard_selection_and_mouse_movement_do_not_begin_text_read_or_show_entry() {
        let inertInputs: [TextCommandAppInput] = [
            .mouseReleased(clickCount: 1, displacement: 30),
            .mouseReleased(clickCount: 2, displacement: 0),
            .mouseReleased(clickCount: 3, displacement: 0),
            .mouseMoved,
            .keyboardSelection,
            .selectAll
        ]
        let actions = inertInputs.map {
            TextCommandEntryPolicy.action(for: $0, panelIsVisible: false)
        }

        TextCommandEntryContractTestSupport.expect(
            actions.allSatisfy { $0 == .none },
            "TestTextCommandEntryRouting.test_selection_gestures_keyboard_selection_and_mouse_movement_do_not_begin_text_read_or_show_entry"
        )
    }

    static func test_only_text_command_hot_key_begins_on_demand_text_read() {
        let action = TextCommandEntryPolicy.action(
            for: .textCommandHotKey,
            panelIsVisible: false
        )

        TextCommandEntryContractTestSupport.expect(
            action == .beginTextRead,
            "TestTextCommandEntryRouting.test_only_text_command_hot_key_begins_on_demand_text_read"
        )
    }

    static func test_screenshot_hot_key_remains_independent_and_keeps_existing_default() {
        let action = TextCommandEntryPolicy.action(
            for: .screenshotHotKey,
            panelIsVisible: false
        )
        let screenshot = ScreenshotHotKey.default

        TextCommandEntryContractTestSupport.expect(
            action == .beginScreenshot
                && screenshot.keyCode == UInt32(kVK_ANSI_E)
                && screenshot.modifiers == UInt32(controlKey | optionKey)
                && screenshot.displayString == "⌃⌥E",
            "TestTextCommandEntryRouting.test_screenshot_hot_key_remains_independent_and_keeps_existing_default"
        )
    }

    static func test_escape_and_external_click_only_dismiss_an_existing_text_command_panel() {
        let hiddenEscape = TextCommandEntryPolicy.action(for: .escape, panelIsVisible: false)
        let visibleEscape = TextCommandEntryPolicy.action(for: .escape, panelIsVisible: true)
        let hiddenClick = TextCommandEntryPolicy.action(for: .externalMouseDown, panelIsVisible: false)
        let visibleClick = TextCommandEntryPolicy.action(for: .externalMouseDown, panelIsVisible: true)

        TextCommandEntryContractTestSupport.expect(
            hiddenEscape == .none
                && hiddenClick == .none
                && visibleEscape == .dismissTextCommandPanel
                && visibleClick == .dismissTextCommandPanel,
            "TestTextCommandEntryRouting.test_escape_and_external_click_only_dismiss_an_existing_text_command_panel"
        )
    }
}

final class TestTextCommandReadSourceBinding {
    private static let checkpoints: [TextCommandReadCheckpoint] = [
        .beforeAccessibilityRead,
        .afterAccessibilityRead,
        .beforeProtectedCopy,
        .duringProtectedCopy,
        .beforePresentation
    ]

    static func test_same_generation_and_source_application_allow_every_read_checkpoint() {
        let request = TextCommandReadIdentity(
            generation: 41,
            sourceApplicationPID: 7_001
        )

        let allowed = checkpoints.allSatisfy {
            TextCommandReadSourcePolicy.allows(
                request,
                currentGeneration: 41,
                frontmostApplicationPID: 7_001,
                at: $0
            )
        }

        TextCommandEntryContractTestSupport.expect(
            allowed,
            "TestTextCommandReadSourceBinding.test_same_generation_and_source_application_allow_every_read_checkpoint"
        )
    }

    static func test_application_switch_missing_source_or_new_generation_reject_every_read_checkpoint() {
        let request = TextCommandReadIdentity(
            generation: 41,
            sourceApplicationPID: 7_001
        )

        let applicationChanged = checkpoints.allSatisfy {
            !TextCommandReadSourcePolicy.allows(
                request,
                currentGeneration: 41,
                frontmostApplicationPID: 7_002,
                at: $0
            )
        }
        let applicationMissing = checkpoints.allSatisfy {
            !TextCommandReadSourcePolicy.allows(
                request,
                currentGeneration: 41,
                frontmostApplicationPID: nil,
                at: $0
            )
        }
        let generationChanged = checkpoints.allSatisfy {
            !TextCommandReadSourcePolicy.allows(
                request,
                currentGeneration: 42,
                frontmostApplicationPID: 7_001,
                at: $0
            )
        }

        TextCommandEntryContractTestSupport.expect(
            applicationChanged && applicationMissing && generationChanged,
            "TestTextCommandReadSourceBinding.test_application_switch_missing_source_or_new_generation_reject_every_read_checkpoint"
        )
    }
}

@main
struct TextCommandEntryContractTests {
    static func main() {
        TestTextCommandEntryRouting.test_selection_gestures_keyboard_selection_and_mouse_movement_do_not_begin_text_read_or_show_entry()
        TestTextCommandEntryRouting.test_only_text_command_hot_key_begins_on_demand_text_read()
        TestTextCommandEntryRouting.test_screenshot_hot_key_remains_independent_and_keeps_existing_default()
        TestTextCommandEntryRouting.test_escape_and_external_click_only_dismiss_an_existing_text_command_panel()
        TestTextCommandReadSourceBinding.test_same_generation_and_source_application_allow_every_read_checkpoint()
        TestTextCommandReadSourceBinding.test_application_switch_missing_source_or_new_generation_reject_every_read_checkpoint()

        if TextCommandEntryContractTestSupport.failures > 0 {
            print("\n\(TextCommandEntryContractTestSupport.failures) text-command entry contract test(s) failed")
            exit(1)
        }
        print("\nAll text-command entry contract tests passed")
    }
}
