import Carbon
import Foundation

// Screenshot hot-key value, migration, recording and transaction black-box contracts.
// This executable uses only fictional Azure values and temporary files. It must never
// load AppConfig.shared, the real ~/.config/glint/config.json, or make network requests.
//
// Intended minimal command once the production contracts exist:
//   swiftc -o /tmp/glint_hotkey_test \
//     Config.swift ScreenshotHotKey.swift HotKey.swift hotkey_tests.swift \
//     -framework Carbon -framework Foundation && /tmp/glint_hotkey_test

enum HotKeyTestSupport {
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

final class TestHotKeyRegistration: HotKeyRegistration {
    let hotKey: ScreenshotHotKey
    private let action: () -> Void
    private let onInvalidate: () -> Void
    private var invalidateStatuses: [OSStatus]

    private(set) var isActive: Bool
    private(set) var invalidateCallCount = 0

    init(
        hotKey: ScreenshotHotKey,
        initiallyActive: Bool,
        invalidateStatuses: [OSStatus],
        onInvalidate: @escaping () -> Void,
        action: @escaping () -> Void
    ) {
        self.hotKey = hotKey
        self.isActive = initiallyActive
        self.invalidateStatuses = invalidateStatuses
        self.onInvalidate = onInvalidate
        self.action = action
    }

    func activate() {
        isActive = true
    }

    @discardableResult
    func invalidate() -> OSStatus {
        invalidateCallCount += 1
        onInvalidate()
        let status = invalidateStatuses.isEmpty ? noErr : invalidateStatuses.removeFirst()
        if status == noErr {
            isActive = false
        }
        return status
    }

    func fire() {
        if isActive { action() }
    }
}

final class TestHotKeyRegistrar: HotKeyRegistering {
    enum Outcome {
        case success(invalidateStatuses: [OSStatus] = [noErr])
        case failure(HotKeyRegistrationError)
    }

    var outcomes: [Outcome]
    var events: [String] = []
    private(set) var registerCallCount = 0
    private(set) var registrations: [TestHotKeyRegistration] = []

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func register(
        _ hotKey: ScreenshotHotKey,
        id: UInt32,
        initiallyActive: Bool,
        action: @escaping () -> Void
    ) -> Result<any HotKeyRegistration, HotKeyRegistrationError> {
        registerCallCount += 1
        events.append("register:\(hotKey.keyCode):\(initiallyActive)")
        let outcome = outcomes.isEmpty ? .success() : outcomes.removeFirst()
        switch outcome {
        case .failure(let error):
            return .failure(error)
        case .success(let statuses):
            let registration = TestHotKeyRegistration(
                hotKey: hotKey,
                initiallyActive: initiallyActive,
                invalidateStatuses: statuses,
                onInvalidate: { [weak self] in
                    self?.events.append("invalidate:\(hotKey.keyCode)")
                },
                action: action
            )
            registrations.append(registration)
            return .success(registration)
        }
    }
}

final class TestHotKeyRuntimeState {
    var persisted: ScreenshotHotKey
    var saveOutcomes: [Bool]
    var screenshots = 0

    init(persisted: ScreenshotHotKey, saveOutcomes: [Bool]) {
        self.persisted = persisted
        self.saveOutcomes = saveOutcomes
    }
}

final class TestHotKeyValueContract {
    static func test_defaultValue_isControlOptionE() {
        let value = ScreenshotHotKey.default
        HotKeyTestSupport.expect(
            value.keyCode == UInt32(kVK_ANSI_E)
                && value.modifiers == UInt32(controlKey | optionKey)
                && value.isValid
                && value.displayString == "⌃⌥E",
            "TestHotKeyValueContract.test_defaultValue_isControlOptionE"
        )
    }

    static func test_unmodifiedGraveAndFunctionKeys_areValidAndReadable() {
        let unavailableTranslator: (UInt32) -> String? = { _ in nil }
        let grave = ScreenshotHotKey(
            keyCode: UInt32(kVK_ANSI_Grave),
            modifiers: 0
        )
        let functionKeys = [kVK_F1, kVK_F12, kVK_F20].map {
            ScreenshotHotKey(keyCode: UInt32($0), modifiers: 0)
        }

        HotKeyTestSupport.expect(
            grave.isValid
                && grave.displayString(keyLabelTranslator: unavailableTranslator) == "`"
                && functionKeys.allSatisfy(\.isValid)
                && functionKeys.map(\.displayString) == ["F1", "F12", "F20"],
            "TestHotKeyValueContract.test_unmodifiedGraveAndFunctionKeys_areValidAndReadable"
        )
    }

    static func test_unmodifiedOrdinaryKeys_areRejectedAcrossTypingNavigationPunctuationAndKeypad() {
        let ordinaryKeyCodes = [
            kVK_ANSI_A,
            kVK_ANSI_1,
            kVK_LeftArrow,
            kVK_RightArrow,
            kVK_Space,
            kVK_Return,
            kVK_Tab,
            kVK_ANSI_Minus,
            kVK_ANSI_Equal,
            kVK_ANSI_Slash,
            kVK_ANSI_Keypad0,
            kVK_ANSI_KeypadPlus
        ].map(UInt32.init)

        HotKeyTestSupport.expect(
            ordinaryKeyCodes.allSatisfy {
                !ScreenshotHotKey(keyCode: $0, modifiers: 0).isValid
            },
            "TestHotKeyValueContract.test_unmodifiedOrdinaryKeys_areRejectedAcrossTypingNavigationPunctuationAndKeypad"
        )
    }

