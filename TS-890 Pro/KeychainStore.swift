import Foundation
import Security

enum KeychainStore {
    /// True when the process is hosted by the XCTest harness. Used to skip
    /// keychain reads during tests: the test host is re-signed on every build,
    /// so it never matches the keychain item's access list and would otherwise
    /// trigger a blocking "wants to use the keychain" prompt that hangs the
    /// test runner. Real app launches are unaffected.
    private static let isRunningUnderXCTest =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    static func setPassword(_ password: String, service: String, account: String) throws {
        let data = Data(password.utf8)
        try upsert(data: data, service: service, account: account)
    }

    static func getPassword(service: String, account: String) throws -> String? {
        // Under XCTest, behave as if no password is stored — see note above.
        if isRunningUnderXCTest { return nil }

        let query: [String: Any] = [
            kSecClass as String:      kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String:  kSecMatchLimitOne,
            kSecReturnData as String:  true
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, let pw = String(data: data, encoding: .utf8) {
            return pw
        }
        if status == errSecItemNotFound {
            return nil
        }
        throw NSError(domain: "KeychainStore", code: Int(status),
                      userInfo: [NSLocalizedDescriptionKey: "Keychain read failed (\(status))"])
    }

    static func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { return }
        throw NSError(domain: "KeychainStore", code: Int(status),
                      userInfo: [NSLocalizedDescriptionKey: "Keychain delete failed (\(status))"])
    }

    private static func upsert(data: Data, service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let existsStatus = SecItemCopyMatching(query as CFDictionary, nil)
        if existsStatus == errSecSuccess {
            let attrs: [String: Any] = [kSecValueData as String: data]
            let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
            if status != errSecSuccess {
                throw NSError(domain: "KeychainStore", code: Int(status),
                              userInfo: [NSLocalizedDescriptionKey: "Keychain update failed (\(status))"])
            }
            return
        }
        if existsStatus != errSecItemNotFound {
            throw NSError(domain: "KeychainStore", code: Int(existsStatus),
                          userInfo: [NSLocalizedDescriptionKey: "Keychain query failed (\(existsStatus))"])
        }
        var addQuery = query
        addQuery[kSecValueData as String]      = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            throw NSError(domain: "KeychainStore", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Keychain add failed (\(status))"])
        }
    }
}
