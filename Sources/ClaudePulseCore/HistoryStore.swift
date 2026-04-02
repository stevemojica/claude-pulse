import Foundation
import SQLite3

public struct UsageSnapshot: Sendable {
    public let timestamp: Date
    public let fiveHourPct: Double?
    public let sevenDayPct: Double?
    public let sonnetPct: Double?
    public let opusPct: Double?
    public let extraUsed: Double?
    public let extraLimit: Double?

    public func percentage(for window: String) -> Double? {
        switch window {
        case "five_hour": return fiveHourPct
        case "seven_day": return sevenDayPct
        case "sonnet":    return sonnetPct
        case "opus":      return opusPct
        default:          return nil
        }
    }
}

/// Thread-safe SQLite-backed usage history with persistent connection and WAL mode.
public final class HistoryStore: @unchecked Sendable {
    private let db: OpaquePointer
    private let lock = NSLock()
    private static let retentionDays = 30

    // SQLITE_TRANSIENT tells SQLite to copy the string immediately
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init() throws {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudePulse", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("history.sqlite3").path

        var handle: OpaquePointer?
        guard sqlite3_open(path, &handle) == SQLITE_OK, let handle else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let handle { sqlite3_close(handle) }
            throw StoreError.cannotOpen("\(path): \(msg)")
        }
        db = handle

        // Enable WAL for concurrent read/write safety
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)

        let sql = """
            CREATE TABLE IF NOT EXISTS usage_snapshots (
                id              INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp       TEXT NOT NULL,
                five_hour_pct   REAL,
                seven_day_pct   REAL,
                sonnet_pct      REAL,
                opus_pct        REAL,
                extra_used      REAL,
                extra_limit     REAL
            );
            CREATE INDEX IF NOT EXISTS idx_snapshots_time ON usage_snapshots(timestamp);
            """
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw StoreError.sqlError(String(cString: sqlite3_errmsg(db)))
        }
    }

    deinit {
        // sqlite3_close_v2 is more forgiving with uncommitted transactions
        sqlite3_close_v2(db)
    }

    public func record(_ usage: UsageResponse) throws {
        try locked {
            let sql = """
                INSERT INTO usage_snapshots
                    (timestamp, five_hour_pct, seven_day_pct, sonnet_pct, opus_pct, extra_used, extra_limit)
                VALUES (?, ?, ?, ?, ?, ?, ?);
                """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StoreError.sqlError(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }

            let now = ISO8601DateFormatter().string(from: Date())
            _ = now.withCString { ptr in
                sqlite3_bind_text(stmt, 1, ptr, -1, Self.sqliteTransient)
            }
            bindOptionalDouble(stmt, 2, usage.fiveHour?.utilization)
            bindOptionalDouble(stmt, 3, usage.sevenDay?.utilization)
            bindOptionalDouble(stmt, 4, usage.sevenDaySonnet?.utilization)
            bindOptionalDouble(stmt, 5, usage.sevenDayOpus?.utilization)
            bindOptionalDouble(stmt, 6, usage.extraUsage?.usedCredits)
            bindOptionalDouble(stmt, 7, usage.extraUsage?.monthlyLimit)

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw StoreError.sqlError(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    public func recentSnapshots(limit: Int = 10) throws -> [UsageSnapshot] {
        try locked {
            let sql = """
                SELECT timestamp, five_hour_pct, seven_day_pct, sonnet_pct, opus_pct, extra_used, extra_limit
                FROM usage_snapshots ORDER BY id DESC LIMIT ?;
                """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StoreError.sqlError(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int(stmt, 1, Int32(limit))

            let fmt = ISO8601DateFormatter()
            var rows: [UsageSnapshot] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let textPtr = sqlite3_column_text(stmt, 0) else { continue }
                let tsStr = String(cString: textPtr)
                let ts = fmt.date(from: tsStr) ?? Date()
                rows.append(UsageSnapshot(
                    timestamp: ts,
                    fiveHourPct: optionalDouble(stmt, 1),
                    sevenDayPct: optionalDouble(stmt, 2),
                    sonnetPct: optionalDouble(stmt, 3),
                    opusPct: optionalDouble(stmt, 4),
                    extraUsed: optionalDouble(stmt, 5),
                    extraLimit: optionalDouble(stmt, 6)
                ))
            }
            return rows.reversed()
        }
    }

    public func snapshotCount() throws -> Int {
        try locked {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM usage_snapshots;", -1, &stmt, nil) == SQLITE_OK else {
                throw StoreError.sqlError(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int(stmt, 0))
        }
    }

    /// Remove snapshots older than retention period.
    public func prune() throws {
        try locked {
            let cutoff = Calendar.current.date(byAdding: .day, value: -Self.retentionDays, to: Date())!
            let cutoffStr = ISO8601DateFormatter().string(from: cutoff)
            let sql = "DELETE FROM usage_snapshots WHERE timestamp < ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StoreError.sqlError(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }
            _ = cutoffStr.withCString { ptr in
                sqlite3_bind_text(stmt, 1, ptr, -1, Self.sqliteTransient)
            }
            sqlite3_step(stmt)
        }
    }

    // MARK: - Helpers

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private func bindOptionalDouble(_ stmt: OpaquePointer?, _ idx: Int32, _ val: Double?) {
        if let val { sqlite3_bind_double(stmt, idx, val) }
        else { sqlite3_bind_null(stmt, idx) }
    }

    private func optionalDouble(_ stmt: OpaquePointer?, _ idx: Int32) -> Double? {
        sqlite3_column_type(stmt, idx) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, idx)
    }

    public enum StoreError: Error, CustomStringConvertible {
        case cannotOpen(String)
        case sqlError(String)
        public var description: String {
            switch self {
            case .cannotOpen(let p): "Cannot open database at \(p)"
            case .sqlError(let msg): "SQLite error: \(msg)"
            }
        }
    }
}
