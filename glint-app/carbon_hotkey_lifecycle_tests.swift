import Carbon
import Foundation

// Black-box contract for the real Carbon registrar lifecycle. The production boundary
// must adapt these operations to InstallEventHandler/RegisterEventHotKey/
// UnregisterEventHotKey; this fake never registers a real system-wide shortcut.

enum CarbonHotKeyLifecycleTestSupport {
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

final class TestCarbonHotKeySystemBoundary: CarbonHotKeySystemBoundary {
    var installStatuses: [OSStatus]
    var registerStatuses: [OSStatus]
    var unregisterStatuses: [OSStatus]

    private(set) var installCallCount = 0
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    private var eventHandler: ((UInt32) -> Void)?
    private var nextToken: UInt64 = 1

    init(
        installStatuses: [OSStatus] = [noErr],
        registerStatuses: [OSStatus] = [noErr],
        unregisterStatuses: [OSStatus] = [noErr]
    ) {
        self.installStatuses = installStatuses
        self.registerStatuses = registerStatuses
        self.unregisterStatuses = unregisterStatuses
    }

    func installEventHandler(_ handler: @escaping (UInt32) -> Void) -> OSStatus {
        installCallCount += 1
        let status = installStatuses.isEmpty ? noErr : installStatuses.removeFirst()
        if status == noErr { eventHandler = handler }
        return status
    }

    func registerEventHotKey(
        _ hotKey: ScreenshotHotKey,
        id: UInt32
    ) -> (status: OSStatus, token: UInt64?) {
        registerCallCount += 1
        let status = registerStatuses.isEmpty ? noErr : registerStatuses.removeFirst()
        guard status == noErr else { return (status, nil) }
        defer { nextToken += 1 }
        return (noErr, nextToken)
    }

    func unregisterEventHotKey(token: UInt64) -> OSStatus {
        unregisterCallCount += 1
        return unregisterStatuses.isEmpty ? noErr : unregisterStatuses.removeFirst()
    }

    func emitHotKey(id: UInt32) {
        eventHandler?(id)
    }
}

final class TestCarbonHotKeyRegistrarLifecycle {
    static func test_eventHandlerInstallationFailure_doesNotRegisterOrLeaveActionBehind() {
        let boundary = TestCarbonHotKeySystemBoundary(
            installStatuses: [-9850, noErr],
            registerStatuses: [noErr]
        )
        let registrar = CarbonHotKeyRegistrar(systemBoundary: boundary)
        var failedActionCount = 0
        var successfulActionCount = 0

        let failed = registrar.register(
            .default,
            id: 301,
            initiallyActive: true,
            action: { failedActionCount += 1 }
        )
        let recovered = registrar.register(
            .default,
            id: 301,
            initiallyActive: true,
            action: { successfulActionCount += 1 }
        )
        boundary.emitHotKey(id: 301)
        let failedAsExpected: Bool
        if case .failure(let error) = failed {
            failedAsExpected = error == .eventHandlerInstallationFailed(-9850)
        } else {
            failedAsExpected = false
        }

        CarbonHotKeyLifecycleTestSupport.expect(
            failedAsExpected
                && recovered.isSuccess
                && boundary.installCallCount == 2
                && boundary.registerCallCount == 1
                && failedActionCount == 0
                && successfulActionCount == 1,
            "TestCarbonHotKeyRegistrarLifecycle.test_eventHandlerInstallationFailure_doesNotRegisterOrLeaveActionBehind"
        )
    }

