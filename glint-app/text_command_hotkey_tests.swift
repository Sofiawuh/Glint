import Carbon
import Foundation

// Text-command hot-key value, migration, conflict, recording and switch contracts.
// This executable uses fictional Azure values and temporary files only. It must never
// load AppConfig.shared, the real ~/.config/glint/config.json, or register a real hot key.
//
// Intended minimal command once the production contracts exist:
//   swiftc -o /tmp/glint_text_command_hotkey_test \
//     Config.swift ScreenshotHotKey.swift TextCommandHotKey.swift HotKey.swift \
//     text_command_hotkey_tests.swift -framework Carbon -framework Foundation \
//     && /tmp/glint_text_command_hotkey_test

enum TextCommandHotKeyTestSupport {
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

final class TextCommandHotKeyTestKeychainStore {
    private var values: [AzureAPIKeySlot: String] = [:]

    var client: AzureKeychainClient {
        AzureKeychainClient(
            read: { [weak self] in self?.values[$0] },
            write: { [weak self] value, slot in
                self?.values[slot] = value
                return self != nil
            }
        )
    }
}

final class TestTextCommandHotKeyRegistration: TextCommandHotKeyRegistration {
    let hotKey: TextCommandHotKey
    private let action: () -> Void
    private var invalidateStatuses: [OSStatus]

    private(set) var isActive: Bool
    private(set) var invalidateCallCount = 0

    init(
        hotKey: TextCommandHotKey,
        initiallyActive: Bool,
        invalidateStatuses: [OSStatus],
        action: @escaping () -> Void
    ) {
        self.hotKey = hotKey
        self.isActive = initiallyActive
        self.invalidateStatuses = invalidateStatuses
        self.action = action
    }

    func activate() {
        isActive = true
    }

    @discardableResult
    func invalidate() -> OSStatus {
        invalidateCallCount += 1
        let status = invalidateStatuses.isEmpty ? noErr : invalidateStatuses.removeFirst()
        if status == noErr { isActive = false }
        return status
    }

    func fire() {
        if isActive { action() }
    }
}

final class TestTextCommandHotKeyRegistrar: TextCommandHotKeyRegistering {
    enum Outcome {
        case success(invalidateStatuses: [OSStatus] = [noErr])
        case failure(HotKeyRegistrationError)
    }

    var outcomes: [Outcome]
    private(set) var registerCallCount = 0
    private(set) var registrations: [TestTextCommandHotKeyRegistration] = []

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func register(
        _ hotKey: TextCommandHotKey,
        id: UInt32,
        initiallyActive: Bool,
        action: @escaping () -> Void
    ) -> Result<any TextCommandHotKeyRegistration, HotKeyRegistrationError> {
        _ = id
        registerCallCount += 1
        let outcome = outcomes.isEmpty ? .success() : outcomes.removeFirst()
        switch outcome {
        case .failure(let error):
            return .failure(error)
        case .success(let statuses):
            let registration = TestTextCommandHotKeyRegistration(
                hotKey: hotKey,
                initiallyActive: initiallyActive,
                invalidateStatuses: statuses,
                action: action
            )
            registrations.append(registration)
            return .success(registration)
        }
    }
}

final class TestTextCommandHotKeyValueAndMigration {
    private static let translator = AzureTranslatorConfig(
        endpoint: "https://fictional-translator.invalid",
        apiKey: "fictional-translator-key",
        region: "fictional-region"
    )
    private static let gpt = AzureOpenAIConfig(
        endpoint: "https://fictional-gpt.invalid/openai/v1",
        apiKey: "fictional-gpt-key",
        deploymentName: "fictional-deployment",
        supportsVision: true
    )

    static func test_default_value_is_unmodified_grave_and_screenshot_default_is_unchanged() {
        let textCommand = TextCommandHotKey.default
        let screenshot = ScreenshotHotKey.default

        TextCommandHotKeyTestSupport.expect(
            textCommand.keyCode == UInt32(kVK_ANSI_Grave)
                && textCommand.modifiers == 0
                && textCommand.isValid
                && textCommand.screenshotHotKey.displayString(
                    keyLabelTranslator: { _ in nil }
                ) == "`"
                && screenshot.keyCode == UInt32(kVK_ANSI_E)
                && screenshot.modifiers == UInt32(controlKey | optionKey)
                && screenshot.displayString == "⌃⌥E",
            "TestTextCommandHotKeyValueAndMigration.test_default_value_is_unmodified_grave_and_screenshot_default_is_unchanged"
        )
    }

