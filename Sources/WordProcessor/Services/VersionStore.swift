import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Stores content-complete document snapshots in SQLite. Snapshot rows and
/// their content-addressed image references are committed in one transaction.
/// All database access is serialized away from the main thread.
final class VersionStore: @unchecked Sendable {
    static let shared = VersionStore(
        databaseURL: ShakespeareStorage.versionsDatabaseURL,
        preparesApplicationStorage: true
    )

    private static let maximumAutomaticHistoryBytes: Int64 = 512 * 1_024 * 1_024
    private static let maximumRecentAutomaticVersionsPerDocument = 60
    private static let oneDay: TimeInterval = 86_400

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.shakespeare.versionstore")
    private let databaseURL: URL
    private let preparesApplicationStorage: Bool

    enum StoreError: LocalizedError {
        case databaseUnavailable
        case sqlite(String)
        case corruptAsset(String)

        var errorDescription: String? {
            switch self {
            case .databaseUnavailable:
                return "Version history is unavailable."
            case .sqlite(let detail):
                return "Version history could not be updated (\(detail))."
            case .corruptAsset(let filename):
                return "A saved version contains an invalid image (\(filename))."
            }
        }
    }

    struct Version: Identifiable, Sendable {
        let id: Int64
        let filePath: String
        let documentID: String?
        let versionName: String?
        let canonicalJSON: String?
        let htmlContent: String
        let plainText: String
        let wordCount: Int
        let characterCount: Int
        let createdAt: Date
        let isNamed: Bool
        let assets: [String: Data]
    }

    struct VersionSummary: Identifiable, Sendable {
        let id: Int64
        let filePath: String
        let documentID: String?
        let versionName: String?
        let wordCount: Int
        let characterCount: Int
        let createdAt: Date
        let isNamed: Bool
    }

    private init(databaseURL: URL, preparesApplicationStorage: Bool) {
        self.databaseURL = databaseURL
        self.preparesApplicationStorage = preparesApplicationStorage
        queue.sync {
            do {
                try openDatabase()
                try createTables()
                try pruneOldVersions()
            } catch {
                print("VersionStore initialization failed: \(error.localizedDescription)")
                if let db {
                    sqlite3_close(db)
                    self.db = nil
                }
            }
        }
    }

