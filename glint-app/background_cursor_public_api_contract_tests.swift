import Foundation

// Source-level contract for a nonactivating panel's background cursor behavior.
// Run from glint-app or pass the absolute path to main.swift as argv[1]:
//   swiftc -parse-as-library -o /tmp/glint_background_cursor_contract \
//     background_cursor_public_api_contract_tests.swift && \
//   /tmp/glint_background_cursor_contract main.swift

enum BackgroundCursorContractTestSupport {
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

final class TestBackgroundCursorPublicAPIContract {
    static func test_mainSource_hasNoPrivateWindowServerSymbolLookup() {
        let source = readMainSource()
        let forbidden = [
            "_CGSDefaultConnection",
            "CGSSetConnectionProperty",
            "dlopen(",
            "dlsym("
        ]

        BackgroundCursorContractTestSupport.expect(
            source.map { text in !forbidden.contains(where: text.contains) } == true,
            "TestBackgroundCursorPublicAPIContract.test_mainSource_hasNoPrivateWindowServerSymbolLookup"
        )
    }

    static func test_selectableTextCursor_usesOnlyPublicCursorAPIOrSafeArrowFallback() {
        guard let source = readMainSource(),
              let selectableRange = source.range(of: "final class SelectableTextView") else {
            BackgroundCursorContractTestSupport.expect(
                false,
                "TestBackgroundCursorPublicAPIContract.test_selectableTextCursor_usesOnlyPublicCursorAPIOrSafeArrowFallback"
            )
            return
        }
        let suffix = source[selectableRange.lowerBound...]
        let end = suffix.range(of: "\nfinal class ", options: [], range: suffix.index(after: suffix.startIndex)..<suffix.endIndex)?.lowerBound
            ?? suffix.endIndex
        let selectableSource = String(suffix[..<end])
        let hasPublicIBeamPath = selectableSource.contains("NSCursor.iBeam")
            || selectableSource.contains("addCursorRect")
        let hasSafeFallback = selectableSource.contains("NSCursor.arrow")
            || selectableSource.contains("discardCursorRects")

        BackgroundCursorContractTestSupport.expect(
            hasPublicIBeamPath && hasSafeFallback,
            "TestBackgroundCursorPublicAPIContract.test_selectableTextCursor_usesOnlyPublicCursorAPIOrSafeArrowFallback"
        )
    }

    private static func readMainSource() -> String? {
        let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "main.swift"
        return try? String(contentsOfFile: path, encoding: .utf8)
    }
}

@main
struct BackgroundCursorPublicAPIContractTests {
    static func main() {
        TestBackgroundCursorPublicAPIContract.test_mainSource_hasNoPrivateWindowServerSymbolLookup()
        TestBackgroundCursorPublicAPIContract.test_selectableTextCursor_usesOnlyPublicCursorAPIOrSafeArrowFallback()

        if BackgroundCursorContractTestSupport.failures > 0 {
            print("\n\(BackgroundCursorContractTestSupport.failures) background cursor contract test(s) failed")
            exit(1)
        }
        print("\nAll background cursor public API contract tests passed")
    }
}