    static func test_ordinaryKeyWithEachSupportedModifier_remainsValid() {
        let modifiers = [controlKey, optionKey, shiftKey, cmdKey].map(UInt32.init)

        HotKeyTestSupport.expect(
            modifiers.allSatisfy {
                ScreenshotHotKey(
                    keyCode: UInt32(kVK_ANSI_A),
                    modifiers: $0
                ).isValid
            },
            "TestHotKeyValueContract.test_ordinaryKeyWithEachSupportedModifier_remainsValid"
        )
    }

    static func test_extraModifierBits_areRemovedAndDisplayOrderIsStable() {
        let raw = UInt32(cmdKey | shiftKey | optionKey | controlKey | alphaLock)
        let value = ScreenshotHotKey(keyCode: UInt32(kVK_ANSI_S), modifiers: raw)
        HotKeyTestSupport.expect(
            value.modifiers == UInt32(controlKey | optionKey | shiftKey | cmdKey)
                && value.displayString == "⌃⌥⇧⌘S",
            "TestHotKeyValueContract.test_extraModifierBits_areRemovedAndDisplayOrderIsStable"
        )
    }

    static func test_decodingJSON_normalizesCarbonModifierBits() {
        let rawModifiers = UInt32(controlKey | optionKey | alphaLock)
        let data = try! JSONSerialization.data(withJSONObject: [
            "keyCode": UInt32(kVK_ANSI_K),
            "modifiers": rawModifiers
        ])
        let decoded = try! JSONDecoder().decode(ScreenshotHotKey.self, from: data)

        HotKeyTestSupport.expect(
            decoded == ScreenshotHotKey(
                keyCode: UInt32(kVK_ANSI_K),
                modifiers: UInt32(controlKey | optionKey)
            )
                && decoded.modifiers == UInt32(controlKey | optionKey),
            "TestHotKeyValueContract.test_decodingJSON_normalizesCarbonModifierBits"
        )
    }

    static func test_missingKeyOrModifierAndReservedKeys_areInvalid() {
        let ordinaryWithoutModifier = ScreenshotHotKey(keyCode: UInt32(kVK_ANSI_A), modifiers: 0)
        let escape = ScreenshotHotKey(keyCode: UInt32(kVK_Escape), modifiers: UInt32(cmdKey))
        let backspace = ScreenshotHotKey(keyCode: UInt32(kVK_Delete), modifiers: UInt32(optionKey))
        let forwardDelete = ScreenshotHotKey(keyCode: UInt32(kVK_ForwardDelete), modifiers: UInt32(controlKey))

        HotKeyTestSupport.expect(
            !ordinaryWithoutModifier.isValid
                && !escape.isValid
                && !backspace.isValid
                && !forwardDelete.isValid,
            "TestHotKeyValueContract.test_missingKeyOrModifierAndReservedKeys_areInvalid"
        )
    }

    static func test_physicalModifierKeyCodes_areInvalidEvenWhenCombinedWithModifiers() {
        let modifierKeyCodes = [
            kVK_Command,
            kVK_Shift,
            kVK_Option,
            kVK_Control,
            kVK_RightCommand,
            kVK_RightShift,
            kVK_RightOption,
            kVK_RightControl,
            kVK_CapsLock,
            kVK_Function
        ].map(UInt32.init)

        let allRejected = modifierKeyCodes.allSatisfy {
            !ScreenshotHotKey(keyCode: $0, modifiers: UInt32(controlKey | optionKey)).isValid
        }
        HotKeyTestSupport.expect(
            allRejected,
            "TestHotKeyValueContract.test_physicalModifierKeyCodes_areInvalidEvenWhenCombinedWithModifiers"
        )
    }

