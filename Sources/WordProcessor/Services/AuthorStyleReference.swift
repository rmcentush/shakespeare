import Foundation

enum AuthorStyleReference {
    private static let cacheLock = NSLock()
    // Every access to these process-wide caches is serialized by cacheLock.
    private nonisolated(unsafe) static var cachedContent: String?
    private nonisolated(unsafe) static var cachedContentModificationDate: Date?
    private nonisolated(unsafe) static var cachedLearnedPreferences: String?
    private nonisolated(unsafe) static var cachedLearnedPreferencesModificationDate: Date?

    static var content: String {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        ensureWritableReferenceExists()
        return cachedString(
            url: writableReferenceURL,
            cachedValue: &cachedContent,
            cachedModificationDate: &cachedContentModificationDate
        ) ?? bundledContent()
    }

    static var learnedPreferences: String {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        ensureStyleDirectoryExists()
        return cachedString(
            url: learnedPreferencesURL,
            cachedValue: &cachedLearnedPreferences,
            cachedModificationDate: &cachedLearnedPreferencesModificationDate
        ) ?? ""
    }

    static var styleDirectoryURL: URL {
        try? ShakespeareStorage.prepare()
        return ShakespeareStorage.styleDirectoryURL
    }

    static var writableReferenceURL: URL {
        styleDirectoryURL.appendingPathComponent("writing_style_reference.md")
    }

    static var learnedPreferencesURL: URL {
        styleDirectoryURL.appendingPathComponent("learned_preferences.md")
    }

    static func reload() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        cachedContent = nil
        cachedContentModificationDate = nil
        cachedLearnedPreferences = nil
        cachedLearnedPreferencesModificationDate = nil
    }

    static func writeLearnedPreferences(_ content: String) throws {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        ensureStyleDirectoryExists()
        try content.write(to: learnedPreferencesURL, atomically: true, encoding: .utf8)
        try protectFile(at: learnedPreferencesURL)
        cachedLearnedPreferences = content
        cachedLearnedPreferencesModificationDate = modificationDate(for: learnedPreferencesURL)
    }

    private static func ensureWritableReferenceExists() {
        ensureStyleDirectoryExists()
        if FileManager.default.fileExists(atPath: writableReferenceURL.path) {
            try? protectFile(at: writableReferenceURL)
            return
        }
        guard let bundledURL = Bundle.shakespeareResources.url(
                forResource: "writing_style_reference",
                withExtension: "md"
              )
        else { return }

        do {
            try FileManager.default.copyItem(at: bundledURL, to: writableReferenceURL)
            try protectFile(at: writableReferenceURL)
        } catch {
            print("AuthorStyleReference: failed to copy writable style guide: \(error)")
        }
    }

    private static func ensureStyleDirectoryExists() {
        do {
            try FileManager.default.createDirectory(
                at: styleDirectoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: styleDirectoryURL.path
            )
        } catch {
            print("AuthorStyleReference: failed to protect style directory: \(error)")
        }
    }

    private static func protectFile(at url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    private static func bundledContent() -> String {
        guard let resourceURL = Bundle.shakespeareResources.url(
                forResource: "writing_style_reference",
                withExtension: "md"
              ),
              let content = try? String(contentsOf: resourceURL, encoding: .utf8)
        else { return "" }
        return content
    }

    private static func cachedString(
        url: URL,
        cachedValue: inout String?,
        cachedModificationDate: inout Date?
    ) -> String? {
        let currentModificationDate = modificationDate(for: url)
        if let cachedValue, cachedModificationDate == currentModificationDate {
            return cachedValue
        }

        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            cachedValue = nil
            cachedModificationDate = nil
            return nil
        }

        cachedValue = content
        cachedModificationDate = currentModificationDate
        return content
    }

    private static func modificationDate(for url: URL) -> Date? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]) else {
            return nil
        }
        return values.contentModificationDate
    }
}
