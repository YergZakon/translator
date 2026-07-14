import Foundation
import Security

protocol TokenStorage: AnyObject {
    func getAppToken() throws -> String?
    func saveAppToken(_ token: String) throws
    func getInstallationPublicId() throws -> UUID?
    func saveInstallationPublicId(_ id: UUID) throws
    func deleteToken() throws
}

enum KeychainError: Error, LocalizedError, Equatable {
    case invalidData
    case secError(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Keychain data is invalid."
        case .secError(let status):
            return "Keychain operation failed (\(status))."
        }
    }
}

protocol SecureStringStore {
    func read(account: String) throws -> String?
    func upsert(_ value: String, account: String) throws
    func delete(account: String) throws
}

final class SecurityKeychainStore: SecureStringStore {
    private let service: String

    init(service: String) {
        self.service = service
    }

    func read(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.secError(status) }
        guard
            let data = result as? Data,
            let value = String(data: data, encoding: .utf8)
        else {
            throw KeychainError.invalidData
        }
        return value
    }

    func upsert(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let values: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.secError(updateStatus)
        }

        var attributes = query
        values.forEach { attributes[$0.key] = $0.value }
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.secError(addStatus)
        }
    }

    func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.secError(status)
        }
    }
}

final class KeychainTokenStorage: TokenStorage {
    private let store: SecureStringStore
    private let tokenAccount = "appToken"
    private let installationAccount = "installationPublicId"

    init(store: SecureStringStore = SecurityKeychainStore(
        service: "com.yergakon.RealtimeTranslator.installationAuth"
    )) {
        self.store = store
    }

    func getAppToken() throws -> String? {
        try store.read(account: tokenAccount)
    }

    func saveAppToken(_ token: String) throws {
        try store.upsert(token, account: tokenAccount)
    }

    func getInstallationPublicId() throws -> UUID? {
        guard let value = try store.read(account: installationAccount) else {
            return nil
        }
        guard let id = UUID(uuidString: value) else {
            throw KeychainError.invalidData
        }
        return id
    }

    func saveInstallationPublicId(_ id: UUID) throws {
        try store.upsert(id.uuidString, account: installationAccount)
    }

    func deleteToken() throws {
        try store.delete(account: tokenAccount)
    }
}

final class MemoryTokenStorage: TokenStorage {
    private let lock = NSLock()
    private var token: String?
    private var installationId: UUID?

    init(appToken: String? = nil, installationId: UUID? = nil) {
        token = appToken
        self.installationId = installationId
    }

    func getAppToken() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return token
    }

    func saveAppToken(_ token: String) throws {
        lock.lock()
        defer { lock.unlock() }
        self.token = token
    }

    func getInstallationPublicId() throws -> UUID? {
        lock.lock()
        defer { lock.unlock() }
        return installationId
    }

    func saveInstallationPublicId(_ id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        installationId = id
    }

    func deleteToken() throws {
        lock.lock()
        defer { lock.unlock() }
        token = nil
    }
}
