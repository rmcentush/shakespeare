import Darwin
import Foundation

@main
struct APIKeyStoreEvals {
    static func main() {
        guard APIKeyStore.keychainItemLabel == "Shakespeare" else {
            print("API key store eval failed: Keychain item label was not user-facing")
            exit(1)
        }
        guard APIKeyStore.keychainServicePrefix != "com.shakespeare.api" else {
            print("API key store eval failed: legacy Keychain service would still surface")
            exit(1)
        }
        guard !APIKeyStore.hasStableSigningIdentity() else {
            print("API key store eval failed: unsigned evaluator looked distribution-signed")
            exit(1)
        }

        let service = "shakespeare-eval-\(UUID().uuidString)"
        let expected = "temporary-test-key"
        defer { APIKeyStore.shared.deleteAPIKey(service: service) }

        guard !APIKeyStore.shared.hasAPIKey(service: service) else {
            print("API key store eval failed: temporary service should start empty")
            exit(1)
        }
        guard APIKeyStore.shared.setAPIKey(expected, service: service) else {
            print("API key store eval failed: could not save a temporary key")
            exit(1)
        }
        guard APIKeyStore.shared.hasAPIKey(service: service) else {
            print("API key store eval failed: saved key was not detected")
            exit(1)
        }
        guard APIKeyStore.shared.hasAuthorizedAPIKeyInSession(service: service) else {
            print("API key store eval failed: saved key was not available to authorized background work")
            exit(1)
        }
        guard APIKeyStore.shared.getAPIKey(service: service) == expected else {
            print("API key store eval failed: temporary key did not round-trip")
            exit(1)
        }

        APIKeyStore.shared.deleteAPIKey(service: service)
        guard !APIKeyStore.shared.hasAPIKey(service: service) else {
            print("API key store eval failed: deleted key was still detected")
            exit(1)
        }
        guard !APIKeyStore.shared.hasAuthorizedAPIKeyInSession(service: service) else {
            print("API key store eval failed: deleted key remained in the session cache")
            exit(1)
        }
        guard APIKeyStore.shared.getAPIKey(service: service) == nil else {
            print("API key store eval failed: temporary key was not deleted")
            exit(1)
        }

        let stableDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("shakespeare-stable-key-eval-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: stableDirectory) }
        let stableStore = APIKeyStore(
            testingDevelopmentStore: false,
            storageDirectory: stableDirectory,
            keychainWrite: { _, _ in false }
        )
        guard !stableStore.setAPIKey(expected, service: "openrouter") else {
            print("API key store eval failed: stable build accepted a failed Keychain write")
            exit(1)
        }
        guard !FileManager.default.fileExists(
            atPath: stableDirectory.appendingPathComponent("openrouter.key").path
        ) else {
            print("API key store eval failed: stable build wrote a fallback credential file")
            exit(1)
        }

        print("API key store eval passed.")
    }
}
