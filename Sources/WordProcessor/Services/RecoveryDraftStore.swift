import Foundation

actor RecoveryDraftStore {
    static let shared = RecoveryDraftStore()

    struct DraftMetadata: Codable, Identifiable, Sendable, Equatable {
        let id: String
        let documentID: String
        let displayName: String
        let originalFilePath: String?
        let originalFileBookmark: Data?
        let isUntitled: Bool
        let createdAt: Date
        let updatedAt: Date
        let wordCount: Int
        let characterCount: Int
    }

    struct LoadedDraft: Sendable {
        let metadata: DraftMetadata
        let packageURL: URL
        let snapshot: DocumentFileStore.FileSnapshot
    }

    private let metadataExtension = "json"

    @discardableResult
    func saveDraft(
        snapshot: DocumentFileStore.FileSnapshot,
        assetSourceDocumentURL: URL?,
        originalDocumentURL: URL?,
        displayName: String
    ) async throws -> DraftMetadata {
        let directory = try draftsDirectory()
        let id = draftID(for: snapshot.documentID)
        let packageURL = packageURL(for: id, in: directory)
        let metadataURL = self.metadataURL(for: id, in: directory)

        let existingMetadata = try? readMetadata(from: metadataURL)
        let packageExistedBefore = FileManager.default.fileExists(atPath: packageURL.path)
        let persistedSnapshot = try await DocumentFileStore.shared.save(
            snapshot,
            to: packageURL,
            sourceDocumentURL: assetSourceDocumentURL
        )

        let bookmark = try? originalDocumentURL?.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let now = Date()
        let metadata = DraftMetadata(
            id: id,
            documentID: persistedSnapshot.documentID,
            displayName: displayName,
            originalFilePath: originalDocumentURL?.path,
            originalFileBookmark: bookmark ?? existingMetadata?.originalFileBookmark,
            isUntitled: originalDocumentURL == nil,
            createdAt: existingMetadata?.createdAt ?? now,
            updatedAt: now,
            wordCount: persistedSnapshot.wordCount,
            characterCount: persistedSnapshot.characterCount
        )

        do {
            try writeMetadata(metadata, to: metadataURL)
        } catch {
            // availableDrafts() only surfaces drafts with metadata, so a new
            // package without metadata would be invisible and never cleaned up.
            // For pre-existing drafts, keep the (newer) package — the old
            // metadata still points at it.
            if !packageExistedBefore, existingMetadata == nil {
                try? FileManager.default.removeItem(at: packageURL)
            }
            throw error
        }
        return metadata
    }

    func availableDrafts() throws -> [DraftMetadata] {
        let directory = try draftsDirectory()
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        let drafts = urls
            .filter { $0.pathExtension == metadataExtension }
            .compactMap { try? readMetadata(from: $0) }
            .filter { metadata in
                FileManager.default.fileExists(atPath: packageURL(for: metadata.id, in: directory).path)
            }

        return drafts.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.displayName < rhs.displayName
        }
    }

    func loadDraft(id: String) async throws -> LoadedDraft {
        let directory = try draftsDirectory()
        let metadata = try readMetadata(from: metadataURL(for: id, in: directory))
        let packageURL = packageURL(for: id, in: directory)
        let snapshot = try await DocumentFileStore.shared.load(from: packageURL)
        return LoadedDraft(metadata: metadata, packageURL: packageURL, snapshot: snapshot)
    }

    func deleteDraft(id: String) throws {
        let directory = try draftsDirectory()
        let fileManager = FileManager.default
        let packageURL = packageURL(for: id, in: directory)
        let metadataURL = metadataURL(for: id, in: directory)

        if fileManager.fileExists(atPath: packageURL.path) {
            try fileManager.removeItem(at: packageURL)
        }
        if fileManager.fileExists(atPath: metadataURL.path) {
            try fileManager.removeItem(at: metadataURL)
        }
    }

    func deleteDraft(documentID: String) throws {
        try deleteDraft(id: draftID(for: documentID))
    }

    func originalFileURL(for metadata: DraftMetadata) -> URL? {
        if let bookmark = metadata.originalFileBookmark {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                return url
            }
        }

        if let path = metadata.originalFilePath,
           FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        return nil
    }

    private func draftsDirectory() throws -> URL {
        try ShakespeareStorage.prepare()
        let directory = ShakespeareStorage.recoveryDraftsDirectoryURL
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return directory
    }

    private func draftID(for documentID: String) -> String {
        let sanitized = documentID.replacingOccurrences(
            of: "[^A-Za-z0-9_-]",
            with: "-",
            options: .regularExpression
        )
        return sanitized.isEmpty ? UUID().uuidString : sanitized
    }

    private func packageURL(for id: String, in directory: URL) -> URL {
        directory.appendingPathComponent("\(id).\(DocumentFileStore.documentPackageExtension)", isDirectory: true)
    }

    private func metadataURL(for id: String, in directory: URL) -> URL {
        directory.appendingPathComponent("\(id).\(metadataExtension)", isDirectory: false)
    }

    private func readMetadata(from url: URL) throws -> DraftMetadata {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try PackageFileSafety.readData(
            from: url,
            maximumBytes: 256 * 1_024,
            displayName: url.lastPathComponent
        )
        return try decoder.decode(DraftMetadata.self, from: data)
    }

    private func writeMetadata(_ metadata: DraftMetadata, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(metadata).write(to: url, options: .atomic)
    }
}
