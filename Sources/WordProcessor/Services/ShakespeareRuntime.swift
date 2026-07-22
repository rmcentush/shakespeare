import Foundation

/// Defines the one runtime identity that may access shipping data. SwiftPM
/// executables and alternate bundles are development runtimes by default, so
/// local testing cannot read or mutate the installed app's files or Keychain.
enum ShakespeareRuntime {
    static let productionBundleIdentifier = "com.shakespeare.app"
    private static let productionStorageDirectoryName = "Shakespeare"
    private static let developmentStorageDirectoryName = "Shakespeare-Development"
    private static let productionKeychainServicePrefix = "com.shakespeare.credential.v2"

    static var storageRootURL: URL {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return storageRootURL(
            applicationSupportURL: applicationSupportURL,
            bundleIdentifier: Bundle.main.bundleIdentifier
        )
    }

    static var keychainServicePrefix: String {
        keychainServicePrefix(bundleIdentifier: Bundle.main.bundleIdentifier)
    }

    static func storageRootURL(
        applicationSupportURL: URL,
        bundleIdentifier: String?
    ) -> URL {
        guard bundleIdentifier == productionBundleIdentifier else {
            return applicationSupportURL
                .appendingPathComponent(developmentStorageDirectoryName, isDirectory: true)
                .appendingPathComponent(
                    developmentIdentity(bundleIdentifier: bundleIdentifier),
                    isDirectory: true
                )
        }
        return applicationSupportURL.appendingPathComponent(
            productionStorageDirectoryName,
            isDirectory: true
        )
    }

    static func keychainServicePrefix(bundleIdentifier: String?) -> String {
        guard bundleIdentifier == productionBundleIdentifier else {
            let identity = developmentIdentity(bundleIdentifier: bundleIdentifier)
            return "\(productionKeychainServicePrefix).development.\(identity)"
        }
        return productionKeychainServicePrefix
    }

    private static func developmentIdentity(bundleIdentifier: String?) -> String {
        let candidate = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = candidate.flatMap { $0.isEmpty ? nil : $0 } ?? "swiftpm"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let sanitizedScalars = source.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(String(scalar)) : "-"
        }
        let sanitized = String(sanitizedScalars)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        return sanitized.isEmpty ? "unknown" : sanitized
    }
}
