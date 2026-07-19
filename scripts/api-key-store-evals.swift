import Darwin
import Foundation

private final class KeychainDouble: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    private var acceptsWrites = true

    func setAcceptsWrites(_ value: Bool) {
        lock.withLock { acceptsWrites = value }
    }

    func contains(_ service: String) -> Bool {
        lock.withLock { values[service] != nil }
    }

    func read(_ service: String) -> String? {
        lock.withLock { values[service] }
    }

    func write(_ value: String, service: String) -> Bool {
        lock.withLock {
            guard acceptsWrites else { return false }
            values[service] = value
            return true
        }
    }

    func delete(_ service: String) {
        lock.withLock { values[service] = nil }
    }
}

@main
struct APIKeyStoreEvals {
    static func main() {
        guard APIKeyStore.keychainItemLabel == "Shakespeare" else {
            fail("Keychain item label was not user-facing")
        }
        guard APIKeyStore.keychainServicePrefix != "com.shakespeare.api" else {
            fail("legacy Keychain service would still surface")
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("shakespeare-key-eval-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let keychain = KeychainDouble()
        let store = APIKeyStore(
            storageDirectory: directory,
            keychainContains: { keychain.contains($0) },
            keychainRead: { keychain.read($0) },
            keychainWrite: { keychain.write($0, service: $1) },
            keychainDelete: { keychain.delete($0) }
        )
        let expected = "temporary-test-key"

        guard !store.hasAPIKey(service: "openrouter") else { fail("store should start empty") }
        guard store.setAPIKey(expected, service: "openrouter") else { fail("Keychain write failed") }
        guard store.hasAPIKey(service: "openrouter") else { fail("saved key was not detected") }
        guard store.getAPIKey(service: "openrouter") == expected else { fail("key did not round-trip") }
        guard store.hasAuthorizedAPIKeyInSession(service: "openrouter") else {
            fail("saved key was not authorized for background work")
        }
        guard !FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("openrouter.key").path
        ) else { fail("a new credential was written to plaintext storage") }

        store.deleteAPIKey(service: "openrouter")
        guard !store.hasAPIKey(service: "openrouter") else { fail("deleted key was detected") }

        keychain.setAcceptsWrites(false)
        guard !store.setAPIKey(expected, service: "failed-write") else {
            fail("a failed Keychain write was accepted")
        }
        guard !FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("failed-write.key").path
        ) else { fail("a failed Keychain write fell back to plaintext") }

        keychain.setAcceptsWrites(true)
        let legacyPath = directory.appendingPathComponent("legacy.key")
        try? Data("legacy-secret".utf8).write(to: legacyPath, options: .atomic)
        let migrationStore = APIKeyStore(
            storageDirectory: directory,
            keychainContains: { keychain.contains($0) },
            keychainRead: { keychain.read($0) },
            keychainWrite: { keychain.write($0, service: $1) },
            keychainDelete: { keychain.delete($0) }
        )
        guard migrationStore.hasAPIKey(service: "legacy") else {
            fail("legacy credential was not discovered for migration")
        }
        guard migrationStore.getAPIKey(service: "legacy") == "legacy-secret" else {
            fail("legacy credential did not migrate")
        }
        guard keychain.read("legacy") == "legacy-secret" else {
            fail("legacy credential was not stored in Keychain")
        }
        guard !FileManager.default.fileExists(atPath: legacyPath.path) else {
            fail("legacy plaintext credential was not removed after migration")
        }

        print("API key store eval passed.")
    }

    private static func fail(_ message: String) -> Never {
        print("API key store eval failed: \(message)")
        exit(1)
    }
}