    static func test_legacy_config_without_text_command_field_preserves_azure_and_custom_screenshot_values() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("glint-text-command-migration-\(UUID().uuidString)", isDirectory: true)
        let configURL = directory.appendingPathComponent("config.json")
        let backupURL = directory.appendingPathComponent("config.pre-azure-backup.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let customScreenshot = ScreenshotHotKey(
            keyCode: UInt32(kVK_ANSI_Q),
            modifiers: UInt32(controlKey | shiftKey)
        )
        let current = AppConfig(
            translator: translator,
            azureOpenAI: gpt,
            screenshotHotKey: customScreenshot,
            textCommandHotKey: TextCommandHotKey(
                keyCode: UInt32(kVK_ANSI_R),
                modifiers: UInt32(cmdKey | optionKey)
            )
        )
        let encoded = try! JSONEncoder().encode(current)
        var legacyObject = try! JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        legacyObject.removeValue(forKey: "textCommandHotKey")
        let legacyData = try! JSONSerialization.data(withJSONObject: legacyObject, options: [.sortedKeys])
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try! legacyData.write(to: configURL)

        let loaded = AppConfig.loadOrCreate(at: configURL)

        TextCommandHotKeyTestSupport.expect(
            loaded.translator == translator
                && loaded.azureOpenAI == gpt
                && loaded.screenshotHotKey == customScreenshot
                && loaded.textCommandHotKey == .default
                && !FileManager.default.fileExists(atPath: backupURL.path),
            "TestTextCommandHotKeyValueAndMigration.test_legacy_config_without_text_command_field_preserves_azure_and_custom_screenshot_values"
        )
    }

    static func test_new_config_round_trip_preserves_both_independent_hot_keys() {
        let screenshot = ScreenshotHotKey(
            keyCode: UInt32(kVK_ANSI_Q),
            modifiers: UInt32(controlKey | shiftKey)
        )
        let textCommand = TextCommandHotKey(
            keyCode: UInt32(kVK_ANSI_K),
            modifiers: UInt32(cmdKey | optionKey)
        )
        let original = AppConfig(
            translator: translator,
            azureOpenAI: gpt,
            screenshotHotKey: screenshot,
            textCommandHotKey: textCommand
        )

        let encoded = try? JSONEncoder().encode(original)
        let decoded = encoded.flatMap { try? JSONDecoder().decode(AppConfig.self, from: $0) }

        TextCommandHotKeyTestSupport.expect(
            decoded?.translator == translator
                && decoded?.azureOpenAI == gpt
                && decoded?.screenshotHotKey == screenshot
                && decoded?.textCommandHotKey == textCommand,
            "TestTextCommandHotKeyValueAndMigration.test_new_config_round_trip_preserves_both_independent_hot_keys"
        )
    }

    static func test_saved_old_default_is_migrated_and_persisted_without_changing_azure_or_screenshot() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("glint-text-command-old-default-\(UUID().uuidString)", isDirectory: true)
        let configURL = directory.appendingPathComponent("config.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let keychain = TextCommandHotKeyTestKeychainStore()
        AppConfig.installRuntimeKeychain(keychain.client)
        defer { AppConfig.installRuntimeKeychain(.unavailable) }

        let customScreenshot = ScreenshotHotKey(
            keyCode: UInt32(kVK_ANSI_Q),
            modifiers: UInt32(controlKey | shiftKey)
        )
        let oldDefault = TextCommandHotKey(
            keyCode: UInt32(kVK_ANSI_T),
            modifiers: UInt32(controlKey | optionKey)
        )
        let migratedDefault = TextCommandHotKey(
            keyCode: UInt32(kVK_ANSI_Grave),
            modifiers: 0
        )
        let stored = AppConfig(
            translator: translator,
            azureOpenAI: gpt,
            screenshotHotKey: customScreenshot,
            textCommandHotKey: oldDefault
        )
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = stored.save(to: configURL)

        let loaded = AppConfig.loadOrCreate(at: configURL)
        let persisted = AppConfig.load(from: configURL)

        TextCommandHotKeyTestSupport.expect(
            loaded.textCommandHotKey == migratedDefault
                && persisted?.textCommandHotKey == migratedDefault
                && persisted?.translator == translator
                && persisted?.azureOpenAI == gpt
                && persisted?.screenshotHotKey == customScreenshot,
            "TestTextCommandHotKeyValueAndMigration.test_saved_old_default_is_migrated_and_persisted_without_changing_azure_or_screenshot"
        )
    }

