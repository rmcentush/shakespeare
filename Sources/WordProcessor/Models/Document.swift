import SwiftUI

@Observable
@MainActor
final class DocumentModel: @unchecked Sendable {
    struct PersistenceRequest: Sendable {
        let requestID: UInt64
        let generation: UInt64
        let revision: UInt64
        let snapshot: DocumentFileStore.FileSnapshot
    }

    var canonicalJSONContent: String?
    var htmlContent: String = ""
    var plainTextContent: String = ""
    private(set) var notes: String = ""
    var fileURL: URL?
    var isDirty: Bool = false
    var wordCount: Int = 0
    var characterCount: Int = 0
    private(set) var personalizationOutcomes: [PersonalizationOutcomeSnapshot] = []
    var documentID: String = UUID().uuidString
    var schemaVersion: Int = DocumentFileStore.currentSchemaVersion
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    private(set) var hasUnsyncedEditorChanges: Bool = false
    private var unsavedDisplayName = "Untitled"

    private static let recentFilesKey = "recentFileBookmarks"
    private static let maxRecentFiles = 10
    private var documentGeneration: UInt64 = 0
    private var contentRevision: UInt64 = 0
    private var nextPersistenceRequestID: UInt64 = 0
    private var lastCommittedPersistenceRequestID: UInt64 = 0

    init() {
        applySnapshot(.empty(), fileURL: nil, markDirty: false, resetRevision: true)
    }

    var displayName: String {
        if let url = fileURL {
            return url.deletingPathExtension().lastPathComponent
        }
        return unsavedDisplayName
    }

    var windowTitle: String {
        let name = displayName
        return isDirty ? "\(name) — Edited" : name
    }

    func renameUnsavedDocument(to name: String) {
        guard fileURL == nil else { return }
        unsavedDisplayName = name
    }

    func markRenamed(from sourceURL: URL, to destinationURL: URL) {
        guard fileURL == sourceURL else { return }
        fileURL = destinationURL
        Self.replaceRecentFile(sourceURL, with: destinationURL)
    }

    func markEditorMutation() {
        contentRevision &+= 1
        modifiedAt = Date()
        isDirty = true
        hasUnsyncedEditorChanges = true
    }

    func updateNotes(_ notes: String) {
        guard notes != self.notes else { return }
        self.notes = notes
        contentRevision &+= 1
        modifiedAt = Date()
        isDirty = true
    }

    @discardableResult
    func syncFromEditor(snapshot: DocumentFileStore.FileSnapshot) -> Bool {
        let changed =
            snapshot.htmlContent != htmlContent ||
            snapshot.plainText != plainTextContent ||
            snapshot.canonicalJSON != canonicalJSONContent ||
            snapshot.notes != notes
        let shouldRemainDirty = isDirty || changed

        applySnapshot(snapshot, fileURL: fileURL, markDirty: shouldRemainDirty, resetRevision: false)

        if changed {
            contentRevision &+= 1
            isDirty = true
        }
        hasUnsyncedEditorChanges = false
        return changed
    }

    @discardableResult
    func syncFromEditor(html: String, plainText: String, words: Int, characters: Int) -> Bool {
        let changed = html != htmlContent || plainText != plainTextContent
        htmlContent = html
        plainTextContent = plainText
        wordCount = words
        characterCount = characters
        modifiedAt = Date()

        if changed {
            // A complete HTML snapshot is a safe persistence fallback if the
            // renderer becomes unavailable. Never pair it with older JSON.
            canonicalJSONContent = nil
            contentRevision &+= 1
            isDirty = true
        }
        hasUnsyncedEditorChanges = false
        return changed
    }

    func syncEditorMetrics(words: Int, characters: Int) {
        wordCount = max(0, words)
        characterCount = max(0, characters)
        markEditorMutation()
    }

    func markSaved(url: URL, request: PersistenceRequest) {
        guard request.generation == documentGeneration else { return }
        guard request.requestID >= lastCommittedPersistenceRequestID else { return }

        lastCommittedPersistenceRequestID = request.requestID
        if request.revision == contentRevision {
            applySnapshot(request.snapshot, fileURL: url, markDirty: false, resetRevision: false)
        } else {
            // A newer editor or notes mutation landed while this save was in flight.
            // Keep that in-memory state authoritative and let the next save persist it.
            fileURL = url
            isDirty = true
        }
        Self.addToRecentFiles(url)
    }

    func acknowledgePersonalizationOutcomes(_ actionIDs: [String]) {
        guard !actionIDs.isEmpty else { return }
        let acknowledged = Set(actionIDs)
        personalizationOutcomes.removeAll { acknowledged.contains($0.actionID) }
    }

