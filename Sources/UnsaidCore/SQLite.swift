import Foundation
import SQLite3

public struct SQLiteError: Error, CustomStringConvertible {
    public let description: String
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A minimal SQLite connection: enough for Wispr's database (read-only) and Unsaid's own store.
final class SQLite {
    private var db: OpaquePointer?

    init(path: String, readOnly: Bool) throws {
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open"
            sqlite3_close(db)
            throw SQLiteError(description: "\(path): \(message)")
        }
        sqlite3_busy_timeout(db, 2000)
    }

    deinit { sqlite3_close(db) }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw error() }
    }

    /// Runs `sql` with `params` (String, Double, Int, Data or nil) and returns every row.
    @discardableResult
    func query(_ sql: String, _ params: [Any?] = []) throws -> [Row] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw error() }
        defer { sqlite3_finalize(stmt) }
        for (i, p) in params.enumerated() {
            let n = Int32(i + 1)
            switch p {
            case let s as String: sqlite3_bind_text(stmt, n, s, -1, SQLITE_TRANSIENT)
            case let d as Double: sqlite3_bind_double(stmt, n, d)
            case let v as Int: sqlite3_bind_int64(stmt, n, Int64(v))
            case let data as Data:
                _ = data.withUnsafeBytes { sqlite3_bind_blob(stmt, n, $0.baseAddress, Int32(data.count), SQLITE_TRANSIENT) }
            default: sqlite3_bind_null(stmt, n)
            }
        }
        var rows: [Row] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw error() }
            var values: [String: Any] = [:]
            for c in 0..<sqlite3_column_count(stmt) {
                let name = String(cString: sqlite3_column_name(stmt, c))
                switch sqlite3_column_type(stmt, c) {
                case SQLITE_INTEGER: values[name] = Int(sqlite3_column_int64(stmt, c))
                case SQLITE_FLOAT: values[name] = sqlite3_column_double(stmt, c)
                case SQLITE_TEXT: values[name] = String(cString: sqlite3_column_text(stmt, c))
                case SQLITE_BLOB:
                    let count = Int(sqlite3_column_bytes(stmt, c))
                    values[name] = count > 0 ? Data(bytes: sqlite3_column_blob(stmt, c), count: count) : Data()
                default: break
                }
            }
            rows.append(Row(values: values))
        }
        return rows
    }

    private func error() -> SQLiteError { SQLiteError(description: String(cString: sqlite3_errmsg(db))) }
}

struct Row {
    let values: [String: Any]
    func string(_ k: String) -> String? { values[k] as? String }
    func int(_ k: String) -> Int? { values[k] as? Int ?? (values[k] as? Double).map(Int.init) }
    func double(_ k: String) -> Double? { values[k] as? Double ?? (values[k] as? Int).map(Double.init) }
    func data(_ k: String) -> Data? { values[k] as? Data }
}
