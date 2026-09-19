import Foundation
import Security

/// One Keychain entry per Fathom account, keyed by that account's generated
/// ID. Never logs a key value, only status codes.
enum FathomKeychain {
    private static let service = "com.acdropp.Blocks.fathom"
    private static let legacyAccount = "FathomAPIKey"

    private static func accountAttribute(for accountID: String) -> String {
        "FathomAPIKey.\(accountID)"
    }

    @discardableResult
    static func save(_ key: String, accountID: String) -> Bool {
        save(key, keychainAccount: accountAttribute(for: accountID))
    }

    static func load(accountID: String) -> String? {
        load(keychainAccount: accountAttribute(for: accountID))
    }

    static func delete(accountID: String) {
        delete(keychainAccount: accountAttribute(for: accountID))
    }

    // MARK: - One-time migration from the old single-account storage

    static func loadLegacyKey() -> String? {
        load(keychainAccount: legacyAccount)
    }

    static func deleteLegacyKey() {
        delete(keychainAccount: legacyAccount)
    }

    // MARK: - Shared implementation

    private static func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    @discardableResult
    private static func save(_ key: String, keychainAccount: String) -> Bool {
        let baseQuery = query(account: keychainAccount)
        SecItemDelete(baseQuery as CFDictionary)
        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(key.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            print("[Fathom] Keychain save failed: OSStatus \(status)")
            return false
        }
        return true
    }

    private static func load(keychainAccount: String) -> String? {
        var query = query(account: keychainAccount)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                print("[Fathom] Keychain load failed: OSStatus \(status)")
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(keychainAccount: String) {
        SecItemDelete(query(account: keychainAccount) as CFDictionary)
    }
}
