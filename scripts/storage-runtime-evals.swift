import Foundation

private enum ExpectedFailure: LocalizedError {
    case unavailable

    var errorDescription: String? { "Storage unavailable for evaluation." }
}

@main
private struct StorageRuntimeEvals {
    @MainActor
    static func main() {
        let base = URL(fileURLWithPath: "/tmp/application-support", isDirectory: true)
        let productionRoot = ShakespeareRuntime.storageRootURL(
            applicationSupportURL: base,
            bundleIdentifier: ShakespeareRuntime.productionBundleIdentifier
        )
        precondition(productionRoot == base.appendingPathComponent("Shakespeare", isDirectory: true))
        precondition(
            ShakespeareRuntime.keychainServicePrefix(
                bundleIdentifier: ShakespeareRuntime.productionBundleIdentifier
            ) == "com.shakespeare.credential.v2"
        )

        let auditRoot = ShakespeareRuntime.storageRootURL(
            applicationSupportURL: base,
            bundleIdentifier: "com.shakespeare.audit"
        )
        precondition(auditRoot != productionRoot)
        precondition(auditRoot.path.contains("Shakespeare-Development/com.shakespeare.audit"))
        precondition(
            ShakespeareRuntime.keychainServicePrefix(bundleIdentifier: "com.shakespeare.audit")
                == "com.shakespeare.credential.v2.development.com.shakespeare.audit"
        )

        let swiftPMRoot = ShakespeareRuntime.storageRootURL(
            applicationSupportURL: base,
            bundleIdentifier: nil
        )
        precondition(swiftPMRoot != productionRoot)
        precondition(swiftPMRoot.lastPathComponent == "swiftpm")

        var attempts = 0
        let status = ApplicationStorageStatus {
            attempts += 1
            if attempts == 1 { throw ExpectedFailure.unavailable }
        }
        status.prepare()
        precondition(!status.isReady)
        precondition(status.failureMessage == ExpectedFailure.unavailable.localizedDescription)
        status.prepare()
        precondition(status.isReady)
        precondition(status.failureMessage == nil)

        print("Storage runtime evals passed (production isolation and visible retry state).")
    }
}
