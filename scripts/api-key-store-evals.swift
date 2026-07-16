import Darwin
import Foundation

@main
struct APIKeyStoreEvals {
    static func main() {
        let service = "shakespeare-eval-\(UUID().uuidString)"
        let expected = "temporary-test-key"
        defer { APIKeyStore.shared.deleteAPIKey(service: service) }

        guard APIKeyStore.shared.setAPIKey(expected, service: service) else {
            print("API key store eval failed: could not save a temporary key")
            exit(1)
        }
        guard APIKeyStore.shared.getAPIKey(service: service) == expected else {
            print("API key store eval failed: temporary key did not round-trip")
            exit(1)
        }

        APIKeyStore.shared.deleteAPIKey(service: service)
        guard APIKeyStore.shared.getAPIKey(service: service) == nil else {
            print("API key store eval failed: temporary key was not deleted")
            exit(1)
        }

        print("API key store eval passed.")
    }
}
