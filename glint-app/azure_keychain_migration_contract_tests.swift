import Foundation

// Azure credential migration black-box contracts. All files live below a fresh
// temporary directory and all credentials are intentionally fictional.
//
// Intended command once the production contract exists:
//   swiftc -parse-as-library -o /tmp/glint_azure_keychain_migration_test \
//     TranslationFormatting.swift TranslationDocument.swift ScreenshotHotKey.swift \
//     HotKey.swift TextCommandHotKey.swift Config.swift \
//     azure_keychain_migration_contract_tests.swift \
//     -framework Foundation -framework Carbon && \
//   /tmp/glint_azure_keychain_migration_test

enum AzureKeychainMigrationTestSupport {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() {
            print("  ok  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
        }
    }

    static func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("glint-keychain-contract-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func legacyConfigData(
        translatorKey: String,
        openAIKey: String,
        speechKey: String
    ) -> Data {
        let object: [String: Any] = [
            "translator": [
                "endpoint": "https://translator.invalid",
                "apiKey": translatorKey,
                "region": "test-region"
            ],
            "azureOpenAI": [
                "endpoint": "https://openai.invalid/openai/v1",
                "apiKey": openAIKey,
                "deploymentName": "fictional-deployment",
                "supportsVision": false
            ],
            "speech": [
                "endpoint": "https://speech.invalid",
                "apiKey": speechKey
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    static func containsForbiddenPlaintext(in data: Data, values: [String]) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else { return true }
        if values.contains(where: text.contains) { return true }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return true }
        return containsAPIKeyField(object)
    }

    private static func containsAPIKeyField(_ value: Any) -> Bool {
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                let normalized = key.lowercased().filter(\.isLetter)
                if normalized == "apikey" || normalized == "azureapikey" { return true }
                if containsAPIKeyField(child) { return true }
            }
        } else if let array = value as? [Any] {
            return array.contains(where: containsAPIKeyField)
        }
        return false
    }

    static func permissions(at url: URL) -> Int? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.posixPermissions] as? NSNumber)?.intValue
    }
}

final class RecordingAzureKeychain {
    var values: [AzureAPIKeySlot: String] = [:]
    var writes: [AzureAPIKeySlot] = []
    var failingSlots: Set<AzureAPIKeySlot> = []

    lazy var client = AzureKeychainClient(
        read: { [weak self] slot in self?.values[slot] },
        write: { [weak self] value, slot in
            guard let self else { return false }
            self.writes.append(slot)
            guard !self.failingSlots.contains(slot) else { return false }
            self.values[slot] = value
            return true
        }
    )
}

final class TestAzureKeychainMigration {
    private static let translatorKey = "fictional-translator-key-4d83"
    private static let openAIKey = "fictional-openai-key-91af"
    private static let speechKey = "fictional-speech-key-c257"

    static func test_plaintextConfigAndBackup_migrateAllKeysAndRewriteSanitizedFilesWithPrivatePermissions() {
        let directory = AzureKeychainMigrationTestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appendingPathComponent("config.json")
        let backupURL = directory.appendingPathComponent("config.pre-azure-backup.json")
        let legacy = AzureKeychainMigrationTestSupport.legacyConfigData(
            translatorKey: translatorKey,
            openAIKey: openAIKey,
            speechKey: speechKey
        )
        try! legacy.write(to: configURL)
        try! legacy.write(to: backupURL)

        let keychain = RecordingAzureKeychain()
        let loaded = AppConfig.loadOrCreate(at: configURL, keychain: keychain.client)
        let persistedConfig = try? Data(contentsOf: configURL)
        let persistedBackup = try? Data(contentsOf: backupURL)
        let secrets = [translatorKey, openAIKey, speechKey]

        AzureKeychainMigrationTestSupport.expect(
            loaded.translator.apiKey == translatorKey
                && loaded.azureOpenAI.apiKey == openAIKey
                && loaded.speech.apiKey == speechKey
                && keychain.values[.translator] == translatorKey
                && keychain.values[.openAI] == openAIKey
                && keychain.values[.speech] == speechKey
                && persistedConfig.map { !AzureKeychainMigrationTestSupport.containsForbiddenPlaintext(in: $0, values: secrets) } == true
                && persistedBackup.map { !AzureKeychainMigrationTestSupport.containsForbiddenPlaintext(in: $0, values: secrets) } == true
                && AzureKeychainMigrationTestSupport.permissions(at: configURL) == 0o600
                && AzureKeychainMigrationTestSupport.permissions(at: backupURL) == 0o600,
            "TestAzureKeychainMigration.test_plaintextConfigAndBackup_migrateAllKeysAndRewriteSanitizedFilesWithPrivatePermissions"
        )
    }

