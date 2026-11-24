import AppKit

// Pure screen-selection contract plus a source-level guard against unchecked
// NSScreen.screens indexing.
//
// Intended command once the production contract exists:
//   swiftc -parse-as-library -o /tmp/glint_text_command_screen_safety_test \
//     Geometry.swift text_command_screen_safety_contract_tests.swift \
//     -framework AppKit && \
//   /tmp/glint_text_command_screen_safety_test TextCommandPanelController.swift

enum TextCommandScreenSafetyTestSupport {
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

#if !SCREEN_SOURCE_ONLY
final class TestTextCommandScreenSelection {
    private static let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private static let left = CGRect(x: -1920, y: -120, width: 1920, height: 1080)

    static func test_pointerInsideSecondaryScreen_returnsThatVisibleFrame() {
        let selected = textCommandPanelVisibleFrame(
            mouseLocation: CGPoint(x: -800, y: 400),
            availableVisibleFrames: [primary, left],
            mainVisibleFrame: primary
        )

        TextCommandScreenSafetyTestSupport.expect(
            selected == left,
            "TestTextCommandScreenSelection.test_pointerInsideSecondaryScreen_returnsThatVisibleFrame"
        )
    }

    static func test_pointerOutsideEveryScreen_returnsNearestVisibleFrame() {
        let selected = textCommandPanelVisibleFrame(
            mouseLocation: CGPoint(x: -2000, y: 400),
            availableVisibleFrames: [primary, left],
            mainVisibleFrame: primary
        )

        TextCommandScreenSafetyTestSupport.expect(
            selected == left,
            "TestTextCommandScreenSelection.test_pointerOutsideEveryScreen_returnsNearestVisibleFrame"
        )
    }

    static func test_emptyScreensWithMainFrame_returnsSafeMainFallback() {
        let selected = textCommandPanelVisibleFrame(
            mouseLocation: CGPoint(x: 300, y: 200),
            availableVisibleFrames: [],
            mainVisibleFrame: primary
        )

        TextCommandScreenSafetyTestSupport.expect(
            selected == primary,
            "TestTextCommandScreenSelection.test_emptyScreensWithMainFrame_returnsSafeMainFallback"
        )
    }

    static func test_emptyScreensWithoutMainFrame_returnsNilInsteadOfIndexingOrCrashing() {
        let selected = textCommandPanelVisibleFrame(
            mouseLocation: CGPoint(x: 300, y: 200),
            availableVisibleFrames: [],
            mainVisibleFrame: nil
        )

        TextCommandScreenSafetyTestSupport.expect(
            selected == nil,
            "TestTextCommandScreenSelection.test_emptyScreensWithoutMainFrame_returnsNilInsteadOfIndexingOrCrashing"
        )
    }
}
#endif

final class TestTextCommandPanelControllerScreenSourceContract {
    static func test_controllerSource_neverDirectlyIndexesFirstScreen() {
        let path = CommandLine.arguments.count > 1
            ? CommandLine.arguments[1]
            : "TextCommandPanelController.swift"
        let source = try? String(contentsOfFile: path, encoding: .utf8)
        let directIndexPattern = #"NSScreen\s*\.\s*screens\s*\[\s*0\s*\]"#
        let forcedFirstPattern = #"NSScreen\s*\.\s*screens\s*\.\s*first\s*!"#

        TextCommandScreenSafetyTestSupport.expect(
            source.map { text in
                text.range(of: directIndexPattern, options: .regularExpression) == nil
                    && text.range(of: forcedFirstPattern, options: .regularExpression) == nil
            } == true,
            "TestTextCommandPanelControllerScreenSourceContract.test_controllerSource_neverDirectlyIndexesFirstScreen"
        )
    }
}

@main
struct TextCommandScreenSafetyContractTests {
    static func main() {
#if !SCREEN_SOURCE_ONLY
        TestTextCommandScreenSelection.test_pointerInsideSecondaryScreen_returnsThatVisibleFrame()
        TestTextCommandScreenSelection.test_pointerOutsideEveryScreen_returnsNearestVisibleFrame()
        TestTextCommandScreenSelection.test_emptyScreensWithMainFrame_returnsSafeMainFallback()
        TestTextCommandScreenSelection.test_emptyScreensWithoutMainFrame_returnsNilInsteadOfIndexingOrCrashing()
#endif
        TestTextCommandPanelControllerScreenSourceContract.test_controllerSource_neverDirectlyIndexesFirstScreen()

        if TextCommandScreenSafetyTestSupport.failures > 0 {
            print("\n\(TextCommandScreenSafetyTestSupport.failures) text-command screen safety contract test(s) failed")
            exit(1)
        }
        print("\nAll text-command screen safety contract tests passed")
    }
}
