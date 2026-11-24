import Carbon
import Foundation

struct TextCommandHotKey: Codable, Equatable {
    enum RecordingDecision: Equatable {
        case cancel
        case restoreDefault
        case waitForKey
        case invalid
        case commit(TextCommandHotKey)
    }

    static let legacyDefault = TextCommandHotKey(
        keyCode: UInt32(kVK_ANSI_T),
        modifiers: UInt32(controlKey | optionKey)
    )
    static let `default` = TextCommandHotKey(
        keyCode: UInt32(kVK_ANSI_Grave),
        modifiers: 0
    )

    let keyCode: UInt32
    let modifiers: UInt32

    private enum CodingKeys: String, CodingKey {
        case keyCode
        case modifiers
    }

    init(keyCode: UInt32, modifiers: UInt32) {
        let normalized = ScreenshotHotKey(keyCode: keyCode, modifiers: modifiers)
        self.keyCode = normalized.keyCode
        self.modifiers = normalized.modifiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            keyCode: try container.decode(UInt32.self, forKey: .keyCode),
            modifiers: try container.decode(UInt32.self, forKey: .modifiers)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(modifiers, forKey: .modifiers)
    }

    var isValid: Bool {
        screenshotHotKey.isValid
    }

    var displayString: String {
        screenshotHotKey.displayString
    }

    static func recordingDecision(keyCode: UInt32?, modifiers: UInt32) -> RecordingDecision {
        switch ScreenshotHotKey.recordingDecision(keyCode: keyCode, modifiers: modifiers) {
        case .cancel:
            return .cancel
        case .restoreDefault:
            return .restoreDefault
        case .waitForKey:
            return .waitForKey
        case .invalid:
            return .invalid
        case .commit(let value):
            return .commit(TextCommandHotKey(
                keyCode: value.keyCode,
                modifiers: value.modifiers
            ))
        }
    }

    var screenshotHotKey: ScreenshotHotKey {
        ScreenshotHotKey(keyCode: keyCode, modifiers: modifiers)
    }
}

protocol TextCommandHotKeyRegistration: AnyObject {
    var hotKey: TextCommandHotKey { get }
    var isActive: Bool { get }
    func activate()
    @discardableResult func invalidate() -> OSStatus
}

protocol TextCommandHotKeyRegistering {
    func register(
        _ hotKey: TextCommandHotKey,
        id: UInt32,
        initiallyActive: Bool,
        action: @escaping () -> Void
    ) -> Result<any TextCommandHotKeyRegistration, HotKeyRegistrationError>
}

private final class TextCommandHotKeyRegistrationAdapter: TextCommandHotKeyRegistration {
    let hotKey: TextCommandHotKey
    private let base: any HotKeyRegistration

    var isActive: Bool { base.isActive }

    init(hotKey: TextCommandHotKey, base: any HotKeyRegistration) {
        self.hotKey = hotKey
        self.base = base
    }

    func activate() {
        base.activate()
    }

    @discardableResult
    func invalidate() -> OSStatus {
        base.invalidate()
    }
}

final class TextCommandHotKeyRegistrarAdapter: TextCommandHotKeyRegistering {
    private let base: any HotKeyRegistering

    init(base: any HotKeyRegistering) {
        self.base = base
    }

    func register(
        _ hotKey: TextCommandHotKey,
        id: UInt32,
        initiallyActive: Bool,
        action: @escaping () -> Void
    ) -> Result<any TextCommandHotKeyRegistration, HotKeyRegistrationError> {
        switch base.register(
            hotKey.screenshotHotKey,
            id: id,
            initiallyActive: initiallyActive,
            action: action
        ) {
        case .success(let registration):
            return .success(TextCommandHotKeyRegistrationAdapter(
                hotKey: hotKey,
                base: registration
            ))
        case .failure(let error):
            return .failure(error)
        }
    }
}

enum TextCommandHotKeyApplyResult: Equatable {
    case applied
    case unchanged
    case invalid
    case conflictsWithScreenshot
    case registrationFailed
    case persistenceFailed(candidateCleanupFailed: Bool)
    case oldRegistrationInvalidationFailed(
        configRollbackFailed: Bool,
        candidateCleanupFailed: Bool
    )
    case modificationLocked
}

