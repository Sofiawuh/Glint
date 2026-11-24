import AppKit
import Foundation

// Regression contract for the real NSTextAttachmentCell subclass. The fixture
// contains no user data and archives only an in-memory HRCell instance.

enum MarkdownHRCellCodingTestSupport {
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

final class TestMarkdownHRCellCoding {
    static func test_archiveThenUnarchive_returnsUsableCellWithoutCrashing() {
        let original = HRCell(width: 137)
        let data: Data
        do {
            data = try NSKeyedArchiver.archivedData(
                withRootObject: original,
                requiringSecureCoding: false
            )
        } catch {
            MarkdownHRCellCodingTestSupport.expect(
                false,
                "TestMarkdownHRCellCoding.test_archiveThenUnarchive_returnsUsableCellWithoutCrashing"
            )
            return
        }

        let decoded: Any?
        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = false
            decoded = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
            unarchiver.finishDecoding()
        } catch {
            MarkdownHRCellCodingTestSupport.expect(
                false,
                "TestMarkdownHRCellCoding.test_archiveThenUnarchive_returnsUsableCellWithoutCrashing"
            )
            return
        }

        let restored = decoded as? HRCell
        MarkdownHRCellCodingTestSupport.expect(
            restored != nil
                && restored?.cellSize().width ?? 0 >= 10
                && restored?.cellSize().height ?? 0 > 0,
            "TestMarkdownHRCellCoding.test_archiveThenUnarchive_returnsUsableCellWithoutCrashing"
        )
    }
}

@main
enum MarkdownHRCellCodingTests {
    static func main() {
        TestMarkdownHRCellCoding
            .test_archiveThenUnarchive_returnsUsableCellWithoutCrashing()
        print(
            MarkdownHRCellCodingTestSupport.failures == 0
                ? "ALL PASS"
                : "\(MarkdownHRCellCodingTestSupport.failures) FAILURES"
        )
        exit(MarkdownHRCellCodingTestSupport.failures == 0 ? 0 : 1)
    }
}