    static func test_specialPhysicalKeys_haveStableReadableLabels() {
        let values = [
            ScreenshotHotKey(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(cmdKey)).displayString,
            ScreenshotHotKey(keyCode: UInt32(kVK_F5), modifiers: UInt32(shiftKey)).displayString,
            ScreenshotHotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey)).displayString,
            ScreenshotHotKey(keyCode: UInt32(kVK_Return), modifiers: UInt32(optionKey)).displayString,
            ScreenshotHotKey(keyCode: UInt32(kVK_Tab), modifiers: UInt32(cmdKey)).displayString
        ]
        HotKeyTestSupport.expect(
            values == ["⌘←", "⇧F5", "⌃Space", "⌥↩", "⌘⇥"],
            "TestHotKeyValueContract.test_specialPhysicalKeys_haveStableReadableLabels"
        )
    }

    static func test_layoutDependentPunctuation_usesKeyboardLayoutTranslationBeforeFallback() {
        let translatedLabels: [UInt32: String] = [
            UInt32(kVK_ANSI_Minus): "§",
            UInt32(kVK_ANSI_Equal): "¿",
            UInt32(kVK_ANSI_LeftBracket): "«",
            UInt32(kVK_ANSI_Semicolon): "…"
        ]
        let values = [
            ScreenshotHotKey(keyCode: UInt32(kVK_ANSI_Minus), modifiers: UInt32(cmdKey))
                .displayString(keyLabelTranslator: { translatedLabels[$0] }),
            ScreenshotHotKey(keyCode: UInt32(kVK_ANSI_Equal), modifiers: UInt32(optionKey))
                .displayString(keyLabelTranslator: { translatedLabels[$0] }),
            ScreenshotHotKey(keyCode: UInt32(kVK_ANSI_LeftBracket), modifiers: UInt32(controlKey))
                .displayString(keyLabelTranslator: { translatedLabels[$0] }),
            ScreenshotHotKey(keyCode: UInt32(kVK_ANSI_Semicolon), modifiers: UInt32(shiftKey))
                .displayString(keyLabelTranslator: { translatedLabels[$0] })
        ]

        HotKeyTestSupport.expect(
            values == ["⌘§", "⌥¿", "⌃«", "⇧…"],
            "TestHotKeyValueContract.test_layoutDependentPunctuation_usesKeyboardLayoutTranslationBeforeFallback"
        )
    }

    static func test_punctuationWithoutKeyboardLayoutTranslation_usesReadableFallback() {
        let unavailableTranslator: (UInt32) -> String? = { _ in nil }
        let values = [
            ScreenshotHotKey(keyCode: UInt32(kVK_ANSI_Minus), modifiers: UInt32(cmdKey))
                .displayString(keyLabelTranslator: unavailableTranslator),
            ScreenshotHotKey(keyCode: UInt32(kVK_ANSI_Equal), modifiers: UInt32(optionKey))
                .displayString(keyLabelTranslator: unavailableTranslator),
            ScreenshotHotKey(keyCode: UInt32(kVK_ANSI_LeftBracket), modifiers: UInt32(controlKey))
                .displayString(keyLabelTranslator: unavailableTranslator),
            ScreenshotHotKey(keyCode: UInt32(kVK_ANSI_Semicolon), modifiers: UInt32(shiftKey))
                .displayString(keyLabelTranslator: unavailableTranslator)
        ]

        HotKeyTestSupport.expect(
            values == ["⌘-", "⌥=", "⌃[", "⇧;"],
            "TestHotKeyValueContract.test_punctuationWithoutKeyboardLayoutTranslation_usesReadableFallback"
        )
    }

    static func test_emptyKeyboardLayoutTranslation_usesReadablePunctuationFallback() {
        let emptyTranslator: (UInt32) -> String? = { _ in "" }
        let values = [
            ScreenshotHotKey(keyCode: UInt32(kVK_ANSI_Minus), modifiers: UInt32(cmdKey))
                .displayString(keyLabelTranslator: emptyTranslator),
            ScreenshotHotKey(keyCode: UInt32(kVK_ANSI_Equal), modifiers: UInt32(optionKey))
                .displayString(keyLabelTranslator: emptyTranslator),
            ScreenshotHotKey(keyCode: UInt32(kVK_ANSI_LeftBracket), modifiers: UInt32(controlKey))
                .displayString(keyLabelTranslator: emptyTranslator),
            ScreenshotHotKey(keyCode: UInt32(kVK_ANSI_Semicolon), modifiers: UInt32(shiftKey))
                .displayString(keyLabelTranslator: emptyTranslator)
        ]

        HotKeyTestSupport.expect(
            values == ["⌘-", "⌥=", "⌃[", "⇧;"],
            "TestHotKeyValueContract.test_emptyKeyboardLayoutTranslation_usesReadablePunctuationFallback"
        )
    }

    static func test_keypadKeys_haveStableReadableLabelsIndependentOfKeyboardLayout() {
        let conflictingTranslator: (UInt32) -> String? = { _ in "layout-dependent" }
        let values = [
            ScreenshotHotKey(keyCode: UInt32(kVK_ANSI_Keypad0), modifiers: UInt32(cmdKey))
                .displayString(keyLabelTranslator: conflictingTranslator),
            ScreenshotHotKey(keyCode: UInt32(kVK_ANSI_KeypadDecimal), modifiers: UInt32(controlKey))
                .displayString(keyLabelTranslator: conflictingTranslator),
            ScreenshotHotKey(keyCode: UInt32(kVK_ANSI_KeypadMultiply), modifiers: UInt32(shiftKey))
                .displayString(keyLabelTranslator: conflictingTranslator),
            ScreenshotHotKey(keyCode: UInt32(kVK_ANSI_KeypadPlus), modifiers: UInt32(optionKey))
                .displayString(keyLabelTranslator: conflictingTranslator)
        ]

        HotKeyTestSupport.expect(
            values == ["⌘0", "⌃.", "⇧×", "⌥+"],
            "TestHotKeyValueContract.test_keypadKeys_haveStableReadableLabelsIndependentOfKeyboardLayout"
        )
    }

    static func test_unknownKeyCodeDisplay_includesTheActualNumericCode() {
        let firstCode: UInt32 = 222
        let secondCode: UInt32 = 223
        let first = ScreenshotHotKey(keyCode: firstCode, modifiers: UInt32(controlKey)).displayString
        let second = ScreenshotHotKey(keyCode: secondCode, modifiers: UInt32(controlKey)).displayString

        HotKeyTestSupport.expect(
            first.contains(String(firstCode))
                && second.contains(String(secondCode))
                && first != second,
            "TestHotKeyValueContract.test_unknownKeyCodeDisplay_includesTheActualNumericCode"
        )
    }
}

