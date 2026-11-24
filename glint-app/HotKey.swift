import Carbon
import Foundation

enum HotKeyRegistrationError: Error, Equatable, CustomStringConvertible {
    case eventHandlerInstallationFailed(OSStatus)
    case registrationFailed(OSStatus)

    var description: String {
        switch self {
        case .eventHandlerInstallationFailed(let status):
            return "event handler installation failed (\(status))"
        case .registrationFailed(let status):
            return "hot-key registration failed (\(status))"
        }
    }
}

protocol HotKeyRegistration: AnyObject {
    var hotKey: ScreenshotHotKey { get }
    var isActive: Bool { get }
    func activate()
    @discardableResult func invalidate() -> OSStatus
}

protocol HotKeyRegistering {
    func register(
        _ hotKey: ScreenshotHotKey,
        id: UInt32,
        initiallyActive: Bool,
        action: @escaping () -> Void
    ) -> Result<any HotKeyRegistration, HotKeyRegistrationError>
}

protocol CarbonHotKeySystemBoundary: AnyObject {
    func installEventHandler(_ handler: @escaping (UInt32) -> Void) -> OSStatus
    func registerEventHotKey(
        _ hotKey: ScreenshotHotKey,
        id: UInt32
    ) -> (status: OSStatus, token: UInt64?)
    func unregisterEventHotKey(token: UInt64) -> OSStatus
}

private final class SystemCarbonHotKeyBoundary: CarbonHotKeySystemBoundary {
    private static let signature = OSType(0x474C4E54) // 'GLNT'

    private let lock = NSLock()
    private var handlerRef: EventHandlerRef?
    private var handler: ((UInt32) -> Void)?
    private var nextToken: UInt64 = 1
    private var hotKeyRefs: [UInt64: EventHotKeyRef] = [:]

