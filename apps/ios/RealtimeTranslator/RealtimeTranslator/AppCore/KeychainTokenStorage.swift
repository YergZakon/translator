import Foundation
import Security

protocol TokenStorage {
    func getAppToken() -> String?
    func saveAppToken(_ token: String) throws
    func getInstallationPublicId() -> UUID?
    func saveInstallationPublicId(_ id: UUID) throws
    func deleteToken() throws
}

enum KeychainError: Error, LocalizedError {
    case invalidData
    case secError(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Failed to convert data to/from UTF-8 string."
        case .secError(let status):
            return "Keychain error: \(status)"
        }
    }
}

class KeychainTokenStorage: TokenStorage {
    private let service = "com.realtimetranslator.keychain"
    private let tokenAccount = "appToken"
    private let installationAccount = "installationPublicId"

    private func saveString(_ string: String, forAccount account: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        // Try deleting the item first (in case it already exists)
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            throw KeychainError.secError(status)
        }
    }

    private func getString(forAccount account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        guard status == errSecSuccess, let data = dataTypeRef as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.secError(status)
        }
    }

    func getAppToken() -> String? {
        return getString(forAccount: tokenAccount)
    }

    func saveAppToken(_ token: String) throws {
        try saveString(token, forAccount: tokenAccount)
    }

    func getInstallationPublicId() -> UUID? {
        guard let string = getString(forAccount: installationAccount) else {
            return nil
        }
        return UUID(uuidString: string)
    }

    func saveInstallationPublicId(_ id: UUID) throws {
        try saveString(id.uuidString, forAccount: installationAccount)
    }

    func deleteToken() throws {
        try delete(account: tokenAccount)
    }
}

class MemoryTokenStorage: TokenStorage {
    private var token: String?
    private var installationId: UUID?

    init(appToken: String? = nil, installationId: UUID? = nil) {
        self.token = appToken
        self.installationId = installationId
    }

    func getAppToken() -> String? {
        return token
    }

    func saveAppToken(_ token: String) throws {
        self.token = token
    }

    func getInstallationPublicId() -> UUID? {
        return installationId
    }

    func saveInstallationPublicId(_ id: UUID) throws {
        self.installationId = id
    }

    func deleteToken() throws {
        token = nil
    }
}

