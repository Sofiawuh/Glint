import Foundation

// Regression contract: translator output is untrusted and may contain text that
// happens to equal another fragment's private assembly placeholder. Reassembly
// must either reject that response or perform one stable template substitution;
// it must never process the injected placeholder a second time.

enum TranslationDocumentPlaceholderInjectionTestSupport {
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

final class TestTranslationDocumentPlaceholderInjection {
    static func test_translationContainingAnotherFragmentsPrivatePlaceholder_isNotReplacedTwice() {
        let document = TranslationDocument(formattedText: "Alpha\nBeta")
        guard document.fragments.count == 2 else {
            TranslationDocumentPlaceholderInjectionTestSupport.expect(
                false,
                "TestTranslationDocumentPlaceholderInjection.test_translationContainingAnotherFragmentsPrivatePlaceholder_isNotReplacedTwice"
            )
            return
        }

        let first = document.fragments[0]
        let second = document.fragments[1]
        let injectedPrivatePlaceholder = "\u{E000}\(second.id)\u{E001}"
        let firstTranslation = "translated-alpha[\(injectedPrivatePlaceholder)]"
        let secondTranslation = "translated-beta"
        let result = document.reassemble([
            TranslationFragmentResponse(
                id: first.id,
                translatedText: firstTranslation,
                detectedLanguage: "en"
            ),
            TranslationFragmentResponse(
                id: second.id,
                translatedText: secondTranslation,
                detectedLanguage: "en"
            )
        ])

        let stableSinglePassResult = "\(firstTranslation)\n\(secondTranslation)"
        TranslationDocumentPlaceholderInjectionTestSupport.expect(
            result == nil || result?.text == stableSinglePassResult,
            "TestTranslationDocumentPlaceholderInjection.test_translationContainingAnotherFragmentsPrivatePlaceholder_isNotReplacedTwice"
        )
    }
}

@main
enum TranslationDocumentPlaceholderInjectionTests {
    static func main() {
        TestTranslationDocumentPlaceholderInjection
            .test_translationContainingAnotherFragmentsPrivatePlaceholder_isNotReplacedTwice()
        print(
            TranslationDocumentPlaceholderInjectionTestSupport.failures == 0
                ? "ALL PASS"
                : "\(TranslationDocumentPlaceholderInjectionTestSupport.failures) FAILURES"
        )
        exit(TranslationDocumentPlaceholderInjectionTestSupport.failures == 0 ? 0 : 1)
    }
}