    static func test_secondLoadAfterSuccessfulMigration_isIdempotentAndDoesNotRewriteKeychain() {
        let directory = AzureKeychainMigrationTestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appendingPathComponent("config.json")
        let legacy = AzureKeychainMigrationTestSupport.legacyConfigData(
            translatorKey: translatorKey,
            openAIKey: openAIKey,
            speechKey: speechKey
        )
        try! legacy.write(to: configURL)

        let keychain = RecordingAzureKeychain()
        let first = AppConfig.loadOrCreate(at: configURL, keychain: keychain.client)
        let firstBytes = try? Data(contentsOf: configURL)
        let writeCount = keychain.writes.count
        let second = AppConfig.loadOrCreate(at: configURL, keychain: keychain.client)
        let secondBytes = try? Data(contentsOf: configURL)

        AzureKeychainMigrationTestSupport.expect(
            first.translator.apiKey == translatorKey
                && second.translator.apiKey == translatorKey
                && second.azureOpenAI.apiKey == openAIKey
                && second.speech.apiKey == speechKey
                && writeCount == 3
                && keychain.writes.count == writeCount
                && firstBytes == secondBytes,
            "TestAzureKeychainMigration.test_secondLoadAfterSuccessfulMigration_isIdempotentAndDoesNotRewriteKeychain"
        )
    }

    static func test_keychainWriteFailure_preservesEveryLegacyPlaintextFileUntilMigrationCanRetry() {
        let directory = AzureKeychainMigrationTestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appendingPathComponent("config.json")
        let backupURL = directory.appendingPathComponent("config.pre-azure-backup.json")
        let legacy = AzureKeychainMigrationTestSupport.legacyConfigData(
            translatorKey: translatorKey,
            openAIKey: openAIKey,
            speechKey: speechKey
        )
        try! legacy.write(to: configURL)
        try! legacy.write(to: backupURL)
        let originalConfig = try! Data(contentsOf: configURL)
        let originalBackup = try! Data(contentsOf: backupURL)

        let keychain = RecordingAzureKeychain()
        keychain.failingSlots = [.openAI]
        let loaded = AppConfig.loadOrCreate(at: configURL, keychain: keychain.client)

        AzureKeychainMigrationTestSupport.expect(
            loaded.translator.apiKey == translatorKey
                && loaded.azureOpenAI.apiKey == openAIKey
                && loaded.speech.apiKey == speechKey
                && (try? Data(contentsOf: configURL)) == originalConfig
                && (try? Data(contentsOf: backupURL)) == originalBackup,
            "TestAzureKeychainMigration.test_keychainWriteFailure_preservesEveryLegacyPlaintextFileUntilMigrationCanRetry"
        )
    }
}

@main
struct AzureKeychainMigrationContractTests {
    static func main() {
        TestAzureKeychainMigration.test_plaintextConfigAndBackup_migrateAllKeysAndRewriteSanitizedFilesWithPrivatePermissions()
        TestAzureKeychainMigration.test_secondLoadAfterSuccessfulMigration_isIdempotentAndDoesNotRewriteKeychain()
        TestAzureKeychainMigration.test_keychainWriteFailure_preservesEveryLegacyPlaintextFileUntilMigrationCanRetry()

        if AzureKeychainMigrationTestSupport.failures > 0 {
            print("\n\(AzureKeychainMigrationTestSupport.failures) Azure Keychain migration contract test(s) failed")
            exit(1)
        }
        print("\nAll Azure Keychain migration contract tests passed")
    }
}