final class TextCommandHotKeyManager {
    private let registrar: any TextCommandHotKeyRegistering
    private let screenshotHotKeyProvider: () -> ScreenshotHotKey
    private let persist: (TextCommandHotKey) -> Bool
    private let onTextCommand: () -> Void
    private var nextID: UInt32 = 1_001
    private var currentRegistration: (any TextCommandHotKeyRegistration)?
    private var pendingCandidateRegistration: (any TextCommandHotKeyRegistration)?
    private var recordingHandler: ((TextCommandHotKey) -> Void)?

    private(set) var effectiveHotKey: TextCommandHotKey
    private(set) var isModificationLocked = false
    private(set) var startupRegistrationError: HotKeyRegistrationError?
    private(set) var didFallbackToDefault = false

    var hasActiveRegistration: Bool {
        currentRegistration?.isActive == true
    }

    convenience init(
        savedHotKey: TextCommandHotKey,
        screenshotHotKey: ScreenshotHotKey,
        registrar: any TextCommandHotKeyRegistering,
        persist: @escaping (TextCommandHotKey) -> Bool,
        onTextCommand: @escaping () -> Void
    ) {
        self.init(
            savedHotKey: savedHotKey,
            screenshotHotKeyProvider: { screenshotHotKey },
            registrar: registrar,
            persist: persist,
            onTextCommand: onTextCommand
        )
    }

    init(
        savedHotKey: TextCommandHotKey,
        screenshotHotKeyProvider: @escaping () -> ScreenshotHotKey,
        registrar: any TextCommandHotKeyRegistering,
        persist: @escaping (TextCommandHotKey) -> Bool,
        onTextCommand: @escaping () -> Void
    ) {
        self.registrar = registrar
        self.screenshotHotKeyProvider = screenshotHotKeyProvider
        self.persist = persist
        self.onTextCommand = onTextCommand

        let validSaved = savedHotKey.isValid ? savedHotKey : .default
        let initialHotKey = Self.conflicts(
            validSaved,
            screenshot: screenshotHotKeyProvider()
        ) ? .default : validSaved
        effectiveHotKey = initialHotKey
        didFallbackToDefault = initialHotKey != savedHotKey

        switch register(initialHotKey, initiallyActive: true) {
        case .success(let registration):
            currentRegistration = registration
            if initialHotKey != savedHotKey { _ = persist(initialHotKey) }
        case .failure(let error):
            startupRegistrationError = error
            guard initialHotKey != .default,
                  !Self.conflicts(.default, screenshot: screenshotHotKeyProvider()) else { return }
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

    func beginRecording(_ handler: @escaping (TextCommandHotKey) -> Void) {
        recordingHandler = handler
    }

    func endRecording() {
        recordingHandler = nil
    }

    func apply(_ candidate: TextCommandHotKey) -> TextCommandHotKeyApplyResult {
        guard !isModificationLocked else { return .modificationLocked }
        guard candidate.isValid else { return .invalid }
        guard !Self.conflicts(candidate, screenshot: screenshotHotKeyProvider()) else {
            return .conflictsWithScreenshot
        }
        if candidate == effectiveHotKey, currentRegistration != nil {
            return .unchanged
        }

        let oldHotKey = effectiveHotKey
        let candidateRegistration: any TextCommandHotKeyRegistration
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
        _ hotKey: TextCommandHotKey,
        initiallyActive: Bool
    ) -> Result<any TextCommandHotKeyRegistration, HotKeyRegistrationError> {
        let id = nextID
        nextID &+= 1
        return registrar.register(
            hotKey,
            id: id,
            initiallyActive: initiallyActive,
            action: { [weak self] in self?.route(hotKey) }
        )
    }

    private func route(_ hotKey: TextCommandHotKey) {
        if let recordingHandler {
            recordingHandler(hotKey)
        } else {
            onTextCommand()
        }
    }

    private static func conflicts(
        _ textCommand: TextCommandHotKey,
        screenshot: ScreenshotHotKey
    ) -> Bool {
        textCommand.keyCode == screenshot.keyCode
            && textCommand.modifiers == screenshot.modifiers
    }
}

final class TextCommandHotKeyRecordingCoordinator {
    private let beginRouting: (@escaping (TextCommandHotKey) -> Void) -> Void
    private let endRouting: () -> Void

    private(set) var isRecording = false

    init(
        beginRouting: @escaping (@escaping (TextCommandHotKey) -> Void) -> Void,
        endRouting: @escaping () -> Void
    ) {
        self.beginRouting = beginRouting
        self.endRouting = endRouting
    }

    func beginRecording(_ handler: @escaping (TextCommandHotKey) -> Void) {
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
