import Foundation
import SQLite3

/// Thin SQLite wrapper. All access happens on the main thread (the poll timer
/// fires there), so no locking is needed for v1. One row per focus session;
/// `end_ts` is updated in place as the session extends.
final class Database {
    private var db: OpaquePointer?

    // SQLite wants to know whether it can keep a borrowed string pointer.
    // TRANSIENT tells it to copy, which is correct for Swift String bridging.
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Opens (or creates) the database at the standard app-support location.
    static func standardLocation() -> String {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("scattrd", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = dir.appendingPathComponent("focus.sqlite")

        // One-time migration from the old FocusTracker location so history survives the rename.
        let old = base.appendingPathComponent("FocusTracker", isDirectory: true)
            .appendingPathComponent("focus.sqlite")
        if !fm.fileExists(atPath: db.path) && fm.fileExists(atPath: old.path) {
            try? fm.copyItem(at: old, to: db)
        }
        return db.path
    }

    init(path: String) {
        if sqlite3_open(path, &db) != SQLITE_OK {
            fatalError("scattrd: cannot open database at \(path)")
        }
        createTables()
    }

    deinit { sqlite3_close(db) }

    private func createTables() {
        exec("""
        CREATE TABLE IF NOT EXISTS sessions (
            id        INTEGER PRIMARY KEY AUTOINCREMENT,
            app       TEXT NOT NULL,
            bundle_id TEXT,
            category  INTEGER NOT NULL,
            start_ts  REAL NOT NULL,
            end_ts    REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_sessions_start ON sessions(start_ts);
        """)
    }

    private func exec(_ sql: String) {
        var err: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            FileHandle.standardError.write(Data("FocusTracker SQL error: \(msg)\n".utf8))
            sqlite3_free(err)
        }
    }

    /// Inserts a new session and returns its row id.
    @discardableResult
    func startSession(app: String, bundleId: String?, category: Int, start: Double) -> Int64 {
        let sql = "INSERT INTO sessions (app, bundle_id, category, start_ts, end_ts) VALUES (?, ?, ?, ?, ?);"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return -1 }
        sqlite3_bind_text(stmt, 1, app, -1, SQLITE_TRANSIENT)
        if let bundleId {
            sqlite3_bind_text(stmt, 2, bundleId, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 2)
        }
        sqlite3_bind_int(stmt, 3, Int32(category))
        sqlite3_bind_double(stmt, 4, start)
        sqlite3_bind_double(stmt, 5, start)
        guard sqlite3_step(stmt) == SQLITE_DONE else { return -1 }
        return sqlite3_last_insert_rowid(db)
    }

    /// Extends an existing session's end timestamp.
    func updateSessionEnd(id: Int64, end: Double) {
        let sql = "UPDATE sessions SET end_ts = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_double(stmt, 1, end)
        sqlite3_bind_int64(stmt, 2, id)
        sqlite3_step(stmt)
    }

    /// All sessions that started within [from, to), in chronological order.
    func sessions(from: Double, to: Double) -> [FocusSession] {
        let sql = """
        SELECT app, bundle_id, category, start_ts, end_ts
        FROM sessions WHERE start_ts >= ? AND start_ts < ?
        ORDER BY start_ts ASC;
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_double(stmt, 1, from)
        sqlite3_bind_double(stmt, 2, to)

        var result: [FocusSession] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let app = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? "Unknown"
            let bundle = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
            let category = AppCategory(rawValue: Int(sqlite3_column_int(stmt, 2))) ?? .neutral
            let start = sqlite3_column_double(stmt, 3)
            let end = sqlite3_column_double(stmt, 4)
            result.append(FocusSession(app: app, bundleId: bundle, category: category, start: start, end: end))
        }
        return result
    }
}
