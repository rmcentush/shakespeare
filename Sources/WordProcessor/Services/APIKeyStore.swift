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

/// Stores API keys in the macOS Keychain. A legacy owner-only credential file
/// is read only to migrate older installations; new credentials are never
/// written outside Keychain, including in ad-hoc development builds.
final class APIKeyStore: Sendable {
    static let shared = APIKeyStore()
    static let keychainItemLabel = "Shakespeare"
    static let keychainServicePrefix = "com.shakespeare.credential.v2"
    private let keychainAccount = "default"
    private let sessionCache = APIKeySessionCache()
    private let storageDirectoryOverride: URL?
    private let keychainContainsOverride: (@Sendable (String) -> Bool)?
    private let keychainReadOverride: (@Sendable (String) -> String?)?
    private let keychainWriteOverride: (@Sendable (String, String) -> Bool)?
    private let keychainDeleteOverride: (@Sendable (String) -> Void)?

    private var storageDirectory: URL {
        if let storageDirectoryOverride { return storageDirectoryOverride }
        try? ShakespeareStorage.prepare()
        return ShakespeareStorage.credentialsDirectoryURL
    }

    private init() {
        storageDirectoryOverride = nil
        keychainContainsOverride = nil
        keychainReadOverride = nil
        keychainWriteOverride = nil
        keychainDeleteOverride = nil
    }

    init(
        storageDirectory: URL,
        keychainContains: (@Sendable (String) -> Bool)? = nil,
        keychainRead: (@Sendable (String) -> String?)? = nil,
        keychainWrite: (@Sendable (String, String) -> Bool)? = nil,
        keychainDelete: (@Sendable (String) -> Void)? = nil
    ) {
        storageDirectoryOverride = storageDirectory
        keychainContainsOverride = keychainContains
        keychainReadOverride = keychainRead
        keychainWriteOverride = keychainWrite
        keychainDeleteOverride = keychainDelete
    }

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
        if containsKeychainAPIKey(service: service) { return true }

        // Report a legacy file as connected only until the next authorized read,
        // when it is migrated to Keychain and securely removed.
        return legacyCredentialExists(at: fallbackPath)
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
        if let key = readKeychainAPIKey(service: service) {
            sessionCache.setValue(key, for: service)
            return key
        }

        guard let key = fallbackAPIKey(service: service) else { return nil }
        guard storeKeychainAPIKey(key, service: service) else { return nil }
        deleteFallbackAPIKey(service: service)
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

        if storeKeychainAPIKey(normalizedKey, service: service) {
            deleteFallbackAPIKey(service: service)
            sessionCache.setValue(normalizedKey, for: service)
            return true
        }

        // Never downgrade a Keychain failure to a plaintext credential file.
        return false
    }

    func deleteAPIKey(service: String) {
        guard keyFilePath(service: service) != nil else { return }
        if let keychainDeleteOverride {
            keychainDeleteOverride(service)
        } else {
            SecItemDelete(keychainQuery(service: service) as CFDictionary)
        }
        deleteFallbackAPIKey(service: service)
        sessionCache.setValue(nil, for: service)
    }

    private func keychainQuery(service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(Self.keychainServicePrefix).\(service)",
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

    private func containsKeychainAPIKey(service: String) -> Bool {
        keychainContainsOverride?(service) ?? keychainContainsAPIKey(service: service)
    }

    private func readKeychainAPIKey(service: String) -> String? {
        keychainReadOverride?(service) ?? keychainAPIKey(service: service)
    }

    private func setKeychainAPIKey(_ key: String, service: String) -> Bool {
        let query = keychainQuery(service: service)
        let data = Data(key.utf8)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [
                kSecValueData as String: data,
                kSecAttrLabel as String: Self.keychainItemLabel,
                kSecAttrDescription as String: "OpenRouter API key",
            ] as CFDictionary
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
        item[kSecAttrLabel as String] = Self.keychainItemLabel
        item[kSecAttrDescription as String] = "OpenRouter API key"
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        if addStatus != errSecSuccess {
            print("APIKeyStore: Keychain add failed with status \(addStatus)")
        }
        return addStatus == errSecSuccess
    }

    private func storeKeychainAPIKey(_ key: String, service: String) -> Bool {
        if let keychainWriteOverride {
            return keychainWriteOverride(key, service)
        }
        return setKeychainAPIKey(key, service: service)
    }

    private func fallbackAPIKey(service: String) -> String? {
        guard let path = keyFilePath(service: service) else { return nil }
        guard let raw = try? String(contentsOf: path, encoding: .utf8) else { return nil }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    private func legacyCredentialExists(at path: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path.path),
              let size = attributes[.size] as? NSNumber else { return false }
        return size.intValue > 0
    }

    private func deleteFallbackAPIKey(service: String) {
        guard let path = keyFilePath(service: service) else { return }
        try? FileManager.default.removeItem(at: path)
    }
}