    func installEventHandler(_ handler: @escaping (UInt32) -> Void) -> OSStatus {
        self.handler = handler
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var installedRef: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context -> OSStatus in
                guard let event, let context else { return OSStatus(paramErr) }
                var hotKeyID = EventHotKeyID()
                let readStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard readStatus == noErr else { return readStatus }
                let owner = Unmanaged<SystemCarbonHotKeyBoundary>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                owner.handler?(hotKeyID.id)
                return noErr
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &installedRef
        )
        guard status == noErr else {
            self.handler = nil
            return status
        }
        handlerRef = installedRef
        return noErr
    }

    func registerEventHotKey(
        _ hotKey: ScreenshotHotKey,
        id: UInt32
    ) -> (status: OSStatus, token: UInt64?) {
        let eventID = EventHotKeyID(signature: Self.signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            eventID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            return (status == noErr ? OSStatus(paramErr) : status, nil)
        }

        lock.lock()
        let token = nextToken
        nextToken &+= 1
        hotKeyRefs[token] = ref
        lock.unlock()
        return (noErr, token)
    }

    func unregisterEventHotKey(token: UInt64) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        guard let ref = hotKeyRefs[token] else {
            return noErr
        }

        let status = UnregisterEventHotKey(ref)
        if status == noErr {
            hotKeyRefs.removeValue(forKey: token)
        }
        return status
    }

    deinit {
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

private final class HotKeyActionGate {
    private let lock = NSLock()
    private var active: Bool
    let action: () -> Void

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    init(isActive: Bool, action: @escaping () -> Void) {
        self.active = isActive
        self.action = action
    }

    func activate() {
        lock.lock()
        active = true
        lock.unlock()
    }

    func deactivate() {
        lock.lock()
        active = false
        lock.unlock()
    }

    func fire() {
        guard isActive else { return }
        action()
    }
}

private final class CarbonHotKeyRegistration: HotKeyRegistration {
    private enum InvalidationState {
        case active(UInt64)
        case invalidating(UInt64)
        case inactive
    }

    let hotKey: ScreenshotHotKey
    private let invalidationCondition = NSCondition()
    private var invalidationState: InvalidationState
    private let systemBoundary: any CarbonHotKeySystemBoundary
    private let gate: HotKeyActionGate
    private let removeAction: () -> Void

    var isActive: Bool { gate.isActive }

    init(
        hotKey: ScreenshotHotKey,
        token: UInt64,
        systemBoundary: any CarbonHotKeySystemBoundary,
        gate: HotKeyActionGate,
        removeAction: @escaping () -> Void
    ) {
        self.hotKey = hotKey
        self.invalidationState = .active(token)
        self.systemBoundary = systemBoundary
        self.gate = gate
        self.removeAction = removeAction
    }

    func activate() {
        gate.activate()
    }

    @discardableResult
    func invalidate() -> OSStatus {
        let token: UInt64
        invalidationCondition.lock()
        acquireToken: while true {
            switch invalidationState {
            case .inactive:
                invalidationCondition.unlock()
                return noErr
            case .invalidating:
                invalidationCondition.wait()
            case .active(let activeToken):
                token = activeToken
                invalidationState = .invalidating(activeToken)
                invalidationCondition.unlock()
                break acquireToken
            }
        }

        let status = systemBoundary.unregisterEventHotKey(token: token)
        invalidationCondition.lock()
        if status == noErr {
            invalidationState = .inactive
            gate.deactivate()
        } else {
            invalidationState = .active(token)
        }
        invalidationCondition.broadcast()
        invalidationCondition.unlock()

        if status == noErr { removeAction() }
        return status
    }

    deinit {
        _ = invalidate()
    }
}

final class CarbonHotKeyRegistrar: HotKeyRegistering {
    private let lock = NSLock()
    private var handlerInstalled = false
    private var actions: [UInt32: HotKeyActionGate] = [:]
    private let systemBoundary: any CarbonHotKeySystemBoundary
    private let logger: (String) -> Void

    init(
        systemBoundary: any CarbonHotKeySystemBoundary = SystemCarbonHotKeyBoundary(),
        logger: @escaping (String) -> Void = { _ in }
    ) {
        self.systemBoundary = systemBoundary
        self.logger = logger
    }

    func register(
        _ hotKey: ScreenshotHotKey,
        id: UInt32,
        initiallyActive: Bool,
        action: @escaping () -> Void
    ) -> Result<any HotKeyRegistration, HotKeyRegistrationError> {
        let handlerStatus = ensureEventHandler()
        guard handlerStatus == noErr else {
            logger("HOTKEY event handler install failed status=\(handlerStatus)")
            return .failure(.eventHandlerInstallationFailed(handlerStatus))
        }

        let gate = HotKeyActionGate(isActive: initiallyActive, action: action)
        lock.lock()
        if actions[id] != nil {
            lock.unlock()
            logger("HOTKEY duplicate id=\(id)")
            return .failure(.registrationFailed(OSStatus(paramErr)))
        }
        actions[id] = gate
        lock.unlock()

        let result = systemBoundary.registerEventHotKey(hotKey, id: id)
        guard result.status == noErr, let token = result.token else {
            removeAction(id: id)
            let status = result.status == noErr ? OSStatus(paramErr) : result.status
            logger("HOTKEY register failed status=\(status) keyCode=\(hotKey.keyCode) modifiers=\(hotKey.modifiers)")
            return .failure(.registrationFailed(status))
        }

        logger("HOTKEY registered id=\(id) keyCode=\(hotKey.keyCode) modifiers=\(hotKey.modifiers) active=\(initiallyActive)")
        let registration = CarbonHotKeyRegistration(
            hotKey: hotKey,
            token: token,
            systemBoundary: systemBoundary,
            gate: gate,
            removeAction: { [weak self] in self?.removeAction(id: id) }
        )
        return .success(registration)
    }

    private func ensureEventHandler() -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        if handlerInstalled { return noErr }
        let status = systemBoundary.installEventHandler { [weak self] id in
            self?.fireAction(id: id)
        }
        guard status == noErr else { return status }
        handlerInstalled = true
        return noErr
    }

    private func fireAction(id: UInt32) {
        lock.lock()
        let gate = actions[id]
        lock.unlock()
        gate?.fire()
    }

    private func removeAction(id: UInt32) {
        lock.lock()
        actions.removeValue(forKey: id)
        lock.unlock()
    }
}

enum ScreenshotHotKeyApplyResult: Equatable {
    case applied
    case unchanged
    case invalid
    case conflictsWithOtherAction
    case registrationFailed
    case persistenceFailed(candidateCleanupFailed: Bool)
    case oldRegistrationInvalidationFailed(configRollbackFailed: Bool, candidateCleanupFailed: Bool)
    case modificationLocked
}

final class ScreenshotHotKeyManager {
    private let registrar: any HotKeyRegistering
    private let persist: (ScreenshotHotKey) -> Bool
    private let onScreenshot: () -> Void
    private let reservedHotKeyProvider: () -> ScreenshotHotKey?
    private var nextID: UInt32 = 1
    private var currentRegistration: (any HotKeyRegistration)?
    private var pendingCandidateRegistration: (any HotKeyRegistration)?
    private var recordingHandler: ((ScreenshotHotKey) -> Void)?

    private(set) var effectiveHotKey: ScreenshotHotKey
    private(set) var isModificationLocked = false
    private(set) var startupRegistrationError: HotKeyRegistrationError?
    private(set) var didFallbackToDefault = false

    var pendingCandidateHotKey: ScreenshotHotKey? {
        pendingCandidateRegistration?.hotKey
    }

    var hasActiveRegistration: Bool {
        currentRegistration?.isActive == true
    }