    static func test_registrationFailure_removesActionSoSameIDCanBeRegisteredAgain() {
        let boundary = TestCarbonHotKeySystemBoundary(
            registerStatuses: [-9851, noErr]
        )
        let registrar = CarbonHotKeyRegistrar(systemBoundary: boundary)
        var failedActionCount = 0
        var successfulActionCount = 0

        let failed = registrar.register(
            .default,
            id: 302,
            initiallyActive: true,
            action: { failedActionCount += 1 }
        )
        let recovered = registrar.register(
            .default,
            id: 302,
            initiallyActive: true,
            action: { successfulActionCount += 1 }
        )
        boundary.emitHotKey(id: 302)
        let failedAsExpected: Bool
        if case .failure(let error) = failed {
            failedAsExpected = error == .registrationFailed(-9851)
        } else {
            failedAsExpected = false
        }

        CarbonHotKeyLifecycleTestSupport.expect(
            failedAsExpected
                && recovered.isSuccess
                && failedActionCount == 0
                && successfulActionCount == 1,
            "TestCarbonHotKeyRegistrarLifecycle.test_registrationFailure_removesActionSoSameIDCanBeRegisteredAgain"
        )
    }

    static func test_invalidateAfterSuccess_isIdempotentAndUnregistersOnce() {
        let boundary = TestCarbonHotKeySystemBoundary()
        let registrar = CarbonHotKeyRegistrar(systemBoundary: boundary)
        var actionCount = 0
        let result = registrar.register(
            .default,
            id: 303,
            initiallyActive: true,
            action: { actionCount += 1 }
        )
        guard case .success(let registration) = result else {
            CarbonHotKeyLifecycleTestSupport.expect(
                false,
                "TestCarbonHotKeyRegistrarLifecycle.test_invalidateAfterSuccess_isIdempotentAndUnregistersOnce"
            )
            return
        }

        boundary.emitHotKey(id: 303)
        let first = registration.invalidate()
        let second = registration.invalidate()
        boundary.emitHotKey(id: 303)

        CarbonHotKeyLifecycleTestSupport.expect(
            first == noErr
                && second == noErr
                && boundary.unregisterCallCount == 1
                && actionCount == 1,
            "TestCarbonHotKeyRegistrarLifecycle.test_invalidateAfterSuccess_isIdempotentAndUnregistersOnce"
        )
    }

    static func test_unregisterFailure_keepsActionUntilALaterInvalidateSucceeds() {
        let boundary = TestCarbonHotKeySystemBoundary(
            unregisterStatuses: [-9852, noErr]
        )
        let registrar = CarbonHotKeyRegistrar(systemBoundary: boundary)
        var actionCount = 0
        let result = registrar.register(
            .default,
            id: 304,
            initiallyActive: true,
            action: { actionCount += 1 }
        )
        guard case .success(let registration) = result else {
            CarbonHotKeyLifecycleTestSupport.expect(
                false,
                "TestCarbonHotKeyRegistrarLifecycle.test_unregisterFailure_keepsActionUntilALaterInvalidateSucceeds"
            )
            return
        }

        boundary.emitHotKey(id: 304)
        let failedStatus = registration.invalidate()
        boundary.emitHotKey(id: 304)
        let recoveredStatus = registration.invalidate()
        boundary.emitHotKey(id: 304)

        CarbonHotKeyLifecycleTestSupport.expect(
            failedStatus == -9852
                && recoveredStatus == noErr
                && boundary.unregisterCallCount == 2
                && actionCount == 2,
            "TestCarbonHotKeyRegistrarLifecycle.test_unregisterFailure_keepsActionUntilALaterInvalidateSucceeds"
        )
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

@main
enum CarbonHotKeyLifecycleTests {
    static func main() {
        TestCarbonHotKeyRegistrarLifecycle
            .test_eventHandlerInstallationFailure_doesNotRegisterOrLeaveActionBehind()
        TestCarbonHotKeyRegistrarLifecycle
            .test_registrationFailure_removesActionSoSameIDCanBeRegisteredAgain()
        TestCarbonHotKeyRegistrarLifecycle
            .test_invalidateAfterSuccess_isIdempotentAndUnregistersOnce()
        TestCarbonHotKeyRegistrarLifecycle
            .test_unregisterFailure_keepsActionUntilALaterInvalidateSucceeds()

        print(
            CarbonHotKeyLifecycleTestSupport.failures == 0
                ? "ALL PASS"
                : "\(CarbonHotKeyLifecycleTestSupport.failures) FAILURES"
        )
        exit(CarbonHotKeyLifecycleTestSupport.failures == 0 ? 0 : 1)
    }
}