final class TestHotKeyRecordingDecision {
    static func test_escapeWithOrWithoutModifiers_cancels() {
        let plain = ScreenshotHotKey.recordingDecision(
            keyCode: UInt32(kVK_Escape),
            modifiers: 0
        )
        let modified = ScreenshotHotKey.recordingDecision(
            keyCode: UInt32(kVK_Escape),
            modifiers: UInt32(cmdKey | shiftKey)
        )
        HotKeyTestSupport.expect(
            plain == .cancel && modified == .cancel,
            "TestHotKeyRecordingDecision.test_escapeWithOrWithoutModifiers_cancels"
        )
    }

    static func test_deleteKeysWithOrWithoutModifiers_requestDefault() {
        let backspace = ScreenshotHotKey.recordingDecision(
            keyCode: UInt32(kVK_Delete),
            modifiers: 0
        )
        let forwardDelete = ScreenshotHotKey.recordingDecision(
            keyCode: UInt32(kVK_ForwardDelete),
            modifiers: UInt32(controlKey | optionKey)
        )
        HotKeyTestSupport.expect(
            backspace == .restoreDefault && forwardDelete == .restoreDefault,
            "TestHotKeyRecordingDecision.test_deleteKeysWithOrWithoutModifiers_requestDefault"
        )
    }

    static func test_modifierOnlyWaitsAndPlainKeyRejectsWithoutEndingRecording() {
        let modifierOnly = ScreenshotHotKey.recordingDecision(
            keyCode: nil,
            modifiers: UInt32(cmdKey)
        )
        let plainKey = ScreenshotHotKey.recordingDecision(
            keyCode: UInt32(kVK_ANSI_1),
            modifiers: 0
        )
        HotKeyTestSupport.expect(
            modifierOnly == .waitForKey && plainKey == .invalid,
            "TestHotKeyRecordingDecision.test_modifierOnlyWaitsAndPlainKeyRejectsWithoutEndingRecording"
        )
    }

    static func test_validCombination_commitsNormalizedValue() {
        let decision = ScreenshotHotKey.recordingDecision(
            keyCode: UInt32(kVK_ANSI_K),
            modifiers: UInt32(optionKey | cmdKey | alphaLock)
        )
        HotKeyTestSupport.expect(
            decision == .commit(
                ScreenshotHotKey(
                    keyCode: UInt32(kVK_ANSI_K),
                    modifiers: UInt32(optionKey | cmdKey)
                )
            ),
            "TestHotKeyRecordingDecision.test_validCombination_commitsNormalizedValue"
        )
    }

    static func test_unmodifiedGraveAndFunctionKeys_commitWithoutAddingModifiers() {
        let keyCodes = [kVK_ANSI_Grave, kVK_F1, kVK_F12, kVK_F20].map(UInt32.init)
        let decisions = keyCodes.map {
            ScreenshotHotKey.recordingDecision(keyCode: $0, modifiers: 0)
        }
        let expected = keyCodes.map {
            ScreenshotHotKey.RecordingDecision.commit(
                ScreenshotHotKey(keyCode: $0, modifiers: 0)
            )
        }

        HotKeyTestSupport.expect(
            decisions == expected,
            "TestHotKeyRecordingDecision.test_unmodifiedGraveAndFunctionKeys_commitWithoutAddingModifiers"
        )
    }
}

final class TestHotKeyAppConfigMigration {
    static let translator = AzureTranslatorConfig(
        endpoint: "https://fictional-translator.invalid",
        apiKey: "fictional-translator-key",
        region: "fictional-region"
    )
    static let gpt = AzureOpenAIConfig(
        endpoint: "https://fictional-gpt.invalid/openai/v1",
        apiKey: "fictional-gpt-key",
        deploymentName: "fictional-deployment",
        supportsVision: true
    )

    static func test_missingHotKeyField_loadsDefaultWithoutBackupAndPreservesAzureValues() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("glint-hotkey-migration-\(UUID().uuidString)", isDirectory: true)
        let configURL = directory.appendingPathComponent("config.json")
        let backupURL = directory.appendingPathComponent("config.pre-azure-backup.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let legacy = AppConfig(translator: translator, azureOpenAI: gpt)
        let fullData = try! JSONEncoder().encode(legacy)
        var object = try! JSONSerialization.jsonObject(with: fullData) as! [String: Any]
        object.removeValue(forKey: "screenshotHotKey")
        let legacyData = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try! legacyData.write(to: configURL)

        let loaded = AppConfig.loadOrCreate(at: configURL)

        HotKeyTestSupport.expect(
            loaded.translator == translator
                && loaded.azureOpenAI == gpt
                && loaded.screenshotHotKey == .default
                && !FileManager.default.fileExists(atPath: backupURL.path),
            "TestHotKeyAppConfigMigration.test_missingHotKeyField_loadsDefaultWithoutBackupAndPreservesAzureValues"
        )
    }

