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
/// Support are used by locally built bundles whose changing ad-hoc signatures
/// would otherwise trigger repeated Keychain authorization dialogs.
final class APIKeyStore: Sendable {
    static let shared = APIKeyStore()
    static let keychainItemLabel = "Shakespeare"
    static let keychainServicePrefix = "com.shakespeare.credential.v2"
    private let keychainAccount = "default"
    private let sessionCache = APIKeySessionCache()
    private let usesDevelopmentCredentialStore: Bool
    private let storageDirectoryOverride: URL?
    private let keychainWriteOverride: (@Sendable (String, String) -> Bool)?

    private var storageDirectory: URL {
        if let storageDirectoryOverride { return storageDirectoryOverride }
        try? ShakespeareStorage.prepare()
        return ShakespeareStorage.credentialsDirectoryURL
    }

    private init() {
        usesDevelopmentCredentialStore = !Self.hasStableSigningIdentity()
        storageDirectoryOverride = nil
        keychainWriteOverride = nil
    }

    init(
        testingDevelopmentStore: Bool,
        storageDirectory: URL,
        keychainWrite: (@Sendable (String, String) -> Bool)? = nil
    ) {
        usesDevelopmentCredentialStore = testingDevelopmentStore
        storageDirectoryOverride = storageDirectory
        keychainWriteOverride = keychainWrite
    }

    /// Developer ID and App Store signatures include a stable team identifier.
    /// Ad-hoc local builds do not, so their code requirement changes on every
    /// rebuild and macOS would ask for Keychain permission again.
    static func hasStableSigningIdentity(bundleURL: URL = Bundle.main.bundleURL) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode
        else {
            return false
        }

        var signingInformation: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        ) == errSecSuccess,
              let information = signingInformation as? [String: Any],
              let teamIdentifier = information[kSecCodeInfoTeamIdentifier as String] as? String
        else {
            return false
        }
        return !teamIdentifier.isEmpty
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
        if !usesDevelopmentCredentialStore {
            return keychainContainsAPIKey(service: service)
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
        if usesDevelopmentCredentialStore {
            guard let key = fallbackAPIKey(service: service) else { return nil }
            sessionCache.setValue(key, for: service)
            return key
        }
        if let key = keychainAPIKey(service: service) {
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

        if usesDevelopmentCredentialStore {
            guard setFallbackAPIKey(normalizedKey, service: service) else { return false }
            sessionCache.setValue(normalizedKey, for: service)
            return true
        }

        if storeKeychainAPIKey(normalizedKey, service: service) {
            deleteFallbackAPIKey(service: service)
            sessionCache.setValue(normalizedKey, for: service)
            return true
        }

        // A stable signed build must never downgrade a Keychain failure to a
        // plaintext credential file. Preserve any existing credential and let
        // the connection UI surface the failure.
        return false
    }

    func deleteAPIKey(service: String) {
        guard keyFilePath(service: service) != nil else { return }
        if !usesDevelopmentCredentialStore {
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
