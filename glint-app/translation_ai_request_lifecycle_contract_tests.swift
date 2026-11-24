import Foundation

// 翻译工作台 AI 主控请求身份黑盒契约。
// 不创建 UI、Task 或网络请求，只验证旧回调不得完成或清理新请求。
//
// 预期最小运行命令：
//   swiftc -parse-as-library -o /tmp/glint_translation_ai_request_lifecycle_contract_test \
//     TranslationFormatting.swift RecentResults.swift TranslationWorkbench.swift \
//     translation_ai_request_lifecycle_contract_tests.swift -framework Foundation \
//     && /tmp/glint_translation_ai_request_lifecycle_contract_test

enum TranslationAIRequestLifecycleContractTestSupport {
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

final class TestTranslationAIRequestLifecycle {
    static func test_restoredHistoryStartsNewIdentityAndRejectsOldCompletion() {
        var lifecycle = TranslationAIRequestLifecycle()
        let oldRequest = lifecycle.begin(historyID: "fictional-history")

        lifecycle.invalidateAll()
        let restoredRequest = lifecycle.begin(historyID: "fictional-history")
        let oldAccepted = lifecycle.finish(oldRequest)

        TranslationAIRequestLifecycleContractTestSupport.expect(
            oldRequest != restoredRequest
                && !oldAccepted
                && lifecycle.isCurrent(restoredRequest),
            "TestTranslationAIRequestLifecycle.test_restoredHistoryStartsNewIdentityAndRejectsOldCompletion"
        )
    }

    static func test_oldCancellationCannotClearNewerRequestIdentity() {
        var lifecycle = TranslationAIRequestLifecycle()
        let first = lifecycle.begin(historyID: "fictional-history")
        let second = lifecycle.begin(historyID: "fictional-history")

        let oldCancellationAccepted = lifecycle.finish(first)
        let currentCompletionAccepted = lifecycle.finish(second)

        TranslationAIRequestLifecycleContractTestSupport.expect(
            !oldCancellationAccepted
                && currentCompletionAccepted
                && !lifecycle.isCurrent(second),
            "TestTranslationAIRequestLifecycle.test_oldCancellationCannotClearNewerRequestIdentity"
        )
    }
}

@main
enum TranslationAIRequestLifecycleContractTests {
    static func main() {
        TestTranslationAIRequestLifecycle.test_restoredHistoryStartsNewIdentityAndRejectsOldCompletion()
        TestTranslationAIRequestLifecycle.test_oldCancellationCannotClearNewerRequestIdentity()

        print(
            TranslationAIRequestLifecycleContractTestSupport.failures == 0
                ? "ALL PASS"
                : "\(TranslationAIRequestLifecycleContractTestSupport.failures) FAILURES"
        )
        exit(TranslationAIRequestLifecycleContractTestSupport.failures == 0 ? 0 : 1)
    }
}