    static func test_newConfig_fileRoundTripUsesKeychainAndSanitizesJSON() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("glint-hotkey-roundtrip-\(UUID().uuidString)", isDirectory: true)
        let configURL = directory.appendingPathComponent("config.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        var keychainValues: [AzureAPIKeySlot: String] = [:]
        AppConfig.installRuntimeKeychain(
            AzureKeychainClient(
                read: { keychainValues[$0] },
                write: { value, slot in
                    keychainValues[slot] = value
                    return true
                }
            )
        )
        defer { AppConfig.installRuntimeKeychain(.unavailable) }

        let hotKey = ScreenshotHotKey(
            keyCode: UInt32(kVK_ANSI_7),
            modifiers: UInt32(controlKey | shiftKey)
        )
        let original = AppConfig(
            translator: translator,
            azureOpenAI: gpt,
            screenshotHotKey: hotKey
        )
        let encoded = try? JSONEncoder().encode(original)
        let decoded = encoded.flatMap { try? JSONDecoder().decode(AppConfig.self, from: $0) }
        let saved = original.save(to: configURL)
        let loaded = AppConfig.load(from: configURL)
        let persistedText = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""

        HotKeyTestSupport.expect(
            decoded?.translator == translator
                && decoded?.azureOpenAI == gpt
                && decoded?.screenshotHotKey == hotKey
                && saved
                && loaded?.translator == translator
                && loaded?.azureOpenAI == gpt
                && loaded?.screenshotHotKey == hotKey
                && !persistedText.contains("apiKey")
                && keychainValues[.translator] == translator.apiKey
                && keychainValues[.openAI] == gpt.apiKey,
            "TestHotKeyAppConfigMigration.test_newConfig_fileRoundTripUsesKeychainAndSanitizesJSON"
        )
    }
}

final class TestHotKeyTransaction {
    private static let oldKey = ScreenshotHotKey.default
    private static let newKey = ScreenshotHotKey(
        keyCode: UInt32(kVK_ANSI_S),
        modifiers: UInt32(controlKey | shiftKey)
    )

    private static func makeManager(
        registrar: TestHotKeyRegistrar,
        state: TestHotKeyRuntimeState,
        duringSave: (() -> Void)? = nil
    ) -> ScreenshotHotKeyManager {
        ScreenshotHotKeyManager(
            savedHotKey: oldKey,
            registrar: registrar,
            persist: { key in
                registrar.events.append("save:\(key.keyCode)")
                duringSave?()
                let succeeds = state.saveOutcomes.isEmpty ? true : state.saveOutcomes.removeFirst()
                if succeeds { state.persisted = key }
                return succeeds
            },
            onScreenshot: { state.screenshots += 1 }
        )
    }

    static func test_success_candidateIsInactiveUntilSaveAndOldKeyUnregisterThenOnlyNewKeyFires() {
        let registrar = TestHotKeyRegistrar(outcomes: [.success(), .success()])
        let state = TestHotKeyRuntimeState(persisted: oldKey, saveOutcomes: [true])
        var candidateWasInactiveDuringSave = false

        let manager = makeManager(
            registrar: registrar,
            state: state,
            duringSave: {
                let candidate = registrar.registrations.last!
                candidate.fire()
                candidateWasInactiveDuringSave = !candidate.isActive && state.screenshots == 0
            }
        )
        let result = manager.apply(newKey)
        let oldRegistration = registrar.registrations[0]
        let candidate = registrar.registrations[1]
        oldRegistration.fire()
        candidate.fire()

        HotKeyTestSupport.expect(
            result == .applied
                && candidateWasInactiveDuringSave
                && state.persisted == newKey
                && manager.effectiveHotKey == newKey
                && !oldRegistration.isActive
                && candidate.isActive
                && state.screenshots == 1
                && registrar.events == [
                    "register:\(oldKey.keyCode):true",
                    "register:\(newKey.keyCode):false",
                    "save:\(newKey.keyCode)",
                    "invalidate:\(oldKey.keyCode)"
                ],
            "TestHotKeyTransaction.test_success_candidateIsInactiveUntilSaveAndOldKeyUnregisterThenOnlyNewKeyFires"
        )
    }

    static func test_sameValue_isSuccessfulNoOpWithoutRegistrationOrSave() {
        let registrar = TestHotKeyRegistrar(outcomes: [.success()])
        let state = TestHotKeyRuntimeState(persisted: oldKey, saveOutcomes: [])
        let manager = makeManager(
            registrar: registrar,
            state: state
        )
        let eventCount = registrar.events.count
        let result = manager.apply(oldKey)

        HotKeyTestSupport.expect(
            result == .unchanged
                && registrar.registerCallCount == 1
                && registrar.events.count == eventCount
                && state.persisted == oldKey,
            "TestHotKeyTransaction.test_sameValue_isSuccessfulNoOpWithoutRegistrationOrSave"
        )
    }

    static func test_unmodifiedFunctionKey_preservesZeroModifiersThroughRegistrationAndActivation() {
        let registrar = TestHotKeyRegistrar(outcomes: [.success(), .success()])
        let state = TestHotKeyRuntimeState(persisted: oldKey, saveOutcomes: [true])
        let manager = makeManager(registrar: registrar, state: state)
        let candidate = ScreenshotHotKey(
            keyCode: UInt32(kVK_F12),
            modifiers: 0
        )

        let result = manager.apply(candidate)

        HotKeyTestSupport.expect(
            result == .applied
                && manager.effectiveHotKey == candidate
                && state.persisted == candidate
                && registrar.registrations.count == 2
                && registrar.registrations[1].hotKey.modifiers == 0
                && registrar.registrations[1].isActive,
            "TestHotKeyTransaction.test_unmodifiedFunctionKey_preservesZeroModifiersThroughRegistrationAndActivation"
        )
    }

