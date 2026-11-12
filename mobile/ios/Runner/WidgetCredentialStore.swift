import Foundation
import Security
import LocalAuthentication

/// One device-local item shared only by Runner and its widget extension.
/// The complete connection config lives here: proxy headers can contain secrets too.
enum WidgetCredentialStore {
    static let service = "am.sure.mobile.widget.connection"
    static let account = "connection-v1"

    static var accessGroup: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SureWidgetKeychainGroup") as? String,
              !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }

    private static var query: [String: Any]? {
        guard let group = accessGroup else { return nil }
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service, kSecAttrAccount as String: account,
                kSecAttrAccessGroup as String: group,
                kSecAttrSynchronizable as String: false]
    }

    enum Failure: Error { case unavailable, keychain(OSStatus), verification }

    static func readData() throws -> Data? {
        guard var query else { throw Failure.unavailable }
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        // Never show authentication UI from a background widget refresh.
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw Failure.keychain(status) }
        return data
    }

    static func load() -> [String: Any]? {
        guard let data = try? readData() else { return nil }
        return WidgetCredentialMigration.object(data)
    }

    static func save(_ object: [String: Any]) -> Bool {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return false }
        return saveVerified(data)
    }

    static func saveVerified(_ data: Data) -> Bool {
        guard let query else { return false }
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updated == errSecItemNotFound {
            let added = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            guard added == errSecSuccess else { return false }
        } else if updated != errSecSuccess { return false }
        // A reported write alone is not enough to delete the legacy credential.
        return (try? readData()) == data
    }

    static func clear() -> Bool {
        guard let query else { return false }
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

/// Pure migration policy, tested with synthetic in-memory storage. Only Runner
/// calls this; the widget never reads legacy plaintext, even on Keychain failure.
enum WidgetCredentialMigration {
    static func object(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func migrate(legacy: Data?, generation: Int,
                        readSecure: () throws -> Data?, saveVerified: (Data) -> Bool,
                        removeLegacy: () -> Bool) -> Bool {
        guard let legacy else { return true }
        guard let old = object(legacy), (old["generation"] as? Int ?? 0) == generation else {
            // A pre-logout file cannot resurrect the previous login.
            return removeLegacy()
        }
        do {
            if let existing = try readSecure(), let secure = object(existing),
               (secure["generation"] as? Int ?? 0) == generation {
                return removeLegacy() // Never overwrite the current secure identity.
            }
        } catch { return false } // Locked/denied is not the same as missing.
        guard saveVerified(legacy) else { return false }
        return removeLegacy()
    }
}