    static func test_saved_custom_text_command_is_not_replaced_by_default_migration() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("glint-text-command-custom-\(UUID().uuidString)", isDirectory: true)
        let configURL = directory.appendingPathComponent("config.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let keychain = TextCommandHotKeyTestKeychainStore()
        AppConfig.installRuntimeKeychain(keychain.client)
        defer { AppConfig.installRuntimeKeychain(.unavailable) }

        let customTextCommand = TextCommandHotKey(
            keyCode: UInt32(kVK_ANSI_K),
            modifiers: UInt32(cmdKey | optionKey)
        )
        let stored = AppConfig(
            translator: translator,
            azureOpenAI: gpt,
            screenshotHotKey: ScreenshotHotKey.default,
            textCommandHotKey: customTextCommand
        )
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = stored.save(to: configURL)

        let loaded = AppConfig.loadOrCreate(at: configURL)
        let persisted = AppConfig.load(from: configURL)

        TextCommandHotKeyTestSupport.expect(
            loaded.textCommandHotKey == customTextCommand
                && persisted?.textCommandHotKey == customTextCommand,
            "TestTextCommandHotKeyValueAndMigration.test_saved_custom_text_command_is_not_replaced_by_default_migration"
        )
    }

    static func test_decoding_json_with_extra_modifier_bits_normalizes_stored_value() {
        let rawModifiers = UInt32(controlKey | optionKey) | UInt32(0x8000_0000)
        let data = try! JSONSerialization.data(withJSONObject: [
            "keyCode": UInt32(kVK_ANSI_T),
            "modifiers": rawModifiers
        ])

        let decoded = try? JSONDecoder().decode(TextCommandHotKey.self, from: data)

        TextCommandHotKeyTestSupport.expect(
            decoded?.keyCode == UInt32(kVK_ANSI_T)
                && decoded?.modifiers == UInt32(controlKey | optionKey)
                && decoded == TextCommandHotKey(
                    keyCode: UInt32(kVK_ANSI_T),
                    modifiers: UInt32(controlKey | optionKey)
                ),
            "TestTextCommandHotKeyValueAndMigration.test_decoding_json_with_extra_modifier_bits_normalizes_stored_value"
        )
    }
}

final class TestTextCommandHotKeyConflictAndTransaction {
    private static let screenshot = ScreenshotHotKey(
        keyCode: UInt32(kVK_ANSI_Q),
        modifiers: UInt32(controlKey | shiftKey)
    )
    private static let oldTextCommand = TextCommandHotKey.default
    private static let newTextCommand = TextCommandHotKey(
        keyCode: UInt32(kVK_ANSI_R),
        modifiers: UInt32(cmdKey | optionKey)
    )

    static func test_candidate_equal_to_screenshot_is_rejected_before_registration_or_save() {
        let registrar = TestTextCommandHotKeyRegistrar(outcomes: [.success()])
        var saved = oldTextCommand
        var persistCalls = 0
        let manager = TextCommandHotKeyManager(
            savedHotKey: oldTextCommand,
            screenshotHotKey: screenshot,
            registrar: registrar,
            persist: {
                persistCalls += 1
                saved = $0
                return true
            },
            onTextCommand: {}
        )
        let registrationsBeforeApply = registrar.registerCallCount
        let conflicting = TextCommandHotKey(
            keyCode: screenshot.keyCode,
            modifiers: screenshot.modifiers
        )

        let result = manager.apply(conflicting)

        TextCommandHotKeyTestSupport.expect(
            result == .conflictsWithScreenshot
                && manager.effectiveHotKey == oldTextCommand
                && saved == oldTextCommand
                && registrar.registerCallCount == registrationsBeforeApply
                && persistCalls == 0
                && registrar.registrations.first?.isActive == true,
            "TestTextCommandHotKeyConflictAndTransaction.test_candidate_equal_to_screenshot_is_rejected_before_registration_or_save"
        )
    }

