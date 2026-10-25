import Foundation
import Security

struct AuthTokens: Codable, Sendable, Equatable {
    let accessToken: String
    let expiresAt: Date? // Initial OAuth expiry, not authoritative after server-side extension.
    var applicationKey: String? = nil
    var sessionSecretKey: String? = nil
    var accountID: String? = nil
}

/// Credentials stay on this device; they are never stored in UserDefaults or the snapshot.
actor KeychainTokenStore {
    enum Failure: Error { case status(OSStatus), invalidData }
    private let service: String
    private let account = "ok-oauth"

    init(service: String = Bundle.main.bundleIdentifier ?? "app.oknative.prototype") {
        self.service = service
    }

    func save(_ tokens: AuthTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let insertion = SecItemAdd(item as CFDictionary, nil)
            guard insertion == errSecSuccess else { throw Failure.status(insertion) }
        } else if status != errSecSuccess {
            throw Failure.status(status)
        }
    }

    func read() throws -> AuthTokens? {
        var item = query
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(item as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure.status(status) }
        guard let data = result as? Data else { throw Failure.invalidData }
        return try JSONDecoder().decode(AuthTokens.self, from: data)
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.status(status) }
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
}