    static func test_installOrRegisterFailure_keepsOldKeyAndNeverSaves() {
        for error in [
            HotKeyRegistrationError.eventHandlerInstallationFailed(-9871),
            HotKeyRegistrationError.registrationFailed(-9872)
        ] {
            let registrar = TestHotKeyRegistrar(outcomes: [.success(), .failure(error)])
            let state = TestHotKeyRuntimeState(persisted: oldKey, saveOutcomes: [])
            let manager = makeManager(
                registrar: registrar,
                state: state
            )
            let result = manager.apply(newKey)
            registrar.registrations[0].fire()

            HotKeyTestSupport.expect(
                result == .registrationFailed
                    && state.persisted == oldKey
                    && manager.effectiveHotKey == oldKey
                    && state.screenshots == 1
                    && !registrar.events.contains { $0.hasPrefix("save:") },
                "TestHotKeyTransaction.test_installOrRegisterFailure_keepsOldKeyAndNeverSaves.\(error)"
            )
        }
    }

    static func test_saveFailure_cleansCandidateAndKeepsOldKey() {
        let registrar = TestHotKeyRegistrar(outcomes: [.success(), .success()])
        let state = TestHotKeyRuntimeState(persisted: oldKey, saveOutcomes: [false])
        let manager = makeManager(
            registrar: registrar,
            state: state
        )
        let result = manager.apply(newKey)
        let oldRegistration = registrar.registrations[0]
        let candidate = registrar.registrations[1]
        oldRegistration.fire()
        candidate.fire()

        HotKeyTestSupport.expect(
            result == .persistenceFailed(candidateCleanupFailed: false)
                && state.persisted == oldKey
                && manager.effectiveHotKey == oldKey
                && !manager.isModificationLocked
                && oldRegistration.isActive
                && !candidate.isActive
                && candidate.invalidateCallCount == 1
                && state.screenshots == 1,
            "TestHotKeyTransaction.test_saveFailure_cleansCandidateAndKeepsOldKey"
        )
    }

    static func test_saveFailureAndCandidateCleanupFailure_locksWithInactiveCandidate() {
        let registrar = TestHotKeyRegistrar(outcomes: [
            .success(),
            .success(invalidateStatuses: [-9873])
        ])
        let state = TestHotKeyRuntimeState(persisted: oldKey, saveOutcomes: [false])
        let manager = makeManager(
            registrar: registrar,
            state: state
        )
        let result = manager.apply(newKey)
        let oldRegistration = registrar.registrations[0]
        let candidate = registrar.registrations[1]
        oldRegistration.fire()
        candidate.fire()

        HotKeyTestSupport.expect(
            result == .persistenceFailed(candidateCleanupFailed: true)
                && state.persisted == oldKey
                && manager.effectiveHotKey == oldKey
                && manager.pendingCandidateHotKey == newKey
                && manager.isModificationLocked
                && oldRegistration.isActive
                && !candidate.isActive
                && state.screenshots == 1,
            "TestHotKeyTransaction.test_saveFailureAndCandidateCleanupFailure_locksWithInactiveCandidate"
        )
    }

    static func test_oldInvalidationFailure_attemptsRollbackAndCandidateCleanupIndependently() {
        let registrar = TestHotKeyRegistrar(outcomes: [
            .success(invalidateStatuses: [-9874]),
            .success()
        ])
        let state = TestHotKeyRuntimeState(persisted: oldKey, saveOutcomes: [true, true])
        let manager = makeManager(
            registrar: registrar,
            state: state
        )
        let result = manager.apply(newKey)
        let oldRegistration = registrar.registrations[0]
        let candidate = registrar.registrations[1]
        oldRegistration.fire()
        candidate.fire()

        HotKeyTestSupport.expect(
            result == .oldRegistrationInvalidationFailed(
                configRollbackFailed: false,
                candidateCleanupFailed: false
            )
                && state.persisted == oldKey
                && manager.effectiveHotKey == oldKey
                && !manager.isModificationLocked
                && oldRegistration.isActive
                && !candidate.isActive
                && state.screenshots == 1
                && registrar.events.suffix(3) == [
                    "invalidate:\(oldKey.keyCode)",
                    "save:\(oldKey.keyCode)",
                    "invalidate:\(newKey.keyCode)"
                ],
            "TestHotKeyTransaction.test_oldInvalidationFailure_attemptsRollbackAndCandidateCleanupIndependently"
        )
    }

    static func test_rollbackFailureButCandidateCleanupSuccess_locksWithDiskCandidateAndOnlyOldKeyActive() {
        let registrar = TestHotKeyRegistrar(outcomes: [
            .success(invalidateStatuses: [-9875]),
            .success()
        ])
        let state = TestHotKeyRuntimeState(persisted: oldKey, saveOutcomes: [true, false])
        let manager = makeManager(
            registrar: registrar,
            state: state
        )
        let result = manager.apply(newKey)
        let oldRegistration = registrar.registrations[0]
        let candidate = registrar.registrations[1]
        oldRegistration.fire()
        candidate.fire()

        HotKeyTestSupport.expect(
            result == .oldRegistrationInvalidationFailed(
                configRollbackFailed: true,
                candidateCleanupFailed: false
            )
                && state.persisted == newKey
                && manager.effectiveHotKey == oldKey
                && manager.pendingCandidateHotKey == nil
                && manager.isModificationLocked
                && oldRegistration.isActive
                && !candidate.isActive
                && state.screenshots == 1,
            "TestHotKeyTransaction.test_rollbackFailureButCandidateCleanupSuccess_locksWithDiskCandidateAndOnlyOldKeyActive"
        )
    }