    static func test_unmodified_function_key_equal_to_screenshot_is_rejected_as_conflict() {
        let registrar = TestTextCommandHotKeyRegistrar(outcomes: [.success()])
        let oldTextCommand = TextCommandHotKey(
            keyCode: UInt32(kVK_ANSI_T),
            modifiers: UInt32(controlKey | optionKey)
        )
        let singleScreenshot = ScreenshotHotKey(
            keyCode: UInt32(kVK_F12),
            modifiers: 0
        )
        var saved = oldTextCommand
        var persistCalls = 0
        let manager = TextCommandHotKeyManager(
            savedHotKey: oldTextCommand,
            screenshotHotKey: singleScreenshot,
            registrar: registrar,
            persist: {
                persistCalls += 1
                saved = $0
                return true
            },
            onTextCommand: {}
        )
        let registrationsBeforeApply = registrar.registerCallCount
        let conflicting = TextCommandHotKey(
            keyCode: UInt32(kVK_F12),
            modifiers: 0
        )

        let result = manager.apply(conflicting)

        TextCommandHotKeyTestSupport.expect(
            result == .conflictsWithScreenshot
                && manager.effectiveHotKey == oldTextCommand
                && saved == oldTextCommand
                && registrar.registerCallCount == registrationsBeforeApply
                && persistCalls == 0,
            "TestTextCommandHotKeyConflictAndTransaction.test_unmodified_function_key_equal_to_screenshot_is_rejected_as_conflict"
        )
    }

    static func test_registration_failure_keeps_old_text_command_active() {
        let registrar = TestTextCommandHotKeyRegistrar(outcomes: [
            .success(),
            .failure(.registrationFailed(OSStatus(eventHotKeyExistsErr)))
        ])
        var saved = oldTextCommand
        var actions = 0
        let manager = TextCommandHotKeyManager(
            savedHotKey: oldTextCommand,
            screenshotHotKey: screenshot,
            registrar: registrar,
            persist: { saved = $0; return true },
            onTextCommand: { actions += 1 }
        )

        let result = manager.apply(newTextCommand)
        registrar.registrations.first?.fire()

        TextCommandHotKeyTestSupport.expect(
            result == .registrationFailed
                && manager.effectiveHotKey == oldTextCommand
                && saved == oldTextCommand
                && registrar.registrations.first?.isActive == true
                && actions == 1,
            "TestTextCommandHotKeyConflictAndTransaction.test_registration_failure_keeps_old_text_command_active"
        )
    }

    static func test_persistence_failure_removes_inactive_candidate_and_keeps_old_text_command_active() {
        let registrar = TestTextCommandHotKeyRegistrar(outcomes: [.success(), .success()])
        var saved = oldTextCommand
        var actions = 0
        let manager = TextCommandHotKeyManager(
            savedHotKey: oldTextCommand,
            screenshotHotKey: screenshot,
            registrar: registrar,
            persist: { candidate in
                if candidate == newTextCommand { return false }
                saved = candidate
                return true
            },
            onTextCommand: { actions += 1 }
        )

        let result = manager.apply(newTextCommand)
        registrar.registrations.forEach { $0.fire() }

        TextCommandHotKeyTestSupport.expect(
            result == .persistenceFailed(candidateCleanupFailed: false)
                && manager.effectiveHotKey == oldTextCommand
                && saved == oldTextCommand
                && registrar.registrations[0].isActive
                && !registrar.registrations[1].isActive
                && registrar.registrations[1].invalidateCallCount == 1
                && actions == 1,
            "TestTextCommandHotKeyConflictAndTransaction.test_persistence_failure_removes_inactive_candidate_and_keeps_old_text_command_active"
        )
    }