    convenience init(testingDatabaseURL: URL) {
        self.init(databaseURL: testingDatabaseURL, preparesApplicationStorage: false)
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - Public operations

    func saveVersion(
        filePath: String,
        snapshot: DocumentFileStore.FileSnapshot,
        name: String? = nil,
        sourceDocumentURL: URL?
    ) async throws {
        let assets = try await DocumentFileStore.shared.versionAssets(
            for: snapshot,
            sourceDocumentURL: sourceDocumentURL
        )
        try await perform { [self] in
            try saveVersionRow(
                filePath: filePath,
                snapshot: snapshot,
                name: name,
                assets: assets
            )
        }
    }

    func saveVersion(
        filePath: String,
        snapshot: DocumentFileStore.FileSnapshot,
        name: String? = nil,
        versionAssets: [String: Data]
    ) async throws {
        try await perform { [self] in
            try saveVersionRow(
                filePath: filePath,
                snapshot: snapshot,
                name: name,
                assets: versionAssets
            )
        }
    }

    func versionSummaries(
        forFile filePath: String,
        documentID: String?
    ) async throws -> [VersionSummary] {
        try await perform { [self] in
            try versionSummaries(forFile: filePath, documentID: documentID)
        }
    }

    func version(id: Int64) async throws -> Version? {
        try await perform { [self] in
            guard var version = try versionRow(id: id) else { return nil }
            let assets = try assets(forVersionID: id)
            var referencedAssets = DocumentAssetReference.filenames(in: version.htmlContent)
            if let canonicalJSON = version.canonicalJSON {
                referencedAssets.formUnion(
                    DocumentAssetReference.filenames(inCanonicalJSON: canonicalJSON)
                )
            }
            if referencedAssets != Set(assets.keys) {
                throw StoreError.corruptAsset(
                    referencedAssets.subtracting(assets.keys).sorted().first ?? "unexpected reference"
                )
            }
            version = Version(
                id: version.id,
                filePath: version.filePath,
                documentID: version.documentID,
                versionName: version.versionName,
                canonicalJSON: version.canonicalJSON,
                htmlContent: version.htmlContent,
                plainText: version.plainText,
                wordCount: version.wordCount,
                characterCount: version.characterCount,
                createdAt: version.createdAt,
                isNamed: version.isNamed,
                assets: assets
            )
            return version
        }
    }

    func nameVersion(id: Int64, name: String?) async throws {
        try await perform { [self] in try updateVersionName(id: id, name: name) }
    }

    func deleteVersion(id: Int64) async throws {
        try await perform { [self] in
            try transaction {
                let statement = try prepare("DELETE FROM versions WHERE id = ?")
                defer { sqlite3_finalize(statement) }
                try check(sqlite3_bind_int64(statement, 1, id))
                try stepDone(statement)
                try removeOrphanedAssets()
            }
        }
    }

    // MARK: - Setup

    private func openDatabase() throws {
        if preparesApplicationStorage {
            try ShakespeareStorage.prepare()
        }
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let path = databaseURL.path
        guard sqlite3_open_v2(
            path,
            &db,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK else {
            throw StoreError.sqlite("could not open \(path)")
        }
        sqlite3_busy_timeout(db, 5_000)
        try execute("PRAGMA foreign_keys=ON")
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=NORMAL")
    }

    private func createTables() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS versions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file_path TEXT NOT NULL,
            document_id TEXT,
            version_name TEXT,
            json_content TEXT,
            html_content TEXT NOT NULL DEFAULT '',
            plain_text TEXT NOT NULL DEFAULT '',
            word_count INTEGER DEFAULT 0,
            character_count INTEGER DEFAULT 0,
            created_at REAL NOT NULL,
            is_named INTEGER DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS version_assets (
            filename TEXT PRIMARY KEY,
            data BLOB NOT NULL,
            byte_count INTEGER NOT NULL CHECK(byte_count >= 0)
        );
        CREATE TABLE IF NOT EXISTS version_asset_refs (
            version_id INTEGER NOT NULL REFERENCES versions(id) ON DELETE CASCADE,
            filename TEXT NOT NULL REFERENCES version_assets(filename),
            PRIMARY KEY(version_id, filename)
        );
        CREATE INDEX IF NOT EXISTS idx_versions_file_path ON versions(file_path);
        CREATE INDEX IF NOT EXISTS idx_versions_created_at ON versions(created_at);
        CREATE INDEX IF NOT EXISTS idx_versions_file_created
            ON versions(file_path, created_at DESC);
        CREATE INDEX IF NOT EXISTS idx_versions_document_created
            ON versions(document_id, created_at DESC);
        CREATE INDEX IF NOT EXISTS idx_version_asset_refs_filename
            ON version_asset_refs(filename);
        """)

        try addColumnIfNeeded(name: "document_id", definition: "TEXT")
        try addColumnIfNeeded(name: "json_content", definition: "TEXT")
        try addColumnIfNeeded(name: "plain_text", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfNeeded(name: "character_count", definition: "INTEGER DEFAULT 0")
    }

    private func addColumnIfNeeded(name: String, definition: String) throws {
        guard try !columnExists(name: name) else { return }
        try execute("ALTER TABLE versions ADD COLUMN \(name) \(definition)")
    }

    private func columnExists(name: String) throws -> Bool {
        let statement = try prepare("PRAGMA table_info(versions)")
        defer { sqlite3_finalize(statement) }
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return false }
            try check(result, allowing: SQLITE_ROW)
            if stringValue(statement, column: 1) == name { return true }
        }
    }

    // MARK: - Save

    private func saveVersionRow(
        filePath: String,
        snapshot: DocumentFileStore.FileSnapshot,
        name: String?,
        assets: [String: Data]
    ) throws {
        if let latest = try latestVersion(forFile: filePath, documentID: snapshot.documentID),
           isDuplicate(latest: latest, snapshot: snapshot),
           try assetNames(forVersionID: latest.id) == Set(assets.keys) {
            if let name { try updateVersionName(id: latest.id, name: name) }
            return
        }

        try transaction {
            let statement = try prepare("""
            INSERT INTO versions (
                file_path, document_id, version_name, json_content, html_content,
                plain_text, word_count, character_count, created_at, is_named
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """)
            defer { sqlite3_finalize(statement) }

            try bind(filePath, to: statement, at: 1)
            try bind(snapshot.documentID, to: statement, at: 2)
            try bind(name, to: statement, at: 3)
            try bind(snapshot.canonicalJSON, to: statement, at: 4)
            // Canonical JSON is authoritative for new snapshots. HTML remains
            // populated only for legacy HTML documents.
            try bind(snapshot.canonicalJSON == nil ? snapshot.htmlContent : "", to: statement, at: 5)
            try bind(snapshot.plainText, to: statement, at: 6)
            try check(sqlite3_bind_int64(statement, 7, Int64(snapshot.wordCount)))
            try check(sqlite3_bind_int64(statement, 8, Int64(snapshot.characterCount)))
            try check(sqlite3_bind_double(statement, 9, Date().timeIntervalSince1970))
            try check(sqlite3_bind_int(statement, 10, name == nil ? 0 : 1))
            try stepDone(statement)

            let versionID = sqlite3_last_insert_rowid(try requireDatabase())
            for (filename, data) in assets.sorted(by: { $0.key < $1.key }) {
                try insertAsset(filename: filename, data: data)
                try insertAssetReference(versionID: versionID, filename: filename)
            }
        }
        try pruneOldVersions()
    }

    private func insertAssetReference(versionID: Int64, filename: String) throws {
        let statement = try prepare(
            "INSERT INTO version_asset_refs (version_id, filename) VALUES (?, ?)"
        )
        defer { sqlite3_finalize(statement) }
        try check(sqlite3_bind_int64(statement, 1, versionID))
        try bind(filename, to: statement, at: 2)
        try stepDone(statement)
    }

    private func insertAsset(filename: String, data: Data) throws {
        let statement = try prepare("""
        INSERT INTO version_assets (filename, data, byte_count)
        VALUES (?, ?, ?)
        ON CONFLICT(filename) DO NOTHING
        """)
        defer { sqlite3_finalize(statement) }
        try bind(filename, to: statement, at: 1)
        try bind(data, to: statement, at: 2)
        try check(sqlite3_bind_int64(statement, 3, Int64(data.count)))
        try stepDone(statement)

        let verification = try prepare(
            "SELECT byte_count FROM version_assets WHERE filename = ?"
        )
        defer { sqlite3_finalize(verification) }
        try bind(filename, to: verification, at: 1)
        try check(sqlite3_step(verification), allowing: SQLITE_ROW)
        guard sqlite3_column_int64(verification, 0) == Int64(data.count) else {
            throw StoreError.corruptAsset(filename)
        }
    }

    private func isDuplicate(
        latest: Version,
        snapshot: DocumentFileStore.FileSnapshot
    ) -> Bool {
        if let latestJSON = latest.canonicalJSON,
           let snapshotJSON = snapshot.canonicalJSON {
            return latestJSON == snapshotJSON
        }
        return latest.htmlContent == snapshot.htmlContent
    }

    // MARK: - Query

    private func versionSummaries(
        forFile filePath: String,
        documentID: String?
    ) throws -> [VersionSummary] {
        let hasDocumentID = documentID?.isEmpty == false
        let whereClause = hasDocumentID
            ? "WHERE document_id = ? OR (document_id IS NULL AND file_path = ?)"
            : "WHERE file_path = ?"
        let statement = try prepare("""
        SELECT id, file_path, document_id, version_name, word_count,
               character_count, created_at, is_named
        FROM versions
        \(whereClause)
        ORDER BY created_at DESC
        """)
        defer { sqlite3_finalize(statement) }
        try bindDocumentLookup(
            statement,
            filePath: filePath,
            documentID: documentID,
            hasDocumentID: hasDocumentID
        )

        var results: [VersionSummary] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return results }
            try check(result, allowing: SQLITE_ROW)
            results.append(versionSummary(from: statement))
        }
    }

    private func latestVersion(
        forFile filePath: String,
        documentID: String?
    ) throws -> Version? {
        let hasDocumentID = documentID?.isEmpty == false
        let whereClause = hasDocumentID
            ? "WHERE document_id = ? OR (document_id IS NULL AND file_path = ?)"
            : "WHERE file_path = ?"
        let statement = try prepare("""
        SELECT id, file_path, document_id, version_name, json_content,
               html_content, plain_text, word_count, character_count,
               created_at, is_named
        FROM versions
        \(whereClause)
        ORDER BY created_at DESC
        LIMIT 1
        """)
        defer { sqlite3_finalize(statement) }
        try bindDocumentLookup(
            statement,
            filePath: filePath,
            documentID: documentID,
            hasDocumentID: hasDocumentID
        )
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        try check(result, allowing: SQLITE_ROW)
        return version(from: statement, assets: [:])
    }

    private func versionRow(id: Int64) throws -> Version? {
        let statement = try prepare("""
        SELECT id, file_path, document_id, version_name, json_content,
               html_content, plain_text, word_count, character_count,
               created_at, is_named
        FROM versions WHERE id = ?
        """)
        defer { sqlite3_finalize(statement) }
        try check(sqlite3_bind_int64(statement, 1, id))
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        try check(result, allowing: SQLITE_ROW)
        return version(from: statement, assets: [:])
    }

    private func assets(forVersionID id: Int64) throws -> [String: Data] {
        let statement = try prepare("""
        SELECT a.filename, a.data, a.byte_count
        FROM version_asset_refs r
        JOIN version_assets a ON a.filename = r.filename
        WHERE r.version_id = ?
        ORDER BY a.filename
        """)
        defer { sqlite3_finalize(statement) }
        try check(sqlite3_bind_int64(statement, 1, id))
        var assets: [String: Data] = [:]
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return assets }
            try check(result, allowing: SQLITE_ROW)
            guard let filename = stringValue(statement, column: 0) else {
                throw StoreError.sqlite("asset filename is missing")
            }
            let count = Int(sqlite3_column_bytes(statement, 1))
            let expectedCount = Int(sqlite3_column_int64(statement, 2))
            guard count == expectedCount else { throw StoreError.corruptAsset(filename) }
            let data: Data
            if count == 0 {
                data = Data()
            } else {
                guard let bytes = sqlite3_column_blob(statement, 1) else {
                    throw StoreError.corruptAsset(filename)
                }
                data = Data(bytes: bytes, count: count)
            }
            assets[filename] = data
        }
    }

    private func assetNames(forVersionID id: Int64) throws -> Set<String> {
        let statement = try prepare(
            "SELECT filename FROM version_asset_refs WHERE version_id = ?"
        )
        defer { sqlite3_finalize(statement) }
        try check(sqlite3_bind_int64(statement, 1, id))
        var names: Set<String> = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return names }
            try check(result, allowing: SQLITE_ROW)
            if let name = stringValue(statement, column: 0) { names.insert(name) }
        }
    }

    // MARK: - Mutations and retention

    private func updateVersionName(id: Int64, name: String?) throws {
        let statement = try prepare(
            "UPDATE versions SET version_name = ?, is_named = ? WHERE id = ?"
        )
        defer { sqlite3_finalize(statement) }
        try bind(name, to: statement, at: 1)
        try check(sqlite3_bind_int(statement, 2, name == nil ? 0 : 1))
        try check(sqlite3_bind_int64(statement, 3, id))
        try stepDone(statement)
        guard sqlite3_changes(try requireDatabase()) == 1 else {
            throw StoreError.sqlite("the selected version no longer exists")
        }
    }

    private func pruneOldVersions() throws {
        let now = Date().timeIntervalSince1970
        let oneDayAgo = now - Self.oneDay
        let thirtyDaysAgo = now - (Self.oneDay * 30)
        let oneYearAgo = now - (Self.oneDay * 365)
        let statement = try prepare("""
        SELECT id, COALESCE(NULLIF(document_id, ''), file_path), created_at
        FROM versions
        WHERE is_named = 0
        ORDER BY COALESCE(NULLIF(document_id, ''), file_path), created_at DESC
        """)
        defer { sqlite3_finalize(statement) }

        var toDelete: [Int64] = []
        var currentDocument = ""
        var recentCount = 0
        var keptDays: Set<String> = []
        var keptWeeks: Set<String> = []
        let calendar = Calendar(identifier: .gregorian)

        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            try check(result, allowing: SQLITE_ROW)
            let id = sqlite3_column_int64(statement, 0)
            let document = stringValue(statement, column: 1) ?? ""
            let timestamp = sqlite3_column_double(statement, 2)
            if document != currentDocument {
                currentDocument = document
                recentCount = 0
                keptDays.removeAll(keepingCapacity: true)
                keptWeeks.removeAll(keepingCapacity: true)
            }

            let date = Date(timeIntervalSince1970: timestamp)
            if timestamp >= oneDayAgo {
                recentCount += 1
                if recentCount > Self.maximumRecentAutomaticVersionsPerDocument {
                    toDelete.append(id)
                }
            } else if timestamp >= thirtyDaysAgo {
                let parts = calendar.dateComponents([.year, .month, .day], from: date)
                let key = "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
                if !keptDays.insert(key).inserted { toDelete.append(id) }
            } else if timestamp >= oneYearAgo {
                let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
                let key = "\(parts.yearForWeekOfYear ?? 0)-\(parts.weekOfYear ?? 0)"
                if !keptWeeks.insert(key).inserted { toDelete.append(id) }
            } else {
                toDelete.append(id)
            }
        }

        try transaction {
            for id in toDelete { try deleteVersionRow(id: id) }
            try removeOrphanedAssets()
        }
        try enforceStorageLimit()
    }

    private func enforceStorageLimit() throws {
        while try historyByteCount() > Self.maximumAutomaticHistoryBytes {
            guard let id = try oldestAutomaticVersionID() else { return }
            try transaction {
                try deleteVersionRow(id: id)
                try removeOrphanedAssets()
            }
        }
    }

    private func oldestAutomaticVersionID() throws -> Int64? {
        let statement = try prepare("""
        SELECT id FROM versions
        WHERE is_named = 0
        ORDER BY created_at ASC
        LIMIT 1
        """)
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        try check(result, allowing: SQLITE_ROW)
        return sqlite3_column_int64(statement, 0)
    }

    private func historyByteCount() throws -> Int64 {
        let statement = try prepare("""
        SELECT
            COALESCE((SELECT SUM(
                LENGTH(file_path) + LENGTH(COALESCE(document_id, '')) +
                LENGTH(COALESCE(version_name, '')) + LENGTH(COALESCE(json_content, '')) +
                LENGTH(html_content) + LENGTH(plain_text)
            ) FROM versions), 0) +
            COALESCE((SELECT SUM(byte_count) FROM version_assets), 0)
        """)
        defer { sqlite3_finalize(statement) }
        try check(sqlite3_step(statement), allowing: SQLITE_ROW)
        return sqlite3_column_int64(statement, 0)
    }

    private func deleteVersionRow(id: Int64) throws {
        let statement = try prepare("DELETE FROM versions WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        try check(sqlite3_bind_int64(statement, 1, id))
        try stepDone(statement)
    }

    private func removeOrphanedAssets() throws {
        try execute("""
        DELETE FROM version_assets
        WHERE NOT EXISTS (
            SELECT 1 FROM version_asset_refs
            WHERE version_asset_refs.filename = version_assets.filename
        )
        """)
    }

    // MARK: - SQLite helpers

    private func perform<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try operation()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func requireDatabase() throws -> OpaquePointer {
        guard let db else { throw StoreError.databaseUnavailable }
        return db
    }

    private func execute(_ sql: String) throws {
        let db = try requireDatabase()
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(errorMessage)
            throw StoreError.sqlite(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        let db = try requireDatabase()
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw StoreError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        return statement
    }

    private func check(_ result: Int32, allowing allowed: Int32 = SQLITE_OK) throws {
        guard result == allowed else {
            let db = try requireDatabase()
            throw StoreError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func stepDone(_ statement: OpaquePointer?) throws {
        try check(sqlite3_step(statement), allowing: SQLITE_DONE)
    }

    private func bind(_ value: String?, to statement: OpaquePointer?, at index: Int32) throws {
        guard let value else {
            try check(sqlite3_bind_null(statement, index))
            return
        }
        let result = value.withCString {
            sqlite3_bind_text(statement, index, $0, -1, sqliteTransient)
        }
        try check(result)
    }

    private func bind(_ data: Data, to statement: OpaquePointer?, at index: Int32) throws {
        let result: Int32
        if data.isEmpty {
            result = sqlite3_bind_zeroblob(statement, index, 0)
        } else {
            result = data.withUnsafeBytes {
                sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), sqliteTransient)
            }
        }
        try check(result)
    }

    private func bindDocumentLookup(
        _ statement: OpaquePointer?,
        filePath: String,
        documentID: String?,
        hasDocumentID: Bool
    ) throws {
        if hasDocumentID {
            try bind(documentID, to: statement, at: 1)
            try bind(filePath, to: statement, at: 2)
        } else {
            try bind(filePath, to: statement, at: 1)
        }
    }

    private func version(from statement: OpaquePointer?, assets: [String: Data]) -> Version {
        Version(
            id: sqlite3_column_int64(statement, 0),
            filePath: stringValue(statement, column: 1) ?? "",
            documentID: stringValue(statement, column: 2),
            versionName: stringValue(statement, column: 3),
            canonicalJSON: stringValue(statement, column: 4),
            htmlContent: stringValue(statement, column: 5) ?? "",
            plainText: stringValue(statement, column: 6) ?? "",
            wordCount: Int(sqlite3_column_int64(statement, 7)),
            characterCount: Int(sqlite3_column_int64(statement, 8)),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 9)),
            isNamed: sqlite3_column_int(statement, 10) != 0,
            assets: assets
        )
    }

    private func versionSummary(from statement: OpaquePointer?) -> VersionSummary {
        VersionSummary(
            id: sqlite3_column_int64(statement, 0),
            filePath: stringValue(statement, column: 1) ?? "",
            documentID: stringValue(statement, column: 2),
            versionName: stringValue(statement, column: 3),
            wordCount: Int(sqlite3_column_int64(statement, 4)),
            characterCount: Int(sqlite3_column_int64(statement, 5)),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
            isNamed: sqlite3_column_int(statement, 7) != 0
        )
    }

    private func stringValue(_ statement: OpaquePointer?, column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: value)
    }
}
