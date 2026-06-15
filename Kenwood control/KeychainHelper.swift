//
//  KeychainHelper.swift
//  Kenwood control
//

import Foundation
import Security

final class KeychainHelper {
    static let shared = KeychainHelper()
    private init() {}

    private let bundleID: String = Bundle.main.bundleIdentifier ?? "com.ai5os.ts890pro"

    enum Service: String {
        case qrz     = "qrz"
        case hamqth  = "hamqth"
        case lotw    = "lotw"
        case qrzLog  = "qrzlog"
        case clubLog = "clublog"
        case eqsl    = "eqsl"

        func qualified(with bundleID: String) -> String { "\(bundleID).\(rawValue)" }
    }

    @discardableResult
    func save(username: String, password: String, service: Service) -> Bool {
        let key = service.qualified(with: bundleID)
        delete(service: service)
        guard let data = "\(username):\(password)".data(using: .utf8) else { return false }
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: key,
            kSecValueData:   data,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    func retrieve(service: Service) -> (username: String, password: String)? {
        let key = service.qualified(with: bundleID)
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: key,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let s = String(data: data, encoding: .utf8) else { return nil }
        let parts = s.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    func delete(service: Service) {
        let key = service.qualified(with: bundleID)
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    func hasCredentials(for service: Service) -> Bool {
        retrieve(service: service) != nil
    }
}
