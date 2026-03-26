import Foundation
import SQLite3

/// Stores document version snapshots in a SQLite database.
/// Location: ~/Library/Application Support/Shakespeare/versions.sqlite
/// All SQLite access is serialized through a private dispatch queue to avoid
/// blocking the main thread.
final class VersionStore: @unchecked Sendable {
    static let shared = VersionStore()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.shakespeare.versionstore")

    struct Version: Identifiable {
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
    }

    private init() {
        queue.sync {
            openDatabase()
            createTable()
        }
        queue.async { [self] in
            pruneOldVersions()
        }
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    // MARK: - Database Setup

    private func openDatabase() {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            print("VersionStore: could not locate Application Support directory")
            return
        }
        let dir = appSupport.appendingPathComponent("Shakespeare")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbPath = dir.appendingPathComponent("versions.sqlite").path

        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("VersionStore: failed to open database at \(dbPath)")
            db = nil
        }
    }

    private func createTable() {
        let sql = """
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
        CREATE INDEX IF NOT EXISTS idx_versions_file_path ON versions(file_path);
        CREATE INDEX IF NOT EXISTS idx_versions_created_at ON versions(created_at);
        """
        sqlite3_exec(db, sql, nil, nil, nil)

        addColumnIfNeeded(name: "document_id", definition: "TEXT")
        addColumnIfNeeded(name: "json_content", definition: "TEXT")
        addColumnIfNeeded(name: "plain_text", definition: "TEXT NOT NULL DEFAULT ''")
        addColumnIfNeeded(name: "character_count", definition: "INTEGER DEFAULT 0")
    }

    private func addColumnIfNeeded(name: String, definition: String) {
        guard !columnExists(name: name) else { return }
        let sql = "ALTER TABLE versions ADD COLUMN \(name) \(definition)"
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func columnExists(name: String) -> Bool {
        guard let db else { return false }

        let sql = "PRAGMA table_info(versions)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            if let columnName = sqlite3_column_text(stmt, 1),
               String(cString: columnName) == name {
                return true
            }
        }
        return false
    }

    // MARK: - Save Version

    func saveVersion(filePath: String, snapshot: DocumentFileStore.FileSnapshot, name: String? = nil) {
        queue.async { [self] in
            guard let db else { return }

            if let latest = _latestVersion(forFile: filePath),
               isDuplicate(latest: latest, snapshot: snapshot) {
                return
            }

            let sql = """
            INSERT INTO versions (
                file_path,
                document_id,
                version_name,
                json_content,
                html_content,
                plain_text,
                word_count,
                character_count,
                created_at,
                is_named
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (filePath as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (snapshot.documentID as NSString).utf8String, -1, nil)
            if let name {
                sqlite3_bind_text(stmt, 3, (name as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            if let canonicalJSON = snapshot.canonicalJSON {
                sqlite3_bind_text(stmt, 4, (canonicalJSON as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 4)
            }
            sqlite3_bind_text(stmt, 5, (snapshot.htmlContent as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 6, (snapshot.plainText as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 7, Int32(snapshot.wordCount))
            sqlite3_bind_int(stmt, 8, Int32(snapshot.characterCount))
            sqlite3_bind_double(stmt, 9, Date().timeIntervalSince1970)
            sqlite3_bind_int(stmt, 10, name != nil ? 1 : 0)

            sqlite3_step(stmt)
        }
    }

    private func isDuplicate(latest: Version, snapshot: DocumentFileStore.FileSnapshot) -> Bool {
        if let latestJSON = latest.canonicalJSON,
           let snapshotJSON = snapshot.canonicalJSON {
            return latestJSON == snapshotJSON
        }
        return latest.htmlContent == snapshot.htmlContent
    }

    // MARK: - Query Versions

    func versions(forFile filePath: String) -> [Version] {
        queue.sync { [self] in
            guard let db else { return [] }

            let sql = """
            SELECT
                id,
                file_path,
                document_id,
                version_name,
                json_content,
                html_content,
                plain_text,
                word_count,
                character_count,
                created_at,
                is_named
            FROM versions
            WHERE file_path = ?
            ORDER BY created_at DESC
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (filePath as NSString).utf8String, -1, nil)

            var results: [Version] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(versionFromStatement(stmt))
            }
            return results
        }
    }

    func latestVersion(forFile filePath: String) -> Version? {
        queue.sync { [self] in _latestVersion(forFile: filePath) }
    }

    private func _latestVersion(forFile filePath: String) -> Version? {
        guard let db else { return nil }

        let sql = """
        SELECT
            id,
            file_path,
            document_id,
            version_name,
            json_content,
            html_content,
            plain_text,
            word_count,
            character_count,
            created_at,
            is_named
        FROM versions
        WHERE file_path = ?
        ORDER BY created_at DESC
        LIMIT 1
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (filePath as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) == SQLITE_ROW {
            return versionFromStatement(stmt)
        }
        return nil
    }

    func version(id: Int64) -> Version? {
        queue.sync { [self] in
            guard let db else { return nil }

            let sql = """
            SELECT
                id,
                file_path,
                document_id,
                version_name,
                json_content,
                html_content,
                plain_text,
                word_count,
                character_count,
                created_at,
                is_named
            FROM versions
            WHERE id = ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int64(stmt, 1, id)

            if sqlite3_step(stmt) == SQLITE_ROW {
                return versionFromStatement(stmt)
            }
            return nil
        }
    }

    // MARK: - Name / Rename

    func nameVersion(id: Int64, name: String?) {
        queue.async { [self] in
            guard let db else { return }

            let sql = "UPDATE versions SET version_name = ?, is_named = ? WHERE id = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            if let name {
                sqlite3_bind_text(stmt, 1, (name as NSString).utf8String, -1, nil)
                sqlite3_bind_int(stmt, 2, 1)
            } else {
                sqlite3_bind_null(stmt, 1)
                sqlite3_bind_int(stmt, 2, 0)
            }
            sqlite3_bind_int64(stmt, 3, id)

            sqlite3_step(stmt)
        }
    }

    // MARK: - Delete

    func deleteVersion(id: Int64) {
        queue.async { [self] in
            guard let db else { return }

            let sql = "DELETE FROM versions WHERE id = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int64(stmt, 1, id)
            sqlite3_step(stmt)
        }
    }

    // MARK: - Pruning

    private func pruneOldVersions() {
        guard let db else { return }

        let now = Date().timeIntervalSince1970
        let oneDayAgo = now - 86400
        let thirtyDaysAgo = now - 86400 * 30

        let sql = """
        SELECT id, file_path, created_at FROM versions
        WHERE is_named = 0 AND created_at < ?
        ORDER BY file_path, created_at DESC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, oneDayAgo)

        var toDelete: [Int64] = []
        var currentFile = ""
        var keptDays: Set<String> = []
        var keptWeeks: Set<String> = []

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"

        let weekFormatter = DateFormatter()
        weekFormatter.dateFormat = "yyyy-'W'ww"

        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let filePath = stringValue(stmt, column: 1) ?? ""
            let createdAt = sqlite3_column_double(stmt, 2)
            let date = Date(timeIntervalSince1970: createdAt)

            if filePath != currentFile {
                currentFile = filePath
                keptDays = []
                keptWeeks = []
            }

            if createdAt > thirtyDaysAgo {
                let dayKey = dayFormatter.string(from: date)
                if keptDays.contains(dayKey) {
                    toDelete.append(id)
                } else {
                    keptDays.insert(dayKey)
                }
            } else {
                let weekKey = weekFormatter.string(from: date)
                if keptWeeks.contains(weekKey) {
                    toDelete.append(id)
                } else {
                    keptWeeks.insert(weekKey)
                }
            }
        }

        if !toDelete.isEmpty {
            let ids = toDelete.map(String.init).joined(separator: ",")
            let deleteSQL = "DELETE FROM versions WHERE id IN (\(ids))"
            sqlite3_exec(db, deleteSQL, nil, nil, nil)
        }
    }

    // MARK: - Helpers

    private func versionFromStatement(_ stmt: OpaquePointer?) -> Version {
        let id = sqlite3_column_int64(stmt, 0)
        let filePath = stringValue(stmt, column: 1) ?? ""
        let documentID = stringValue(stmt, column: 2)
        let versionName = stringValue(stmt, column: 3)
        let canonicalJSON = stringValue(stmt, column: 4)
        let htmlContent = stringValue(stmt, column: 5) ?? ""
        let plainText = stringValue(stmt, column: 6) ?? ""
        let wordCount = Int(sqlite3_column_int(stmt, 7))
        let characterCount = Int(sqlite3_column_int(stmt, 8))
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 9))
        let isNamed = sqlite3_column_int(stmt, 10) != 0

        return Version(
            id: id,
            filePath: filePath,
            documentID: documentID,
            versionName: versionName,
            canonicalJSON: canonicalJSON,
            htmlContent: htmlContent,
            plainText: plainText,
            wordCount: wordCount,
            characterCount: characterCount,
            createdAt: createdAt,
            isNamed: isNamed
        )
    }

    private func stringValue(_ stmt: OpaquePointer?, column: Int32) -> String? {
        guard sqlite3_column_type(stmt, column) != SQLITE_NULL,
              let cString = sqlite3_column_text(stmt, column)
        else {
            return nil
        }
        return String(cString: cString)
    }
}
