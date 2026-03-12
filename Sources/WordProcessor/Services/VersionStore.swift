import Foundation
import SQLite3

/// Stores document version snapshots in a SQLite database.
/// Location: ~/Library/Application Support/Shakespeare/versions.sqlite
/// All SQLite access is serialized through a private dispatch queue to avoid
/// blocking the main thread (previously @MainActor, which caused UI hangs
/// during pruneOldVersions and saveVersion).
final class VersionStore: @unchecked Sendable {
    static let shared = VersionStore()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.shakespeare.versionstore")

    struct Version: Identifiable {
        let id: Int64
        let filePath: String
        let versionName: String?
        let htmlContent: String
        let wordCount: Int
        let createdAt: Date
        let isNamed: Bool
    }

    private init() {
        queue.sync {
            openDatabase()
            createTable()
        }
        // Prune old unnamed versions asynchronously — don't block launch
        queue.async { [self] in
            pruneOldVersions()
        }
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    // MARK: - Database Setup

    /// Must be called on `queue`.
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
            version_name TEXT,
            html_content TEXT NOT NULL,
            word_count INTEGER DEFAULT 0,
            created_at REAL NOT NULL,
            is_named INTEGER DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_versions_file_path ON versions(file_path);
        CREATE INDEX IF NOT EXISTS idx_versions_created_at ON versions(created_at);
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    // MARK: - Save Version

    /// Save a snapshot of the document. Called automatically on manual save.
    /// Runs on a background queue to avoid blocking the UI.
    func saveVersion(filePath: String, htmlContent: String, wordCount: Int, name: String? = nil) {
        queue.async { [self] in
            guard let db = db else { return }

            // Skip if content is identical to the most recent version for this file
            if let latest = _latestVersion(forFile: filePath),
               latest.htmlContent == htmlContent {
                return
            }

            let sql = "INSERT INTO versions (file_path, version_name, html_content, word_count, created_at, is_named) VALUES (?, ?, ?, ?, ?, ?)"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (filePath as NSString).utf8String, -1, nil)
            if let name = name {
                sqlite3_bind_text(stmt, 2, (name as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 2)
            }
            sqlite3_bind_text(stmt, 3, (htmlContent as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 4, Int32(wordCount))
            sqlite3_bind_double(stmt, 5, Date().timeIntervalSince1970)
            sqlite3_bind_int(stmt, 6, name != nil ? 1 : 0)

            sqlite3_step(stmt)
        }
    }

    // MARK: - Query Versions

    /// Get all versions for a file, newest first.
    func versions(forFile filePath: String) -> [Version] {
        queue.sync { [self] in
            guard let db = db else { return [] }

            let sql = "SELECT id, file_path, version_name, html_content, word_count, created_at, is_named FROM versions WHERE file_path = ? ORDER BY created_at DESC"
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

    /// Get the most recent version for a file.
    func latestVersion(forFile filePath: String) -> Version? {
        queue.sync { [self] in _latestVersion(forFile: filePath) }
    }

    /// Internal version — must be called on `queue`.
    private func _latestVersion(forFile filePath: String) -> Version? {
        guard let db = db else { return nil }

        let sql = "SELECT id, file_path, version_name, html_content, word_count, created_at, is_named FROM versions WHERE file_path = ? ORDER BY created_at DESC LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (filePath as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) == SQLITE_ROW {
            return versionFromStatement(stmt)
        }
        return nil
    }

    /// Get a single version by ID.
    func version(id: Int64) -> Version? {
        queue.sync { [self] in
            guard let db = db else { return nil }

            let sql = "SELECT id, file_path, version_name, html_content, word_count, created_at, is_named FROM versions WHERE id = ?"
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

    /// Name (or rename) a version. Setting name to nil removes the name.
    func nameVersion(id: Int64, name: String?) {
        queue.async { [self] in
            guard let db = db else { return }

            let sql = "UPDATE versions SET version_name = ?, is_named = ? WHERE id = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            if let name = name {
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
            guard let db = db else { return }

            let sql = "DELETE FROM versions WHERE id = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int64(stmt, 1, id)
            sqlite3_step(stmt)
        }
    }

    // MARK: - Pruning

    /// Keep all named versions forever. For unnamed versions:
    /// - Keep all from the last 24 hours
    /// - Keep one per day for the last 30 days
    /// - Keep one per week beyond 30 days
    /// Must be called on `queue`.
    private func pruneOldVersions() {
        guard let db = db else { return }

        let now = Date().timeIntervalSince1970
        let oneDayAgo = now - 86400
        let thirtyDaysAgo = now - 86400 * 30

        // Get all unnamed versions older than 24 hours, grouped by file
        let sql = """
        SELECT id, file_path, created_at FROM versions
        WHERE is_named = 0 AND created_at < ?
        ORDER BY file_path, created_at DESC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, oneDayAgo)

        // Group by file path and date bucket
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
            let filePath = String(cString: sqlite3_column_text(stmt, 1))
            let createdAt = sqlite3_column_double(stmt, 2)
            let date = Date(timeIntervalSince1970: createdAt)

            if filePath != currentFile {
                currentFile = filePath
                keptDays = []
                keptWeeks = []
            }

            if createdAt > thirtyDaysAgo {
                // Last 30 days: keep one per day
                let dayKey = dayFormatter.string(from: date)
                if keptDays.contains(dayKey) {
                    toDelete.append(id)
                } else {
                    keptDays.insert(dayKey)
                }
            } else {
                // Older than 30 days: keep one per week
                let weekKey = weekFormatter.string(from: date)
                if keptWeeks.contains(weekKey) {
                    toDelete.append(id)
                } else {
                    keptWeeks.insert(weekKey)
                }
            }
        }

        // Batch delete
        if !toDelete.isEmpty {
            let ids = toDelete.map(String.init).joined(separator: ",")
            let deleteSql = "DELETE FROM versions WHERE id IN (\(ids))"
            sqlite3_exec(db, deleteSql, nil, nil, nil)
        }
    }

    // MARK: - Helpers

    private func versionFromStatement(_ stmt: OpaquePointer?) -> Version {
        let id = sqlite3_column_int64(stmt, 0)
        let filePath = String(cString: sqlite3_column_text(stmt, 1))
        let versionName: String? = sqlite3_column_type(stmt, 2) != SQLITE_NULL
            ? String(cString: sqlite3_column_text(stmt, 2)) : nil
        let htmlContent = String(cString: sqlite3_column_text(stmt, 3))
        let wordCount = Int(sqlite3_column_int(stmt, 4))
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
        let isNamed = sqlite3_column_int(stmt, 6) != 0

        return Version(
            id: id,
            filePath: filePath,
            versionName: versionName,
            htmlContent: htmlContent,
            wordCount: wordCount,
            createdAt: createdAt,
            isNamed: isNamed
        )
    }
}
