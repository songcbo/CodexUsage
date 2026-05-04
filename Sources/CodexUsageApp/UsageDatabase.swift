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
        try execute("""
        CREATE TABLE IF NOT EXISTS daily_usage (
            day TEXT PRIMARY KEY NOT NULL,
            input_tokens INTEGER NOT NULL,
            cached_input_tokens INTEGER NOT NULL,
            output_tokens INTEGER NOT NULL,
            reasoning_output_tokens INTEGER NOT NULL,
            total_tokens INTEGER NOT NULL,
            runs INTEGER NOT NULL,
            estimated_cost_usd REAL NOT NULL,
            latest_rate_limits_json TEXT,
            latest_rate_limits_timestamp TEXT,
            updated_at INTEGER NOT NULL
        );
        """)
    }

    deinit {
        sqlite3_close(db)
    }

    func upsert(usages: [DailyUsage]) throws {
        let sql = """
        INSERT INTO daily_usage (
            day, input_tokens, cached_input_tokens, output_tokens, reasoning_output_tokens,
            total_tokens, runs, estimated_cost_usd, latest_rate_limits_json,
            latest_rate_limits_timestamp, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(day) DO UPDATE SET
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
            sqlite3_bind_int64(statement, 2, usage.totals.inputTokens)
            sqlite3_bind_int64(statement, 3, usage.totals.cachedInputTokens)
            sqlite3_bind_int64(statement, 4, usage.totals.outputTokens)
            sqlite3_bind_int64(statement, 5, usage.totals.reasoningOutputTokens)
            sqlite3_bind_int64(statement, 6, usage.totals.totalTokens)
            sqlite3_bind_int64(statement, 7, usage.totals.runs)
            sqlite3_bind_double(statement, 8, usage.totals.estimatedCostUSD)
            if let snapshot = usage.latestRateLimit,
               let data = try? encoder.encode(snapshot),
               let json = String(data: data, encoding: .utf8) {
                sqlite3_bind_text(statement, 9, json, -1, sqliteTransientDestructor())
                sqlite3_bind_text(statement, 10, snapshot.timestamp, -1, sqliteTransientDestructor())
            } else {
                sqlite3_bind_null(statement, 9)
                sqlite3_bind_null(statement, 10)
            }
            sqlite3_bind_int64(statement, 11, usage.updatedAt)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw UsageError.database(lastError)
            }
        }
    }

    func fetchAllDailyUsage() throws -> [DailyUsage] {
        let sql = """
        SELECT day, input_tokens, cached_input_tokens, output_tokens, reasoning_output_tokens,
               total_tokens, runs, estimated_cost_usd, latest_rate_limits_json, updated_at
        FROM daily_usage
        ORDER BY day ASC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw UsageError.database(lastError)
        }
        defer { sqlite3_finalize(statement) }

        var usages: [DailyUsage] = []
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
            usages.append(DailyUsage(
                day: day,
                totals: totals,
                latestRateLimit: snapshot,
                updatedAt: sqlite3_column_int64(statement, 9)
            ))
        }
        return usages
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
