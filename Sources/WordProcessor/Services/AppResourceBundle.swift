import Foundation

extension Bundle {
    /// Resolves SwiftPM resources both beside a command-line build product and
    /// in a standard macOS app bundle under Contents/Resources.
    static let shakespeareResources: Bundle = {
        let bundleName = "WordProcessor_WordProcessor.bundle"
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(bundleName, isDirectory: true),
            Bundle.main.bundleURL.appendingPathComponent(bundleName, isDirectory: true),
        ].compactMap { $0 }

        for candidate in candidates {
            if let bundle = Bundle(url: candidate) {
                return bundle
            }
        }

        // Both app bundles and direct SwiftPM executables place the resource
        // bundle beside the running product. Avoid Bundle.module here because
        // SwiftPM's generated fallback embeds the developer's absolute build path
        // in the release binary.
        return Bundle.main
    }()
}