    func load(snapshot: DocumentFileStore.FileSnapshot, from url: URL) {
        documentGeneration &+= 1
        applySnapshot(snapshot, fileURL: url, markDirty: false, resetRevision: true)
        Self.addToRecentFiles(url)
    }

    func recoverDraft(snapshot: DocumentFileStore.FileSnapshot, originalFileURL: URL?) {
        documentGeneration &+= 1
        applySnapshot(snapshot, fileURL: originalFileURL, markDirty: true, resetRevision: true)
        if let originalFileURL {
            Self.addToRecentFiles(originalFileURL)
        }
    }

    func restoreVersion(snapshot: DocumentFileStore.FileSnapshot) {
        let changed =
            snapshot.htmlContent != htmlContent ||
            snapshot.plainText != plainTextContent ||
            snapshot.canonicalJSON != canonicalJSONContent ||
            snapshot.notes != notes

        applySnapshot(snapshot, fileURL: fileURL, markDirty: true, resetRevision: false)

        if changed {
            contentRevision &+= 1
        }
        isDirty = true
    }

    func makePersistenceRequest(snapshot: DocumentFileStore.FileSnapshot? = nil) -> PersistenceRequest {
        nextPersistenceRequestID &+= 1
        return PersistenceRequest(
            requestID: nextPersistenceRequestID,
            generation: documentGeneration,
            revision: contentRevision,
            snapshot: snapshot ?? currentSnapshot()
        )
    }

    func currentSnapshot() -> DocumentFileStore.FileSnapshot {
        DocumentFileStore.FileSnapshot(
            canonicalJSON: canonicalJSONContent,
            htmlContent: htmlContent,
            plainText: plainTextContent,
            notes: notes,
            wordCount: wordCount,
            characterCount: characterCount,
            documentID: documentID,
            schemaVersion: schemaVersion,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            personalizationOutcomes: personalizationOutcomes
        )
    }

    private func applySnapshot(
        _ snapshot: DocumentFileStore.FileSnapshot,
        fileURL: URL?,
        markDirty: Bool,
        resetRevision: Bool
    ) {
        canonicalJSONContent = snapshot.canonicalJSON
        htmlContent = snapshot.htmlContent
        plainTextContent = snapshot.plainText
        notes = snapshot.notes
        self.fileURL = fileURL
        wordCount = snapshot.wordCount
        characterCount = snapshot.characterCount
        personalizationOutcomes = snapshot.personalizationOutcomes
        documentID = snapshot.documentID
        schemaVersion = snapshot.schemaVersion
        createdAt = snapshot.createdAt
        modifiedAt = snapshot.modifiedAt
        isDirty = markDirty

        if resetRevision {
            contentRevision = 0
        }
        hasUnsyncedEditorChanges = false
    }

    // MARK: - Recent Files

    static func addToRecentFiles(_ url: URL) {
        var bookmarks = UserDefaults.standard.array(forKey: recentFilesKey) as? [Data] ?? []

        if let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            let resolvedURLs = bookmarks.compactMap { data -> (Data, URL)? in
                var stale = false
                guard let resolved = try? URL(
                    resolvingBookmarkData: data,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                ) else {
                    return nil
                }
                return (data, resolved)
            }
            bookmarks = resolvedURLs.filter { $0.1 != url }.map { $0.0 }
            bookmarks.insert(bookmark, at: 0)

            if bookmarks.count > maxRecentFiles {
                bookmarks = Array(bookmarks.prefix(maxRecentFiles))
            }

            UserDefaults.standard.set(bookmarks, forKey: recentFilesKey)
        }
    }

    private static func replaceRecentFile(_ sourceURL: URL, with destinationURL: URL) {
        var bookmarks = UserDefaults.standard.array(forKey: recentFilesKey) as? [Data] ?? []
        bookmarks = bookmarks.filter { data in
            var stale = false
            guard let resolved = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else {
                return false
            }
            return resolved != sourceURL && resolved != destinationURL
        }

        if let bookmark = try? destinationURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            bookmarks.insert(bookmark, at: 0)
        }
        if bookmarks.count > maxRecentFiles {
            bookmarks = Array(bookmarks.prefix(maxRecentFiles))
        }
        UserDefaults.standard.set(bookmarks, forKey: recentFilesKey)
    }

    static func recentFiles() -> [(url: URL, name: String)] {
        let bookmarks = UserDefaults.standard.array(forKey: recentFilesKey) as? [Data] ?? []
        return bookmarks.compactMap { data in
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else {
                return nil
            }
            let name = url.deletingPathExtension().lastPathComponent
            return (url: url, name: name)
        }
    }

    static func clearRecentFiles() {
        UserDefaults.standard.removeObject(forKey: recentFilesKey)
    }
}