    static func test_rollbackAndCandidateCleanupFailure_locksAndRetainsInactiveCandidate() {
        let registrar = TestHotKeyRegistrar(outcomes: [
            .success(invalidateStatuses: [-9876]),
            .success(invalidateStatuses: [-9877])
        ])
        let state = TestHotKeyRuntimeState(persisted: oldKey, saveOutcomes: [true, false])
        let manager = makeManager(
            registrar: registrar,
            state: state
        )
        let result = manager.apply(newKey)
        let oldRegistration = registrar.registrations[0]
        let candidate = registrar.registrations[1]
        oldRegistration.fire()
        candidate.fire()

        HotKeyTestSupport.expect(
            result == .oldRegistrationInvalidationFailed(
                configRollbackFailed: true,
                candidateCleanupFailed: true
            )
                && state.persisted == newKey
                && manager.effectiveHotKey == oldKey
                && manager.pendingCandidateHotKey == newKey
                && manager.isModificationLocked
                && oldRegistration.isActive
                && !candidate.isActive
                && state.screenshots == 1,
            "TestHotKeyTransaction.test_rollbackAndCandidateCleanupFailure_locksAndRetainsInactiveCandidate"
        )
    }

    static func test_rollbackSuccessButCandidateCleanupFailure_locksWithDiskOldAndInactiveCandidate() {
        let registrar = TestHotKeyRegistrar(outcomes: [
            .success(invalidateStatuses: [-9878]),
            .success(invalidateStatuses: [-9879])
        ])
        let state = TestHotKeyRuntimeState(persisted: oldKey, saveOutcomes: [true, true])
        let manager = makeManager(
            registrar: registrar,
            state: state
        )
        let result = manager.apply(newKey)
        let oldRegistration = registrar.registrations[0]
        let candidate = registrar.registrations[1]
        oldRegistration.fire()
        candidate.fire()

        HotKeyTestSupport.expect(
            result == .oldRegistrationInvalidationFailed(
                configRollbackFailed: false,
                candidateCleanupFailed: true
            )
                && state.persisted == oldKey
                && manager.effectiveHotKey == oldKey
                && manager.pendingCandidateHotKey == newKey
                && manager.isModificationLocked
                && oldRegistration.isActive
                && !candidate.isActive
                && state.screenshots == 1,
            "TestHotKeyTransaction.test_rollbackSuccessButCandidateCleanupFailure_locksWithDiskOldAndInactiveCandidate"
        )
    }
}

final class TestHotKeyRecordingBridge {
    static func test_currentHotKeyDuringRecording_returnsSameValueWithoutScreenshotThenRestoresNormalAction() {
        let registrar = TestHotKeyRegistrar(outcomes: [.success()])
        var persisted = ScreenshotHotKey.default
        var saveOutcomes: [Bool] = []
        var screenshots = 0
        let manager = ScreenshotHotKeyManager(
            savedHotKey: .default,
            registrar: registrar,
            persist: { key in
                let succeeds = saveOutcomes.isEmpty ? true : saveOutcomes.removeFirst()
                if succeeds { persisted = key }
                return succeeds
            },
            onScreenshot: { screenshots += 1 }
        )
        var recorded: ScreenshotHotKey?

        manager.beginRecording { recorded = $0 }
        registrar.registrations[0].fire()
        let routedWithoutScreenshot = recorded == .default && screenshots == 0
        manager.endRecording()
        registrar.registrations[0].fire()

        HotKeyTestSupport.expect(
            routedWithoutScreenshot
                && screenshots == 1
                && manager.effectiveHotKey == .default
                && persisted == .default,
            "TestHotKeyRecordingBridge.test_currentHotKeyDuringRecording_returnsSameValueWithoutScreenshotThenRestoresNormalAction"
        )
    }
}

final class TestHotKeyStartupRegistration {
    private static let savedCustomKey = ScreenshotHotKey(
        keyCode: UInt32(kVK_ANSI_S),
        modifiers: UInt32(controlKey | shiftKey)
    )
    private static let replacementKey = ScreenshotHotKey(
        keyCode: UInt32(kVK_ANSI_K),
        modifiers: UInt32(optionKey | cmdKey)
    )

    static func test_savedCustomRegistrationFailure_fallsBackToDefaultAndPersistsRepair() {
        let customError = HotKeyRegistrationError.registrationFailed(-9860)
        let registrar = TestHotKeyRegistrar(outcomes: [
            .failure(customError),
            .success()
        ])
        var persisted = savedCustomKey
        var screenshots = 0
        let manager = ScreenshotHotKeyManager(
            savedHotKey: savedCustomKey,
            registrar: registrar,
            persist: { persisted = $0; return true },
            onScreenshot: { screenshots += 1 }
        )
        registrar.registrations.first?.fire()

        HotKeyTestSupport.expect(
            manager.effectiveHotKey == .default
                && manager.hasActiveRegistration
                && manager.didFallbackToDefault
                && manager.startupRegistrationError == customError
                && persisted == .default
                && screenshots == 1
                && registrar.events.prefix(2) == [
                    "register:\(savedCustomKey.keyCode):true",
                    "register:\(ScreenshotHotKey.default.keyCode):true"
                ],
            "TestHotKeyStartupRegistration.test_savedCustomRegistrationFailure_fallsBackToDefaultAndPersistsRepair"
        )
    }

