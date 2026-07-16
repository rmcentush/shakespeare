import Foundation

enum AuthorStyleReference {
    private static var cachedContent: String?
    private static var cachedContentModificationDate: Date?
    private static var cachedLearnedPreferences: String?
    private static var cachedLearnedPreferencesModificationDate: Date?

    static var content: String {
        ensureWritableReferenceExists()
        return cachedString(
            url: writableReferenceURL,
            cachedValue: &cachedContent,
            cachedModificationDate: &cachedContentModificationDate
        ) ?? bundledContent()
    }

    static var learnedPreferences: String {
        ensureStyleDirectoryExists()
        return cachedString(
            url: learnedPreferencesURL,
            cachedValue: &cachedLearnedPreferences,
            cachedModificationDate: &cachedLearnedPreferencesModificationDate
        ) ?? ""
    }

    static var styleDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("Shakespeare")
            .appendingPathComponent("style")
    }

    static var writableReferenceURL: URL {
        styleDirectoryURL.appendingPathComponent("writing_style_reference.md")
    }

    static var learnedPreferencesURL: URL {
        styleDirectoryURL.appendingPathComponent("learned_preferences.md")
    }

    static func reload() {
        cachedContent = nil
        cachedContentModificationDate = nil
        cachedLearnedPreferences = nil
        cachedLearnedPreferencesModificationDate = nil
    }

    static func writeLearnedPreferences(_ content: String) throws {
        ensureStyleDirectoryExists()
        try content.write(to: learnedPreferencesURL, atomically: true, encoding: .utf8)
        cachedLearnedPreferences = content
        cachedLearnedPreferencesModificationDate = modificationDate(for: learnedPreferencesURL)
    }

    private static func ensureWritableReferenceExists() {
        ensureStyleDirectoryExists()
        guard !FileManager.default.fileExists(atPath: writableReferenceURL.path),
              let bundledURL = Bundle.shakespeareResources.url(
                forResource: "writing_style_reference",
                withExtension: "md"
              )
        else { return }

        do {
            try FileManager.default.copyItem(at: bundledURL, to: writableReferenceURL)
        } catch {
            print("AuthorStyleReference: failed to copy writable style guide: \(error)")
        }
    }

    private static func ensureStyleDirectoryExists() {
        try? FileManager.default.createDirectory(
            at: styleDirectoryURL,
            withIntermediateDirectories: true
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
