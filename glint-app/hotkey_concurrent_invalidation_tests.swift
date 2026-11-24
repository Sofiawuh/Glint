import Carbon
import Foundation

// The fake boundary never registers or unregisters a real system-wide hot key.
// It makes the first unregister slow enough for concurrent invalidate calls to
// overlap, then records how many calls reached the underlying system boundary.

enum HotKeyConcurrentInvalidationTestSupport {
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

final class ConcurrentUnregisterBoundary: CarbonHotKeySystemBoundary {
    private let lock = NSLock()
    private let firstCallEntered = DispatchSemaphore(value: 0)
    private let releaseFirstCall = DispatchSemaphore(value: 0)
    private var unregisterStatuses: [OSStatus]
    private var callCount = 0

    init(unregisterStatuses: [OSStatus]) {
        self.unregisterStatuses = unregisterStatuses
    }

    var unregisterCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return callCount
    }

    func installEventHandler(_ handler: @escaping (UInt32) -> Void) -> OSStatus {
        noErr
    }

    func registerEventHotKey(
        _ hotKey: ScreenshotHotKey,
        id: UInt32
    ) -> (status: OSStatus, token: UInt64?) {
        (noErr, 9001)
    }

    func unregisterEventHotKey(token: UInt64) -> OSStatus {
        lock.lock()
        callCount += 1
        let currentCall = callCount
        let status = unregisterStatuses.isEmpty ? noErr : unregisterStatuses.removeFirst()
        lock.unlock()

        if currentCall == 1 {
            firstCallEntered.signal()
            _ = releaseFirstCall.wait(timeout: .now() + 2)
        }
        return status
    }

    func waitForFirstUnregister() -> Bool {
        firstCallEntered.wait(timeout: .now() + 2) == .success
    }

    func releaseFirstUnregister() {
        releaseFirstCall.signal()
    }
}

final class TestHotKeyConcurrentInvalidation {
    static func makeRegistration(
        boundary: ConcurrentUnregisterBoundary,
        id: UInt32
    ) -> (any HotKeyRegistration)? {
        let registrar = CarbonHotKeyRegistrar(systemBoundary: boundary)
        guard case .success(let registration) = registrar.register(
            .default,
            id: id,
            initiallyActive: true,
            action: {}
        ) else {
            return nil
        }
        return registration
    }

    static func test_concurrentInvalidate_sameRegistrationCallsUnderlyingUnregisterAtMostOnce() {
        let boundary = ConcurrentUnregisterBoundary(unregisterStatuses: [noErr])
        guard let registration = makeRegistration(boundary: boundary, id: 801) else {
            HotKeyConcurrentInvalidationTestSupport.expect(
                false,
                "TestHotKeyConcurrentInvalidation.test_concurrentInvalidate_sameRegistrationCallsUnderlyingUnregisterAtMostOnce"
            )
            return
        }

        let group = DispatchGroup()
        let queue = DispatchQueue(
            label: "fictional.glint.hotkey.concurrent-invalidation",
            attributes: .concurrent
        )
        for _ in 0..<24 {
            group.enter()
            queue.async {
                _ = registration.invalidate()
                group.leave()
            }
        }

        let firstCallObserved = boundary.waitForFirstUnregister()
        // Give already-scheduled invalidations a chance to reach the same token
        // while the first underlying unregister call is deliberately blocked.
        Thread.sleep(forTimeInterval: 0.05)
        boundary.releaseFirstUnregister()
        let completed = group.wait(timeout: .now() + 3) == .success

        HotKeyConcurrentInvalidationTestSupport.expect(
            firstCallObserved && completed && boundary.unregisterCallCount == 1,
            "TestHotKeyConcurrentInvalidation.test_concurrentInvalidate_sameRegistrationCallsUnderlyingUnregisterAtMostOnce"
        )
    }

    static func test_failedInvalidate_canBeRetriedAndRecovered() {
        let fictionalFailure = OSStatus(-9876)
        let boundary = ConcurrentUnregisterBoundary(
            unregisterStatuses: [fictionalFailure, noErr]
        )
        guard let registration = makeRegistration(boundary: boundary, id: 802) else {
            HotKeyConcurrentInvalidationTestSupport.expect(
                false,
                "TestHotKeyConcurrentInvalidation.test_failedInvalidate_canBeRetriedAndRecovered"
            )
            return
        }

        DispatchQueue.global().async {
            boundary.releaseFirstUnregister()
        }
        let firstStatus = registration.invalidate()
        let secondStatus = registration.invalidate()

        HotKeyConcurrentInvalidationTestSupport.expect(
            firstStatus == fictionalFailure
                && secondStatus == noErr
                && boundary.unregisterCallCount == 2
                && registration.isActive == false,
            "TestHotKeyConcurrentInvalidation.test_failedInvalidate_canBeRetriedAndRecovered"
        )
    }
}

@main
enum HotKeyConcurrentInvalidationTests {
    static func main() {
        TestHotKeyConcurrentInvalidation
            .test_concurrentInvalidate_sameRegistrationCallsUnderlyingUnregisterAtMostOnce()
        TestHotKeyConcurrentInvalidation
            .test_failedInvalidate_canBeRetriedAndRecovered()
        print(
            HotKeyConcurrentInvalidationTestSupport.failures == 0
                ? "ALL PASS"
                : "\(HotKeyConcurrentInvalidationTestSupport.failures) FAILURES"
        )
        exit(HotKeyConcurrentInvalidationTestSupport.failures == 0 ? 0 : 1)
    }
}