    static func test_old_unregistration_failure_rolls_back_saved_value_and_keeps_old_text_command_active() {
        let registrar = TestTextCommandHotKeyRegistrar(outcomes: [
            .success(invalidateStatuses: [OSStatus(-9876)]),
            .success()
        ])
        var saved = oldTextCommand
        var saveOutcomes = [true, true]
        var actions = 0
        let manager = TextCommandHotKeyManager(
            savedHotKey: oldTextCommand,
            screenshotHotKey: screenshot,
            registrar: registrar,
            persist: { candidate in
                let succeeds = saveOutcomes.removeFirst()
                if succeeds { saved = candidate }
                return succeeds
            },
            onTextCommand: { actions += 1 }
        )

        let result = manager.apply(newTextCommand)
        registrar.registrations.forEach { $0.fire() }

        TextCommandHotKeyTestSupport.expect(
            result == .oldRegistrationInvalidationFailed(
                configRollbackFailed: false,
                candidateCleanupFailed: false
            )
                && manager.effectiveHotKey == oldTextCommand
                && saved == oldTextCommand
                && registrar.registrations[0].isActive
                && !registrar.registrations[1].isActive
                && actions == 1,
            "TestTextCommandHotKeyConflictAndTransaction.test_old_unregistration_failure_rolls_back_saved_value_and_keeps_old_text_command_active"
        )
    }
}

final class TestTextCommandHotKeyRecordingRoute {
    static func test_current_hot_key_during_recording_only_refills_recorder_then_restores_action() {
        let registrar = TestTextCommandHotKeyRegistrar(outcomes: [.success()])
        var actions = 0
        var recorded: [TextCommandHotKey] = []
        let manager = TextCommandHotKeyManager(
            savedHotKey: .default,
            screenshotHotKey: ScreenshotHotKey.default,
            registrar: registrar,
            persist: { _ in true },
            onTextCommand: { actions += 1 }
        )

        manager.beginRecording { recorded.append($0) }
        registrar.registrations[0].fire()
        let actionsWhileRecording = actions
        manager.endRecording()
        registrar.registrations[0].fire()

        TextCommandHotKeyTestSupport.expect(
            recorded == [.default]
                && actionsWhileRecording == 0
                && actions == 1,
            "TestTextCommandHotKeyRecordingRoute.test_current_hot_key_during_recording_only_refills_recorder_then_restores_action"
        )
    }
}

@main
struct TextCommandHotKeyTests {
    static func main() {
        TestTextCommandHotKeyValueAndMigration.test_default_value_is_unmodified_grave_and_screenshot_default_is_unchanged()
        TestTextCommandHotKeyValueAndMigration.test_legacy_config_without_text_command_field_preserves_azure_and_custom_screenshot_values()
        TestTextCommandHotKeyValueAndMigration.test_new_config_round_trip_preserves_both_independent_hot_keys()
        TestTextCommandHotKeyValueAndMigration.test_saved_old_default_is_migrated_and_persisted_without_changing_azure_or_screenshot()
        TestTextCommandHotKeyValueAndMigration.test_saved_custom_text_command_is_not_replaced_by_default_migration()
        TestTextCommandHotKeyValueAndMigration.test_decoding_json_with_extra_modifier_bits_normalizes_stored_value()
        TestTextCommandHotKeyConflictAndTransaction.test_candidate_equal_to_screenshot_is_rejected_before_registration_or_save()
        TestTextCommandHotKeyConflictAndTransaction.test_unmodified_function_key_equal_to_screenshot_is_rejected_as_conflict()
        TestTextCommandHotKeyConflictAndTransaction.test_registration_failure_keeps_old_text_command_active()
        TestTextCommandHotKeyConflictAndTransaction.test_persistence_failure_removes_inactive_candidate_and_keeps_old_text_command_active()
        TestTextCommandHotKeyConflictAndTransaction.test_old_unregistration_failure_rolls_back_saved_value_and_keeps_old_text_command_active()
        TestTextCommandHotKeyRecordingRoute.test_current_hot_key_during_recording_only_refills_recorder_then_restores_action()

        if TextCommandHotKeyTestSupport.failures > 0 {
            print("\n\(TextCommandHotKeyTestSupport.failures) text-command hot-key test(s) failed")
            exit(1)
        }
        print("\nAll text-command hot-key tests passed")
    }
}
