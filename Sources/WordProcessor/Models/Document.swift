import SwiftUI

@Observable
final class DocumentModel {
    var htmlContent: String = ""
    var fileURL: URL?
    var isDirty: Bool = false
    var wordCount: Int = 0
    var characterCount: Int = 0

    private static let recentFilesKey = "recentFileBookmarks"
    private static let maxRecentFiles = 10

    var displayName: String {
        if let url = fileURL {
            return url.deletingPathExtension().lastPathComponent
        }
        return "Untitled"
    }

    var windowTitle: String {
        let name = displayName
        return isDirty ? "\(name) — Edited" : name
    }

    func newDocument() {
        htmlContent = ""
        fileURL = nil
        isDirty = false
        wordCount = 0
        characterCount = 0
    }

    func updateContent(_ html: String) {
        htmlContent = html
        isDirty = true
    }

    func updateWordCount(words: Int, characters: Int) {
        wordCount = words
        characterCount = characters
    }

    func markSaved(url: URL) {
        fileURL = url
        isDirty = false
        Self.addToRecentFiles(url)
    }

    func loadFromURL(_ url: URL) throws {
        let html = try String(contentsOf: url, encoding: .utf8)
        htmlContent = html
        fileURL = url
        isDirty = false
        Self.addToRecentFiles(url)
    }

    // MARK: - Recent Files

    static func addToRecentFiles(_ url: URL) {
        var bookmarks = UserDefaults.standard.array(forKey: recentFilesKey) as? [Data] ?? []

        // Create a security-scoped bookmark
        if let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            // Remove existing bookmark for the same file
            let resolvedURLs = bookmarks.compactMap { data -> (Data, URL)? in
                var stale = false
                guard let resolved = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
                return (data, resolved)
            }
            bookmarks = resolvedURLs.filter { $0.1 != url }.map { $0.0 }

            // Add to front
            bookmarks.insert(bookmark, at: 0)

            // Trim to max
            if bookmarks.count > maxRecentFiles {
                bookmarks = Array(bookmarks.prefix(maxRecentFiles))
            }

            UserDefaults.standard.set(bookmarks, forKey: recentFilesKey)
        }
    }

    static func recentFiles() -> [(url: URL, name: String)] {
        let bookmarks = UserDefaults.standard.array(forKey: recentFilesKey) as? [Data] ?? []
        return bookmarks.compactMap { data in
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
            let name = url.deletingPathExtension().lastPathComponent
            return (url: url, name: name)
        }
    }

    static func clearRecentFiles() {
        UserDefaults.standard.removeObject(forKey: recentFilesKey)
    }
}
