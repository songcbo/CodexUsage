import AppKit
import Foundation
import SQLite3
import SwiftUI

private func sqliteTransientDestructor() -> sqlite3_destructor_type {
    unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

final class UsageDatabase {
    private let db: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() throws {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appendingPathComponent("CodexUsage", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("usage.sqlite").path

        var connection: OpaquePointer?
        guard sqlite3_open(path, &connection) == SQLITE_OK else {
            throw UsageError.database("Unable to open SQLite database")
        }
        db = connection
        try migrateDailyUsageSchema()
        try migrateSessionLedgerSchema()
    }

    deinit {
        sqlite3_close(db)
    }

    func upsert(usages: [DailyUsage], source: UsageSource) throws {
        let sql = """
        INSERT INTO daily_usage (
            day, source, input_tokens, cached_input_tokens, output_tokens, reasoning_output_tokens,
            total_tokens, runs, estimated_cost_usd, latest_rate_limits_json,
            latest_rate_limits_timestamp, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(day, source) DO UPDATE SET
            input_tokens = excluded.input_tokens,
            cached_input_tokens = excluded.cached_input_tokens,
            output_tokens = excluded.output_tokens,
            reasoning_output_tokens = excluded.reasoning_output_tokens,
            total_tokens = excluded.total_tokens,
            runs = excluded.runs,
            estimated_cost_usd = excluded.estimated_cost_usd,
            latest_rate_limits_json = excluded.latest_rate_limits_json,
            latest_rate_limits_timestamp = excluded.latest_rate_limits_timestamp,
            updated_at = excluded.updated_at;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw UsageError.database(lastError)
        }
        defer { sqlite3_finalize(statement) }

        for usage in usages {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_text(statement, 1, usage.day, -1, sqliteTransientDestructor())
            sqlite3_bind_text(statement, 2, source.rawValue, -1, sqliteTransientDestructor())
            sqlite3_bind_int64(statement, 3, usage.totals.inputTokens)
            sqlite3_bind_int64(statement, 4, usage.totals.cachedInputTokens)
            sqlite3_bind_int64(statement, 5, usage.totals.outputTokens)
            sqlite3_bind_int64(statement, 6, usage.totals.reasoningOutputTokens)
            sqlite3_bind_int64(statement, 7, usage.totals.totalTokens)
            sqlite3_bind_int64(statement, 8, usage.totals.runs)
            sqlite3_bind_double(statement, 9, usage.totals.estimatedCostUSD)
            if let snapshot = usage.latestRateLimit,
               let data = try? encoder.encode(snapshot),
               let json = String(data: data, encoding: .utf8) {
                sqlite3_bind_text(statement, 10, json, -1, sqliteTransientDestructor())
                sqlite3_bind_text(statement, 11, snapshot.timestamp, -1, sqliteTransientDestructor())
            } else {
                sqlite3_bind_null(statement, 10)
                sqlite3_bind_null(statement, 11)
            }
            sqlite3_bind_int64(statement, 12, usage.updatedAt)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw UsageError.database(lastError)
            }
        }
    }

    func replace(usages: [DailyUsage], source: UsageSource) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try deleteDailyUsage(source: source)
            try upsert(usages: usages, source: source)
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func deleteDailyUsage(source: UsageSource) throws {
        let sql = "DELETE FROM daily_usage WHERE source = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw UsageError.database(lastError)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, source.rawValue, -1, sqliteTransientDestructor())
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw UsageError.database(lastError)
        }
    }

    func fetchAllDailyUsage(includeArchived: Bool) throws -> [DailyUsage] {
        if try tableExists("usage_session_days"),
           try hasRows(in: "usage_session_days") {
            return try fetchAllSessionDailyUsage(includeArchived: includeArchived)
        }

        let sql = includeArchived ? """
        SELECT day, input_tokens, cached_input_tokens, output_tokens, reasoning_output_tokens,
               total_tokens, runs, estimated_cost_usd, latest_rate_limits_json, updated_at
        FROM daily_usage
        ORDER BY day ASC;
        """ : """
        SELECT day, input_tokens, cached_input_tokens, output_tokens, reasoning_output_tokens,
               total_tokens, runs, estimated_cost_usd, latest_rate_limits_json, updated_at
        FROM daily_usage
        WHERE source = 'active'
        ORDER BY day ASC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw UsageError.database(lastError)
        }
        defer { sqlite3_finalize(statement) }

        var usagesByDay: [String: DailyUsage] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let day = String(cString: sqlite3_column_text(statement, 0))
            let totals = UsageTotals(
                inputTokens: sqlite3_column_int64(statement, 1),
                cachedInputTokens: sqlite3_column_int64(statement, 2),
                outputTokens: sqlite3_column_int64(statement, 3),
                reasoningOutputTokens: sqlite3_column_int64(statement, 4),
                totalTokens: sqlite3_column_int64(statement, 5),
                runs: sqlite3_column_int64(statement, 6),
                estimatedCostUSD: sqlite3_column_double(statement, 7)
            )
            let snapshot: RateLimitSnapshot?
            if let raw = sqlite3_column_text(statement, 8) {
                let json = String(cString: raw)
                snapshot = try? decoder.decode(RateLimitSnapshot.self, from: Data(json.utf8))
            } else {
                snapshot = nil
            }
            let updatedAt = sqlite3_column_int64(statement, 9)
            var usage = usagesByDay[day] ?? DailyUsage(
                day: day,
                totals: UsageTotals(),
                latestRateLimit: nil,
                updatedAt: updatedAt
            )
            usage.totals.add(totals)
            if let snapshot, usage.latestRateLimit?.timestamp ?? "" < snapshot.timestamp {
                usage.latestRateLimit = snapshot
            }
            usage.updatedAt = max(usage.updatedAt, updatedAt)
            usagesByDay[day] = usage
        }
        return usagesByDay.values.sorted { $0.day < $1.day }
    }

    func reconcile(sessions: [UsageSessionScan], status: UsageSessionStatus, scannedDays: Set<String>?) throws {
        let now = Int64(Date().timeIntervalSince1970)
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            if scannedDays == nil {
                try markUnseenSessionsMissing(status: status, seenSessionKeys: Set(sessions.map(\.sessionKey)))
            }
            for session in sessions {
                try upsert(session: session, now: now)
                try replaceSessionDays(sessionKey: session.sessionKey, usages: session.usages, scannedDays: scannedDays)
            }
            try rebuildLegacyResiduals(scannedDays: scannedDays, now: now)
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func migrateDailyUsageSchema() throws {
        guard try tableExists("daily_usage") else {
            try createDailyUsageTable(named: "daily_usage")
            return
        }
        guard try !columnExists("source", in: "daily_usage") else {
            return
        }

        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try execute("ALTER TABLE daily_usage RENAME TO daily_usage_legacy;")
            try createDailyUsageTable(named: "daily_usage")
            try execute("""
            INSERT INTO daily_usage (
                day, source, input_tokens, cached_input_tokens, output_tokens, reasoning_output_tokens,
                total_tokens, runs, estimated_cost_usd, latest_rate_limits_json,
                latest_rate_limits_timestamp, updated_at
            )
            SELECT
                day, 'active', input_tokens, cached_input_tokens, output_tokens, reasoning_output_tokens,
                total_tokens, runs, estimated_cost_usd, latest_rate_limits_json,
                latest_rate_limits_timestamp, updated_at
            FROM daily_usage_legacy;
            """)
            try execute("DROP TABLE daily_usage_legacy;")
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func migrateSessionLedgerSchema() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS usage_sessions (
            session_key TEXT PRIMARY KEY NOT NULL,
            status TEXT NOT NULL,
            last_seen_source TEXT NOT NULL,
            last_seen_path TEXT NOT NULL,
            file_size INTEGER NOT NULL,
            file_mtime INTEGER NOT NULL,
            first_scanned_at INTEGER NOT NULL,
            last_scanned_at INTEGER NOT NULL
        );
        """)
        if try !columnExists("last_seen_source", in: "usage_sessions") {
            try execute("ALTER TABLE usage_sessions ADD COLUMN last_seen_source TEXT NOT NULL DEFAULT 'active';")
        }
        try execute("""
        CREATE TABLE IF NOT EXISTS usage_session_days (
            session_key TEXT NOT NULL,
            day TEXT NOT NULL,
            input_tokens INTEGER NOT NULL,
            cached_input_tokens INTEGER NOT NULL,
            output_tokens INTEGER NOT NULL,
            reasoning_output_tokens INTEGER NOT NULL,
            total_tokens INTEGER NOT NULL,
            runs INTEGER NOT NULL,
            estimated_cost_usd REAL NOT NULL,
            latest_rate_limits_json TEXT,
            latest_rate_limits_timestamp TEXT,
            updated_at INTEGER NOT NULL,
            PRIMARY KEY(session_key, day),
            FOREIGN KEY(session_key) REFERENCES usage_sessions(session_key) ON DELETE CASCADE
        );
        """)

        guard try !hasRows(in: "usage_sessions") else {
            return
        }
        try rebuildLegacyResiduals(scannedDays: nil, now: Int64(Date().timeIntervalSince1970))
    }

    private func fetchAllSessionDailyUsage(includeArchived: Bool) throws -> [DailyUsage] {
        let sql = includeArchived ? """
        SELECT d.day, d.input_tokens, d.cached_input_tokens, d.output_tokens, d.reasoning_output_tokens,
               d.total_tokens, d.runs, d.estimated_cost_usd, d.latest_rate_limits_json, d.updated_at
        FROM usage_session_days d
        JOIN usage_sessions s ON s.session_key = d.session_key
        ORDER BY d.day ASC;
        """ : """
        SELECT d.day, d.input_tokens, d.cached_input_tokens, d.output_tokens, d.reasoning_output_tokens,
               d.total_tokens, d.runs, d.estimated_cost_usd, d.latest_rate_limits_json, d.updated_at
        FROM usage_session_days d
        JOIN usage_sessions s ON s.session_key = d.session_key
        WHERE s.last_seen_source != 'archived'
        ORDER BY d.day ASC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw UsageError.database(lastError)
        }
        defer { sqlite3_finalize(statement) }

        var usagesByDay: [String: DailyUsage] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            mergeCurrentRow(statement, into: &usagesByDay)
        }
        return usagesByDay.values.sorted { $0.day < $1.day }
    }

    private func mergeCurrentRow(_ statement: OpaquePointer?, into usagesByDay: inout [String: DailyUsage]) {
        let day = String(cString: sqlite3_column_text(statement, 0))
        let totals = UsageTotals(
            inputTokens: sqlite3_column_int64(statement, 1),
            cachedInputTokens: sqlite3_column_int64(statement, 2),
            outputTokens: sqlite3_column_int64(statement, 3),
            reasoningOutputTokens: sqlite3_column_int64(statement, 4),
            totalTokens: sqlite3_column_int64(statement, 5),
            runs: sqlite3_column_int64(statement, 6),
            estimatedCostUSD: sqlite3_column_double(statement, 7)
        )
        let snapshot: RateLimitSnapshot?
        if let raw = sqlite3_column_text(statement, 8) {
            let json = String(cString: raw)
            snapshot = try? decoder.decode(RateLimitSnapshot.self, from: Data(json.utf8))
        } else {
            snapshot = nil
        }
        let updatedAt = sqlite3_column_int64(statement, 9)
        var usage = usagesByDay[day] ?? DailyUsage(
            day: day,
            totals: UsageTotals(),
            latestRateLimit: nil,
            updatedAt: updatedAt
        )
        usage.totals.add(totals)
        if let snapshot, usage.latestRateLimit?.timestamp ?? "" < snapshot.timestamp {
            usage.latestRateLimit = snapshot
        }
        usage.updatedAt = max(usage.updatedAt, updatedAt)
        usagesByDay[day] = usage
    }

    private func upsert(session: UsageSessionScan, now: Int64) throws {
        let sql = """
        INSERT INTO usage_sessions (
            session_key, status, last_seen_source, last_seen_path,
            file_size, file_mtime, first_scanned_at, last_scanned_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(session_key) DO UPDATE SET
            status = excluded.status,
            last_seen_source = excluded.last_seen_source,
            last_seen_path = excluded.last_seen_path,
            file_size = excluded.file_size,
            file_mtime = excluded.file_mtime,
            last_scanned_at = excluded.last_scanned_at;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw UsageError.database(lastError)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, session.sessionKey, -1, sqliteTransientDestructor())
        sqlite3_bind_text(statement, 2, session.status.rawValue, -1, sqliteTransientDestructor())
        sqlite3_bind_text(statement, 3, session.source.rawValue, -1, sqliteTransientDestructor())
        sqlite3_bind_text(statement, 4, session.path, -1, sqliteTransientDestructor())
        sqlite3_bind_int64(statement, 5, session.fileSize)
        sqlite3_bind_int64(statement, 6, session.fileMtime)
        sqlite3_bind_int64(statement, 7, now)
        sqlite3_bind_int64(statement, 8, now)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw UsageError.database(lastError)
        }
    }

    private func replaceSessionDays(sessionKey: String, usages: [DailyUsage], scannedDays: Set<String>?) throws {
        if let scannedDays {
            for day in scannedDays {
                try deleteSessionDay(sessionKey: sessionKey, day: day)
            }
        } else {
            try deleteSessionDays(sessionKey: sessionKey)
        }
        for usage in usages where usage.totals.totalTokens > 0 || usage.totals.runs > 0 {
            try insertSessionDay(sessionKey: sessionKey, usage: usage)
        }
    }

    private func deleteSessionDays(sessionKey: String) throws {
        let sql = "DELETE FROM usage_session_days WHERE session_key = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw UsageError.database(lastError)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, sessionKey, -1, sqliteTransientDestructor())
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw UsageError.database(lastError)
        }
    }

    private func deleteSessionDay(sessionKey: String, day: String) throws {
        let sql = "DELETE FROM usage_session_days WHERE session_key = ? AND day = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw UsageError.database(lastError)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, sessionKey, -1, sqliteTransientDestructor())
        sqlite3_bind_text(statement, 2, day, -1, sqliteTransientDestructor())
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw UsageError.database(lastError)
        }
    }

    private func insertSessionDay(sessionKey: String, usage: DailyUsage) throws {
        let sql = """
        INSERT OR REPLACE INTO usage_session_days (
            session_key, day, input_tokens, cached_input_tokens, output_tokens, reasoning_output_tokens,
            total_tokens, runs, estimated_cost_usd, latest_rate_limits_json,
            latest_rate_limits_timestamp, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw UsageError.database(lastError)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, sessionKey, -1, sqliteTransientDestructor())
        sqlite3_bind_text(statement, 2, usage.day, -1, sqliteTransientDestructor())
        sqlite3_bind_int64(statement, 3, usage.totals.inputTokens)
        sqlite3_bind_int64(statement, 4, usage.totals.cachedInputTokens)
        sqlite3_bind_int64(statement, 5, usage.totals.outputTokens)
        sqlite3_bind_int64(statement, 6, usage.totals.reasoningOutputTokens)
        sqlite3_bind_int64(statement, 7, usage.totals.totalTokens)
        sqlite3_bind_int64(statement, 8, usage.totals.runs)
        sqlite3_bind_double(statement, 9, usage.totals.estimatedCostUSD)
        if let snapshot = usage.latestRateLimit,
           let data = try? encoder.encode(snapshot),
           let json = String(data: data, encoding: .utf8) {
            sqlite3_bind_text(statement, 10, json, -1, sqliteTransientDestructor())
            sqlite3_bind_text(statement, 11, snapshot.timestamp, -1, sqliteTransientDestructor())
        } else {
            sqlite3_bind_null(statement, 10)
            sqlite3_bind_null(statement, 11)
        }
        sqlite3_bind_int64(statement, 12, usage.updatedAt)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw UsageError.database(lastError)
        }
    }

    private func markUnseenSessionsMissing(status: UsageSessionStatus, seenSessionKeys: Set<String>) throws {
        let sql = "SELECT session_key FROM usage_sessions WHERE status = ? AND session_key NOT LIKE '__legacy__:%';"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw UsageError.database(lastError)
        }
        sqlite3_bind_text(statement, 1, status.rawValue, -1, sqliteTransientDestructor())
        var missingKeys: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let key = String(cString: sqlite3_column_text(statement, 0))
            if !seenSessionKeys.contains(key) {
                missingKeys.append(key)
            }
        }
        sqlite3_finalize(statement)

        for key in missingKeys {
            try updateSessionStatus(sessionKey: key, status: .missing)
        }
    }

    private func updateSessionStatus(sessionKey: String, status: UsageSessionStatus) throws {
        let sql = "UPDATE usage_sessions SET status = ? WHERE session_key = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw UsageError.database(lastError)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, status.rawValue, -1, sqliteTransientDestructor())
        sqlite3_bind_text(statement, 2, sessionKey, -1, sqliteTransientDestructor())
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw UsageError.database(lastError)
        }
    }

    private func rebuildLegacyResiduals(scannedDays: Set<String>?, now: Int64) throws {
        let legacyTotals = try legacyDailyTotals(scannedDays: scannedDays)
        guard !legacyTotals.isEmpty else { return }
        let realTotals = try realSessionDailyTotals(scannedDays: scannedDays)

        for key in legacyTotals.keys {
            let sessionKey = legacySessionKey(for: key.day, source: key.source)
            try deleteSessionDays(sessionKey: sessionKey)
            guard let residual = legacyTotals[key]?.subtractingClamped(realTotals[key] ?? UsageTotals()),
                  residual.totalTokens > 0 || residual.runs > 0 else {
                continue
            }
            try upsertLegacySession(sessionKey: sessionKey, day: key.day, source: key.source, now: now)
            try insertSessionDay(
                sessionKey: sessionKey,
                usage: DailyUsage(day: key.day, totals: residual, latestRateLimit: nil, updatedAt: now)
            )
        }
    }

    private func upsertLegacySession(sessionKey: String, day: String, source: UsageSource, now: Int64) throws {
        let session = UsageSessionScan(
            sessionKey: sessionKey,
            source: source,
            status: .missing,
            path: "legacy:\(day)",
            fileSize: 0,
            fileMtime: 0,
            usages: []
        )
        try upsert(session: session, now: now)
    }

    private func legacyDailyTotals(scannedDays: Set<String>?) throws -> [LegacyUsageKey: UsageTotals] {
        let sql: String
        if let scannedDays, scannedDays.isEmpty {
            return [:]
        } else if scannedDays == nil {
            sql = """
            SELECT day, source, input_tokens, cached_input_tokens, output_tokens, reasoning_output_tokens,
                   total_tokens, runs, estimated_cost_usd
            FROM daily_usage;
            """
        } else {
            sql = """
            SELECT day, source, input_tokens, cached_input_tokens, output_tokens, reasoning_output_tokens,
                   total_tokens, runs, estimated_cost_usd
            FROM daily_usage
            WHERE day = ?;
            """
        }

        var totalsByDay: [LegacyUsageKey: UsageTotals] = [:]
        if let scannedDays {
            for day in scannedDays {
                try fetchLegacyDailyTotals(sql: sql, day: day, into: &totalsByDay)
            }
        } else {
            try fetchLegacyDailyTotals(sql: sql, day: nil, into: &totalsByDay)
        }
        return totalsByDay
    }

    private func fetchLegacyDailyTotals(
        sql: String,
        day: String?,
        into totalsByDay: inout [LegacyUsageKey: UsageTotals]
    ) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw UsageError.database(lastError)
        }
        defer { sqlite3_finalize(statement) }
        if let day {
            sqlite3_bind_text(statement, 1, day, -1, sqliteTransientDestructor())
        }
        while sqlite3_step(statement) == SQLITE_ROW {
            let day = String(cString: sqlite3_column_text(statement, 0))
            let source = UsageSource(rawValue: String(cString: sqlite3_column_text(statement, 1))) ?? .active
            let totals = UsageTotals(
                inputTokens: sqlite3_column_int64(statement, 2),
                cachedInputTokens: sqlite3_column_int64(statement, 3),
                outputTokens: sqlite3_column_int64(statement, 4),
                reasoningOutputTokens: sqlite3_column_int64(statement, 5),
                totalTokens: sqlite3_column_int64(statement, 6),
                runs: sqlite3_column_int64(statement, 7),
                estimatedCostUSD: sqlite3_column_double(statement, 8)
            )
            let key = LegacyUsageKey(day: day, source: source)
            var current = totalsByDay[key] ?? UsageTotals()
            current.add(totals)
            totalsByDay[key] = current
        }
    }

    private func realSessionDailyTotals(scannedDays: Set<String>?) throws -> [LegacyUsageKey: UsageTotals] {
        let sql: String
        if scannedDays == nil {
            sql = """
            SELECT d.day, s.last_seen_source, d.input_tokens, d.cached_input_tokens,
                   d.output_tokens, d.reasoning_output_tokens,
                   total_tokens, runs, estimated_cost_usd
            FROM usage_session_days d
            JOIN usage_sessions s ON s.session_key = d.session_key
            WHERE d.session_key NOT LIKE '__legacy__:%';
            """
        } else {
            sql = """
            SELECT d.day, s.last_seen_source, d.input_tokens, d.cached_input_tokens,
                   d.output_tokens, d.reasoning_output_tokens,
                   total_tokens, runs, estimated_cost_usd
            FROM usage_session_days d
            JOIN usage_sessions s ON s.session_key = d.session_key
            WHERE d.session_key NOT LIKE '__legacy__:%' AND d.day = ?;
            """
        }

        var totalsByDay: [LegacyUsageKey: UsageTotals] = [:]
        if let scannedDays {
            for day in scannedDays {
                try fetchRealSessionDailyTotals(sql: sql, day: day, into: &totalsByDay)
            }
        } else {
            try fetchRealSessionDailyTotals(sql: sql, day: nil, into: &totalsByDay)
        }
        return totalsByDay
    }

    private func fetchRealSessionDailyTotals(
        sql: String,
        day: String?,
        into totalsByDay: inout [LegacyUsageKey: UsageTotals]
    ) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw UsageError.database(lastError)
        }
        defer { sqlite3_finalize(statement) }
        if let day {
            sqlite3_bind_text(statement, 1, day, -1, sqliteTransientDestructor())
        }
        while sqlite3_step(statement) == SQLITE_ROW {
            let day = String(cString: sqlite3_column_text(statement, 0))
            let source = UsageSource(rawValue: String(cString: sqlite3_column_text(statement, 1))) ?? .active
            let totals = UsageTotals(
                inputTokens: sqlite3_column_int64(statement, 2),
                cachedInputTokens: sqlite3_column_int64(statement, 3),
                outputTokens: sqlite3_column_int64(statement, 4),
                reasoningOutputTokens: sqlite3_column_int64(statement, 5),
                totalTokens: sqlite3_column_int64(statement, 6),
                runs: sqlite3_column_int64(statement, 7),
                estimatedCostUSD: sqlite3_column_double(statement, 8)
            )
            let key = LegacyUsageKey(day: day, source: source)
            var current = totalsByDay[key] ?? UsageTotals()
            current.add(totals)
            totalsByDay[key] = current
        }
    }

    private func legacySessionKey(for day: String, source: UsageSource) -> String {
        "__legacy__:\(source.rawValue):\(day)"
    }

    private func createDailyUsageTable(named tableName: String) throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS \(tableName) (
            day TEXT NOT NULL,
            source TEXT NOT NULL,
            input_tokens INTEGER NOT NULL,
            cached_input_tokens INTEGER NOT NULL,
            output_tokens INTEGER NOT NULL,
            reasoning_output_tokens INTEGER NOT NULL,
            total_tokens INTEGER NOT NULL,
            runs INTEGER NOT NULL,
            estimated_cost_usd REAL NOT NULL,
            latest_rate_limits_json TEXT,
            latest_rate_limits_timestamp TEXT,
            updated_at INTEGER NOT NULL,
            PRIMARY KEY(day, source)
        );
        """)
    }

    private func tableExists(_ tableName: String) throws -> Bool {
        let sql = "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw UsageError.database(lastError)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, tableName, -1, sqliteTransientDestructor())
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func hasRows(in tableName: String) throws -> Bool {
        let sql = "SELECT 1 FROM \(tableName) LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw UsageError.database(lastError)
        }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func columnExists(_ columnName: String, in tableName: String) throws -> Bool {
        let sql = "PRAGMA table_info(\(tableName));"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw UsageError.database(lastError)
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            if let raw = sqlite3_column_text(statement, 1),
               String(cString: raw) == columnName {
                return true
            }
        }
        return false
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw UsageError.database(lastError)
        }
    }

    private var lastError: String {
        if let message = sqlite3_errmsg(db) {
            return String(cString: message)
        }
        return "Unknown SQLite error"
    }
}

private struct LegacyUsageKey: Hashable {
    var day: String
    var source: UsageSource
}

private extension UsageTotals {
    func subtractingClamped(_ other: UsageTotals) -> UsageTotals {
        UsageTotals(
            inputTokens: max(0, inputTokens - other.inputTokens),
            cachedInputTokens: max(0, cachedInputTokens - other.cachedInputTokens),
            outputTokens: max(0, outputTokens - other.outputTokens),
            reasoningOutputTokens: max(0, reasoningOutputTokens - other.reasoningOutputTokens),
            totalTokens: max(0, totalTokens - other.totalTokens),
            runs: max(0, runs - other.runs),
            estimatedCostUSD: max(0, estimatedCostUSD - other.estimatedCostUSD)
        )
    }
}
