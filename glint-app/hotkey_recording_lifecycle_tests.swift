import Carbon
import Foundation

// Black-box lifecycle contract for the settings-owned recording session.
// This test intentionally requires a small production coordinator so AppKit window/tab
// events can be verified without launching the app or loading the user's real config.

enum HotKeyRecordingLifecycleTestSupport {
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

final class LifecycleTestRegistration: HotKeyRegistration {
    let hotKey: ScreenshotHotKey
    private let action: () -> Void
    private(set) var isActive: Bool

    init(hotKey: ScreenshotHotKey, initiallyActive: Bool, action: @escaping () -> Void) {
        self.hotKey = hotKey
        self.isActive = initiallyActive
        self.action = action
    }

    func activate() { isActive = true }

    @discardableResult
    func invalidate() -> OSStatus {
        isActive = false
        return noErr
    }

    func fire() {
        if isActive { action() }
    }
}

final class LifecycleTestRegistrar: HotKeyRegistering {
    private(set) var registrations: [LifecycleTestRegistration] = []

    func register(
        _ hotKey: ScreenshotHotKey,
        id: UInt32,
        initiallyActive: Bool,
        action: @escaping () -> Void
    ) -> Result<any HotKeyRegistration, HotKeyRegistrationError> {
        let registration = LifecycleTestRegistration(
            hotKey: hotKey,
            initiallyActive: initiallyActive,
            action: action
        )
        registrations.append(registration)
        return .success(registration)
    }
}

final class TestHotKeyRecordingSessionLifecycle {
    private struct Fixture {
        let registrar: LifecycleTestRegistrar
        let coordinator: ScreenshotHotKeyRecordingCoordinator
        let screenshots: () -> Int
    }

    private static func makeFixture() -> Fixture {
        let registrar = LifecycleTestRegistrar()
        var screenshotCount = 0
        let manager = ScreenshotHotKeyManager(
            savedHotKey: .default,
            registrar: registrar,
            persist: { _ in true },
            onScreenshot: { screenshotCount += 1 }
        )
        let coordinator = ScreenshotHotKeyRecordingCoordinator(
            beginRouting: { manager.beginRecording($0) },
            endRouting: { manager.endRecording() }
        )
        return Fixture(
            registrar: registrar,
            coordinator: coordinator,
            screenshots: { screenshotCount }
        )
    }

    private static func verifyEndingEventRestoresScreenshotRoute(
        _ name: String,
        event: (ScreenshotHotKeyRecordingCoordinator) -> Void
    ) {
        let fixture = makeFixture()
        var recorded: ScreenshotHotKey?
        fixture.coordinator.beginRecording { recorded = $0 }
        fixture.registrar.registrations[0].fire()
        let interceptedWhileRecording = recorded == .default && fixture.screenshots() == 0

        event(fixture.coordinator)
        fixture.registrar.registrations[0].fire()

        HotKeyRecordingLifecycleTestSupport.expect(
            interceptedWhileRecording
                && !fixture.coordinator.isRecording
                && fixture.screenshots() == 1,
            name
        )
    }

    static func test_switchingAwayFromBasicTab_endsRecordingAndRestoresScreenshotRoute() {
        verifyEndingEventRestoresScreenshotRoute(
            "TestHotKeyRecordingSessionLifecycle.test_switchingAwayFromBasicTab_endsRecordingAndRestoresScreenshotRoute",
            event: { $0.settingsDidSelectBasicTab(false) }
        )
    }

    static func test_reselectingBasicTab_keepsRecordingSessionActive() {
        let fixture = makeFixture()
        var recorded: ScreenshotHotKey?
        fixture.coordinator.beginRecording { recorded = $0 }

        fixture.coordinator.settingsDidSelectBasicTab(true)
        fixture.registrar.registrations[0].fire()

        HotKeyRecordingLifecycleTestSupport.expect(
            fixture.coordinator.isRecording
                && recorded == .default
                && fixture.screenshots() == 0,
            "TestHotKeyRecordingSessionLifecycle.test_reselectingBasicTab_keepsRecordingSessionActive"
        )
    }

    static func test_settingsWindowResigningKey_endsRecordingAndRestoresScreenshotRoute() {
        verifyEndingEventRestoresScreenshotRoute(
            "TestHotKeyRecordingSessionLifecycle.test_settingsWindowResigningKey_endsRecordingAndRestoresScreenshotRoute",
            event: { $0.settingsWindowDidResignKey() }
        )
    }

    static func test_settingsWindowClosing_endsRecordingAndRestoresScreenshotRoute() {
        verifyEndingEventRestoresScreenshotRoute(
            "TestHotKeyRecordingSessionLifecycle.test_settingsWindowClosing_endsRecordingAndRestoresScreenshotRoute",
            event: { $0.settingsWindowWillClose() }
        )
    }
}

@main
enum HotKeyRecordingLifecycleTests {
    static func main() {
        TestHotKeyRecordingSessionLifecycle
            .test_switchingAwayFromBasicTab_endsRecordingAndRestoresScreenshotRoute()
        TestHotKeyRecordingSessionLifecycle.test_reselectingBasicTab_keepsRecordingSessionActive()
        TestHotKeyRecordingSessionLifecycle
            .test_settingsWindowResigningKey_endsRecordingAndRestoresScreenshotRoute()
        TestHotKeyRecordingSessionLifecycle
            .test_settingsWindowClosing_endsRecordingAndRestoresScreenshotRoute()

        print(
            HotKeyRecordingLifecycleTestSupport.failures == 0
                ? "ALL PASS"
                : "\(HotKeyRecordingLifecycleTestSupport.failures) FAILURES"
        )
        exit(HotKeyRecordingLifecycleTestSupport.failures == 0 ? 0 : 1)
    }
}