    init(
        savedHotKey: ScreenshotHotKey,
        registrar: any HotKeyRegistering,
        persist: @escaping (ScreenshotHotKey) -> Bool,
        reservedHotKeyProvider: @escaping () -> ScreenshotHotKey? = { nil },
        onScreenshot: @escaping () -> Void
    ) {
        self.registrar = registrar
        self.persist = persist
        self.reservedHotKeyProvider = reservedHotKeyProvider
        self.onScreenshot = onScreenshot
        let initialHotKey = savedHotKey.isValid ? savedHotKey : .default
        self.effectiveHotKey = initialHotKey
        self.didFallbackToDefault = initialHotKey != savedHotKey

        switch register(initialHotKey, initiallyActive: true) {
        case .success(let registration):
            currentRegistration = registration
            if initialHotKey != savedHotKey { _ = persist(initialHotKey) }
        case .failure(let error):
            startupRegistrationError = error
            guard initialHotKey != .default else { return }
            switch register(.default, initiallyActive: true) {
            case .success(let fallback):
                currentRegistration = fallback
                effectiveHotKey = .default
                didFallbackToDefault = true
                _ = persist(.default)
            case .failure(let fallbackError):
                startupRegistrationError = fallbackError
            }
        }
    }

    func beginRecording(_ handler: @escaping (ScreenshotHotKey) -> Void) {
        recordingHandler = handler
    }

    func endRecording() {
        recordingHandler = nil
    }

    func apply(_ candidate: ScreenshotHotKey) -> ScreenshotHotKeyApplyResult {
        guard !isModificationLocked else { return .modificationLocked }
        guard candidate.isValid else { return .invalid }
        if candidate == reservedHotKeyProvider() {
            return .conflictsWithOtherAction
        }
        if candidate == effectiveHotKey, currentRegistration != nil {
            return .unchanged
        }

        let oldHotKey = effectiveHotKey
        let candidateRegistration: any HotKeyRegistration
        switch register(candidate, initiallyActive: false) {
        case .failure:
            return .registrationFailed
        case .success(let registration):
            candidateRegistration = registration
        }

        guard persist(candidate) else {
            let cleanupFailed = candidateRegistration.invalidate() != noErr
            if cleanupFailed {
                pendingCandidateRegistration = candidateRegistration
                isModificationLocked = true
            }
            return .persistenceFailed(candidateCleanupFailed: cleanupFailed)
        }

        if let currentRegistration {
            let oldInvalidationStatus = currentRegistration.invalidate()
            if oldInvalidationStatus != noErr {
                let configRollbackFailed = !persist(oldHotKey)
                let candidateCleanupFailed = candidateRegistration.invalidate() != noErr
                if candidateCleanupFailed {
                    pendingCandidateRegistration = candidateRegistration
                }
                if configRollbackFailed || candidateCleanupFailed {
                    isModificationLocked = true
                }
                return .oldRegistrationInvalidationFailed(
                    configRollbackFailed: configRollbackFailed,
                    candidateCleanupFailed: candidateCleanupFailed
                )
            }
        }

        candidateRegistration.activate()
        currentRegistration = candidateRegistration
        pendingCandidateRegistration = nil
        effectiveHotKey = candidate
        startupRegistrationError = nil
        didFallbackToDefault = false
        return .applied
    }

    private func register(
        _ hotKey: ScreenshotHotKey,
        initiallyActive: Bool
    ) -> Result<any HotKeyRegistration, HotKeyRegistrationError> {
        let id = nextID
        nextID &+= 1
        return registrar.register(
            hotKey,
            id: id,
            initiallyActive: initiallyActive,
            action: { [weak self] in self?.route(hotKey) }
        )
    }

    private func route(_ hotKey: ScreenshotHotKey) {
        if let recordingHandler {
            recordingHandler(hotKey)
        } else {
            onScreenshot()
        }
    }
}

final class ScreenshotHotKeyRecordingCoordinator {
    private let beginRouting: (@escaping (ScreenshotHotKey) -> Void) -> Void
    private let endRouting: () -> Void

    private(set) var isRecording = false

    init(
        beginRouting: @escaping (@escaping (ScreenshotHotKey) -> Void) -> Void,
        endRouting: @escaping () -> Void
    ) {
        self.beginRouting = beginRouting
        self.endRouting = endRouting
    }

    func beginRecording(_ handler: @escaping (ScreenshotHotKey) -> Void) {
        isRecording = true
        beginRouting(handler)
    }

    func endRecording() {
        guard isRecording else { return }
        isRecording = false
        endRouting()
    }

    func settingsDidSelectBasicTab(_ isBasicTab: Bool) {
        if !isBasicTab { endRecording() }
    }

    func settingsWindowDidResignKey() {
        endRecording()
    }

    func settingsWindowWillClose() {
        endRecording()
    }
}
