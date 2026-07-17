import Foundation
import LocalAuthentication
import Security

/// Keeps an authorized credential available for the lifetime of the process so
/// connection-status refreshes do not ask Keychain for the secret again.
private final class APIKeySessionCache: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func value(for service: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[service]
    }

    func setValue(_ value: String?, for service: String) {
        lock.lock()
        defer { lock.unlock() }
        values[service] = value
    }
}

/// Stores API keys in the macOS Keychain. Owner-only files under Application
/// Support remain as a compatibility fallback for locally built bundles whose
/// changing ad-hoc signatures cannot access an existing Keychain item.
final class APIKeyStore: Sendable {
    static let shared = APIKeyStore()
    private let keychainServicePrefix = "com.shakespeare.api"
    private let keychainAccount = "default"
    private let sessionCache = APIKeySessionCache()

    private var storageDirectory: URL {
        try? ShakespeareStorage.prepare()
        return ShakespeareStorage.credentialsDirectoryURL
    }

    private init() {}

    private func keyFilePath(service: String) -> URL? {
        guard !service.isEmpty,
              service.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil
        else {
            return nil
        }
        return storageDirectory.appendingPathComponent("\(service).key")
    }

    /// Checks connection state without requesting the secret bytes. UI surfaces
    /// use this method so opening onboarding, Settings, or research chat cannot
    /// produce a Keychain authorization prompt.
    func hasAPIKey(service: String) -> Bool {
        guard let fallbackPath = keyFilePath(service: service) else { return false }
        if sessionCache.value(for: service) != nil {
            return true
        }
        if keychainContainsAPIKey(service: service) {
            return true
        }

        guard let attributes = try? FileManager.default.attributesOfItem(
            atPath: fallbackPath.path
        ), let size = attributes[.size] as? NSNumber else {
            return false
        }
        return size.intValue > 0
    }

    /// Automatic background work may use a key only after the writer has already
    /// authorized it in this process. This avoids surprise Keychain prompts.
    func hasAuthorizedAPIKeyInSession(service: String) -> Bool {
        sessionCache.value(for: service) != nil
    }

    func getAPIKey(service: String) -> String? {
        guard keyFilePath(service: service) != nil else { return nil }
        if let cachedKey = sessionCache.value(for: service) {
            return cachedKey
        }
        if let key = keychainAPIKey(service: service) {
            sessionCache.setValue(key, for: service)
            return key
        }

        guard let key = fallbackAPIKey(service: service) else { return nil }
        if setKeychainAPIKey(key, service: service) {
            deleteFallbackAPIKey(service: service)
        }
        sessionCache.setValue(key, for: service)
        return key
    }

    @discardableResult
    func setAPIKey(_ key: String, service: String) -> Bool {
        guard keyFilePath(service: service) != nil else { return false }
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else {
            deleteAPIKey(service: service)
            return true
        }

        if setKeychainAPIKey(normalizedKey, service: service) {
            deleteFallbackAPIKey(service: service)
            sessionCache.setValue(normalizedKey, for: service)
            return true
        }

        guard setFallbackAPIKey(normalizedKey, service: service) else { return false }
        sessionCache.setValue(normalizedKey, for: service)
        return true
    }

    func deleteAPIKey(service: String) {
        guard keyFilePath(service: service) != nil else { return }
        SecItemDelete(keychainQuery(service: service) as CFDictionary)
        deleteFallbackAPIKey(service: service)
        sessionCache.setValue(nil, for: service)
    }

    private func keychainQuery(service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(keychainServicePrefix).\(service)",
            kSecAttrAccount as String: keychainAccount,
        ]
    }

    private func keychainAPIKey(service: String) -> String? {
        var query = keychainQuery(service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let raw = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    private func keychainContainsAPIKey(service: String) -> Bool {
        var query = keychainQuery(service: service)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let authenticationContext = LAContext()
        authenticationContext.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = authenticationContext

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    private func setKeychainAPIKey(_ key: String, service: String) -> Bool {
        let query = keychainQuery(service: service)
        let data = Data(key.utf8)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return true
        }
        guard updateStatus == errSecItemNotFound else {
            print("APIKeyStore: Keychain update failed with status \(updateStatus)")
            return false
        }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        if addStatus != errSecSuccess {
            print("APIKeyStore: Keychain add failed with status \(addStatus)")
        }
        return addStatus == errSecSuccess
    }

    private func fallbackAPIKey(service: String) -> String? {
        guard let path = keyFilePath(service: service) else { return nil }
        guard let raw = try? String(contentsOf: path, encoding: .utf8) else { return nil }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    private func setFallbackAPIKey(_ key: String, service: String) -> Bool {
        guard let path = keyFilePath(service: service) else { return false }
        let directory = storageDirectory
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
        } catch {
            print("APIKeyStore: failed to prepare secure storage: \(error)")
            return false
        }

        let temporaryPath = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
        let created = FileManager.default.createFile(
            atPath: temporaryPath.path,
            contents: Data(key.utf8),
            attributes: [.posixPermissions: 0o600]
        )
        guard created else {
            print("APIKeyStore: failed to write API key file for service \(service)")
            return false
        }

        do {
            if FileManager.default.fileExists(atPath: path.path) {
                _ = try FileManager.default.replaceItemAt(path, withItemAt: temporaryPath)
            } else {
                try FileManager.default.moveItem(at: temporaryPath, to: path)
            }
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: path.path
            )
            return true
        } catch {
            try? FileManager.default.removeItem(at: temporaryPath)
            print("APIKeyStore: failed to store API key for service \(service): \(error)")
            return false
        }
    }

    private func deleteFallbackAPIKey(service: String) {
        guard let path = keyFilePath(service: service) else { return }
        try? FileManager.default.removeItem(at: path)
    }
}
