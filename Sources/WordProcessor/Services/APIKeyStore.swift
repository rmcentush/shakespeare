import Foundation
import Security

/// Stores API keys in the macOS Keychain. Owner-only files under Application
/// Support remain as a compatibility fallback for locally built bundles whose
/// changing ad-hoc signatures cannot access an existing Keychain item.
final class APIKeyStore: Sendable {
    static let shared = APIKeyStore()
    private let keychainServicePrefix = "com.shakespeare.api"
    private let keychainAccount = "default"

    private var storageDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("Shakespeare")
    }

    private init() {}

    private func keyFilePath(service: String) -> URL? {
        guard !service.isEmpty,
              service.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil
        else {
            return nil
        }
        return storageDirectory.appendingPathComponent(".\(service).key")
    }

    func getAPIKey(service: String) -> String? {
        guard keyFilePath(service: service) != nil else { return nil }
        if let key = keychainAPIKey(service: service) {
            return key
        }

        guard let key = fallbackAPIKey(service: service) else { return nil }
        if setKeychainAPIKey(key, service: service) {
            deleteFallbackAPIKey(service: service)
        }
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
            return true
        }

        return setFallbackAPIKey(normalizedKey, service: service)
    }

    func deleteAPIKey(service: String) {
        guard keyFilePath(service: service) != nil else { return }
        SecItemDelete(keychainQuery(service: service) as CFDictionary)
        deleteFallbackAPIKey(service: service)
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
