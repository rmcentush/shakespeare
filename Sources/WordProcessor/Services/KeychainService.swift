import Foundation

/// Stores API keys as files in ~/Library/Application Support/Shakespeare/
/// with owner-only (0600) permissions. Avoids Keychain password prompts
/// that occur with unsigned apps.
final class KeychainService: Sendable {
    static let shared = KeychainService()

    private var storageDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Shakespeare")
    }

    private init() {}

    private func keyFilePath(service: String) -> URL {
        storageDirectory.appendingPathComponent(".\(service).key")
    }

    func getAPIKey(service: String) -> String? {
        let path = keyFilePath(service: service)
        guard let raw = try? String(contentsOf: path, encoding: .utf8) else { return nil }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    func setAPIKey(_ key: String, service: String) {
        let dir = storageDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = keyFilePath(service: service)
        try? key.write(to: path, atomically: true, encoding: .utf8)
        // Owner read/write only
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    }

    func deleteAPIKey(service: String) {
        let path = keyFilePath(service: service)
        try? FileManager.default.removeItem(at: path)
    }
}
