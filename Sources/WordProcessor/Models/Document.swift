import SwiftUI

@Observable
final class DocumentModel {
    struct PersistenceRequest: Sendable {
        let requestID: UInt64
        let generation: UInt64
        let revision: UInt64
        let snapshot: DocumentFileStore.FileSnapshot
    }

    var htmlContent: String = ""
    var fileURL: URL?
    var isDirty: Bool = false
    var wordCount: Int = 0
    var characterCount: Int = 0

    private static let recentFilesKey = "recentFileBookmarks"
    private static let maxRecentFiles = 10
    private var documentGeneration: UInt64 = 0
    private var contentRevision: UInt64 = 0
    private var nextPersistenceRequestID: UInt64 = 0
    private var lastCommittedPersistenceRequestID: UInt64 = 0

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
        documentGeneration &+= 1
        contentRevision = 0
        htmlContent = ""
        fileURL = nil
        isDirty = false
        wordCount = 0
        characterCount = 0
    }

    func updateContent(_ html: String) {
        let changed = html != htmlContent
        htmlContent = html
        if changed {
            contentRevision &+= 1
            isDirty = true
        }
    }

    func updateWordCount(words: Int, characters: Int) {
        wordCount = words
        characterCount = characters
    }

    func syncFromEditor(snapshot: DocumentFileStore.FileSnapshot) {
        let changed = snapshot.htmlContent != htmlContent
        htmlContent = snapshot.htmlContent
        wordCount = snapshot.wordCount
        characterCount = snapshot.characterCount
        if changed {
            contentRevision &+= 1
            isDirty = true
        }
    }

    func syncFromEditor(html: String, words: Int, characters: Int) {
        let changed = html != htmlContent
        htmlContent = html
        wordCount = words
        characterCount = characters
        if changed {
            contentRevision &+= 1
            isDirty = true
        }
    }

    func markSaved(url: URL, request: PersistenceRequest) {
        guard request.generation == documentGeneration else { return }
        guard request.requestID >= lastCommittedPersistenceRequestID else { return }

        lastCommittedPersistenceRequestID = request.requestID
        fileURL = url
        wordCount = request.snapshot.wordCount
        characterCount = request.snapshot.characterCount
        isDirty = request.revision != contentRevision
        Self.addToRecentFiles(url)
    }

    func load(snapshot: DocumentFileStore.FileSnapshot, from url: URL) {
        documentGeneration &+= 1
        contentRevision = 0
        htmlContent = snapshot.htmlContent
        fileURL = url
        isDirty = false
        wordCount = snapshot.wordCount
        characterCount = snapshot.characterCount
        Self.addToRecentFiles(url)
    }

    func restoreVersion(snapshot: DocumentFileStore.FileSnapshot) {
        let changed = snapshot.htmlContent != htmlContent
        htmlContent = snapshot.htmlContent
        wordCount = snapshot.wordCount
        characterCount = snapshot.characterCount
        if changed {
            contentRevision &+= 1
        }
        isDirty = true
    }

    func makePersistenceRequest() -> PersistenceRequest {
        nextPersistenceRequestID &+= 1
        return PersistenceRequest(
            requestID: nextPersistenceRequestID,
            generation: documentGeneration,
            revision: contentRevision,
            snapshot: currentSnapshot()
        )
    }

    func currentSnapshot() -> DocumentFileStore.FileSnapshot {
        DocumentFileStore.FileSnapshot(
            htmlContent: htmlContent,
            wordCount: wordCount,
            characterCount: characterCount
        )
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
