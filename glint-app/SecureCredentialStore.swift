import Foundation
import Security

enum SecureCredentialStore {
    private static let service = "com.yoryon.glint.azure-api-keys"

    static let client = AzureKeychainClient(
        read: read,
        write: write
    )

    private static func read(_ slot: AzureAPIKeySlot) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: slot.rawValue,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    private static func write(_ value: String, _ slot: AzureAPIKeySlot) -> Bool {
        let identity: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: slot.rawValue
        ]
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            let status = SecItemDelete(identity as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }

        let data = Data(clean.utf8)
        let updateStatus = SecItemUpdate(
            identity as CFDictionary,
            [kSecValueData: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        var item = identity
        item[kSecValueData] = data
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}
