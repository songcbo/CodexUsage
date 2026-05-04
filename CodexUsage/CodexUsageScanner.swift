import AppKit
import Foundation
import SQLite3
import SwiftUI

struct CodexUsageScanner {
    var codexPath: URL
    var includeArchivedSessions: Bool

    func scan(daysBack: Int?) throws -> [DailyUsage] {
        let targetDays = try daysToScan(daysBack: daysBack)
        return try targetDays.map { day in
            let files = try files(for: day)
            let result = try scan(files: files)
            return DailyUsage(
                day: day,
                totals: result.totals.withEstimatedCost(),
                latestRateLimit: result.latestRateLimit,
                updatedAt: Int64(Date().timeIntervalSince1970)
            )
        }
    }

    private func daysToScan(daysBack: Int?) throws -> [String] {
        if let daysBack {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            return (0..<max(1, daysBack)).compactMap { offset in
                calendar.date(byAdding: .day, value: -offset, to: today)
            }
            .map(Self.dayString)
            .sorted()
        }

        var days = Set<String>()
        let sessions = codexPath.appendingPathComponent("sessions", isDirectory: true)
        if let enumerator = FileManager.default.enumerator(at: sessions, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                if let day = dayFromSessionPath(url) {
                    days.insert(day)
                }
            }
        }

        if includeArchivedSessions {
            let archived = codexPath.appendingPathComponent("archived_sessions", isDirectory: true)
            if let enumerator = FileManager.default.enumerator(at: archived, includingPropertiesForKeys: nil) {
                for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                    if let day = dayFromFilename(url) {
                        days.insert(day)
                    }
                }
            }
        }

        return days.sorted()
    }

    private func files(for day: String) throws -> [URL] {
        let components = day.split(separator: "-").map(String.init)
        var result: [URL] = []
        if components.count == 3 {
            let dayDirectory = codexPath
                .appendingPathComponent("sessions", isDirectory: true)
                .appendingPathComponent(components[0], isDirectory: true)
                .appendingPathComponent(components[1], isDirectory: true)
                .appendingPathComponent(components[2], isDirectory: true)
            result.append(contentsOf: try jsonlFiles(in: dayDirectory))
        }

        if includeArchivedSessions {
            let archived = codexPath.appendingPathComponent("archived_sessions", isDirectory: true)
            result.append(contentsOf: try jsonlFiles(in: archived).filter { url in
                dayFromFilename(url) == day
            })
        }
        return result
    }

    private func jsonlFiles(in directory: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return urls.filter { $0.pathExtension == "jsonl" }
    }

    private func scan(files: [URL]) throws -> ScanResult {
        var result = ScanResult()
        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let timestamp = object["timestamp"] as? String,
                      let payload = object["payload"] as? [String: Any] else {
                    continue
                }
                if payload["type"] as? String == "token_count",
                   let info = payload["info"] as? [String: Any],
                   let last = info["last_token_usage"] as? [String: Any] {
                    result.totals.inputTokens += int64(last["input_tokens"])
                    result.totals.cachedInputTokens += int64(last["cached_input_tokens"])
                    result.totals.outputTokens += int64(last["output_tokens"])
                    result.totals.reasoningOutputTokens += int64(last["reasoning_output_tokens"])
                    result.totals.totalTokens += int64(last["total_tokens"])
                    result.totals.runs += 1
                }
                if let rateLimits = payload["rate_limits"] as? [String: Any],
                   let snapshot = snapshot(from: rateLimits, timestamp: timestamp),
                   result.latestRateLimit?.timestamp ?? "" < snapshot.timestamp {
                    result.latestRateLimit = snapshot
                }
            }
        }
        return result
    }

    private func snapshot(from json: [String: Any], timestamp: String) -> RateLimitSnapshot? {
        guard let primary = json["primary"] as? [String: Any],
              let secondary = json["secondary"] as? [String: Any] else {
            return nil
        }
        return RateLimitSnapshot(
            timestamp: timestamp,
            planType: json["plan_type"] as? String ?? "",
            primaryUsedPercent: double(primary["used_percent"]),
            primaryWindowMinutes: Int(int64(primary["window_minutes"])),
            primaryResetsAt: int64(primary["resets_at"]),
            secondaryUsedPercent: double(secondary["used_percent"]),
            secondaryWindowMinutes: Int(int64(secondary["window_minutes"])),
            secondaryResetsAt: int64(secondary["resets_at"])
        )
    }

    private func int64(_ value: Any?) -> Int64 {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? Double { return Int64(value) }
        if let value = value as? String { return Int64(value) ?? 0 }
        return 0
    }

    private func double(_ value: Any?) -> Double {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? String { return Double(value) ?? 0 }
        return 0
    }

    private func dayFromSessionPath(_ url: URL) -> String? {
        let parts = url.pathComponents
        guard parts.count >= 4 else { return nil }
        let day = parts[parts.count - 2]
        let month = parts[parts.count - 3]
        let year = parts[parts.count - 4]
        guard year.count == 4, month.count == 2, day.count == 2 else { return nil }
        return "\(year)-\(month)-\(day)"
    }

    private func dayFromFilename(_ url: URL) -> String? {
        let name = url.lastPathComponent
        guard let range = name.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) else {
            return nil
        }
        return String(name[range])
    }

    private static func dayString(from date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct ScanResult {
    var totals = UsageTotals()
    var latestRateLimit: RateLimitSnapshot?
}

private extension UsageTotals {
    func withEstimatedCost() -> UsageTotals {
        var copy = self
        let billableInput = max(0, inputTokens - cachedInputTokens)
        copy.estimatedCostUSD =
            Double(billableInput) / 1_000_000 * 1.25 +
            Double(cachedInputTokens) / 1_000_000 * 0.125 +
            Double(outputTokens + reasoningOutputTokens) / 1_000_000 * 10.0
        return copy
    }
}

enum UsageError: LocalizedError {
    case database(String)

    var errorDescription: String? {
        switch self {
        case .database(let message):
            return message
        }
    }
}