    static func test_savedAndDefaultRegistrationFailure_reportsErrorButStillAllowsReplacement() {
        let customError = HotKeyRegistrationError.registrationFailed(-9861)
        let defaultError = HotKeyRegistrationError.registrationFailed(-9862)
        let registrar = TestHotKeyRegistrar(outcomes: [
            .failure(customError),
            .failure(defaultError),
            .success()
        ])
        var persisted = savedCustomKey
        var screenshots = 0
        let manager = ScreenshotHotKeyManager(
            savedHotKey: savedCustomKey,
            registrar: registrar,
            persist: { persisted = $0; return true },
            onScreenshot: { screenshots += 1 }
        )

        let startupWasRecoverable = !manager.hasActiveRegistration
            && manager.startupRegistrationError == defaultError
            && registrar.registerCallCount == 2
        let applyResult = manager.apply(replacementKey)
        registrar.registrations.first?.fire()

        HotKeyTestSupport.expect(
            startupWasRecoverable
                && applyResult == .applied
                && manager.effectiveHotKey == replacementKey
                && manager.hasActiveRegistration
                && manager.startupRegistrationError == nil
                && persisted == replacementKey
                && screenshots == 1,
            "TestHotKeyStartupRegistration.test_savedAndDefaultRegistrationFailure_reportsErrorButStillAllowsReplacement"
        )
    }
}

@main
enum HotKeyTests {
    static func main() {
        TestHotKeyValueContract.test_defaultValue_isControlOptionE()
        TestHotKeyValueContract.test_unmodifiedGraveAndFunctionKeys_areValidAndReadable()
        TestHotKeyValueContract
            .test_unmodifiedOrdinaryKeys_areRejectedAcrossTypingNavigationPunctuationAndKeypad()
        TestHotKeyValueContract.test_ordinaryKeyWithEachSupportedModifier_remainsValid()
        TestHotKeyValueContract.test_extraModifierBits_areRemovedAndDisplayOrderIsStable()
        TestHotKeyValueContract.test_decodingJSON_normalizesCarbonModifierBits()
        TestHotKeyValueContract.test_missingKeyOrModifierAndReservedKeys_areInvalid()
        TestHotKeyValueContract.test_physicalModifierKeyCodes_areInvalidEvenWhenCombinedWithModifiers()
        TestHotKeyValueContract.test_specialPhysicalKeys_haveStableReadableLabels()
        TestHotKeyValueContract
            .test_layoutDependentPunctuation_usesKeyboardLayoutTranslationBeforeFallback()
        TestHotKeyValueContract
            .test_punctuationWithoutKeyboardLayoutTranslation_usesReadableFallback()
        TestHotKeyValueContract
            .test_emptyKeyboardLayoutTranslation_usesReadablePunctuationFallback()
        TestHotKeyValueContract
            .test_keypadKeys_haveStableReadableLabelsIndependentOfKeyboardLayout()
        TestHotKeyValueContract.test_unknownKeyCodeDisplay_includesTheActualNumericCode()

        TestHotKeyRecordingDecision.test_escapeWithOrWithoutModifiers_cancels()
        TestHotKeyRecordingDecision.test_deleteKeysWithOrWithoutModifiers_requestDefault()
        TestHotKeyRecordingDecision.test_modifierOnlyWaitsAndPlainKeyRejectsWithoutEndingRecording()
        TestHotKeyRecordingDecision.test_validCombination_commitsNormalizedValue()
        TestHotKeyRecordingDecision
            .test_unmodifiedGraveAndFunctionKeys_commitWithoutAddingModifiers()

        TestHotKeyAppConfigMigration.test_missingHotKeyField_loadsDefaultWithoutBackupAndPreservesAzureValues()
        TestHotKeyAppConfigMigration.test_newConfig_fileRoundTripUsesKeychainAndSanitizesJSON()

        TestHotKeyTransaction.test_success_candidateIsInactiveUntilSaveAndOldKeyUnregisterThenOnlyNewKeyFires()
        TestHotKeyTransaction.test_sameValue_isSuccessfulNoOpWithoutRegistrationOrSave()
        TestHotKeyTransaction
            .test_unmodifiedFunctionKey_preservesZeroModifiersThroughRegistrationAndActivation()
        TestHotKeyTransaction.test_installOrRegisterFailure_keepsOldKeyAndNeverSaves()
        TestHotKeyTransaction.test_saveFailure_cleansCandidateAndKeepsOldKey()
        TestHotKeyTransaction.test_saveFailureAndCandidateCleanupFailure_locksWithInactiveCandidate()
        TestHotKeyTransaction.test_oldInvalidationFailure_attemptsRollbackAndCandidateCleanupIndependently()
        TestHotKeyTransaction.test_rollbackFailureButCandidateCleanupSuccess_locksWithDiskCandidateAndOnlyOldKeyActive()
        TestHotKeyTransaction.test_rollbackAndCandidateCleanupFailure_locksAndRetainsInactiveCandidate()
        TestHotKeyTransaction.test_rollbackSuccessButCandidateCleanupFailure_locksWithDiskOldAndInactiveCandidate()

        TestHotKeyRecordingBridge.test_currentHotKeyDuringRecording_returnsSameValueWithoutScreenshotThenRestoresNormalAction()

        TestHotKeyStartupRegistration.test_savedCustomRegistrationFailure_fallsBackToDefaultAndPersistsRepair()
        TestHotKeyStartupRegistration.test_savedAndDefaultRegistrationFailure_reportsErrorButStillAllowsReplacement()

        print(HotKeyTestSupport.failures == 0 ? "ALL PASS" : "\(HotKeyTestSupport.failures) FAILURES")
        exit(HotKeyTestSupport.failures == 0 ? 0 : 1)
    }
}
