import AppKit
import Foundation
import SQLite3
import SwiftUI

struct CodexUsageScanner {
    var codexPath: URL
    var includeArchivedSessions: Bool

    func scan(daysBack: Int?) throws -> [DailyUsage] {
        let targetDays = daysBack.map { Set(daysToScan(daysBack: $0)) }
        let files = try files(daysBack: daysBack)
        let results = try scan(files: files, targetDays: targetDays)
        let days = targetDays?.sorted() ?? results.keys.sorted()
        return days.map { day in
            let result = results[day] ?? ScanResult()
            return DailyUsage(
                day: day,
                totals: result.totals.withEstimatedCost(),
                latestRateLimit: result.latestRateLimit,
                updatedAt: Int64(Date().timeIntervalSince1970)
            )
        }
    }

    private func daysToScan(daysBack: Int) -> [String] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<max(1, daysBack)).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
        }
        .map(Self.dayString)
        .sorted()
    }

    private func files(daysBack: Int?) throws -> [URL] {
        var result = try jsonlFilesRecursively(in: codexPath.appendingPathComponent("sessions", isDirectory: true))
        if let daysBack {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let earliest = calendar.date(byAdding: .day, value: -max(1, daysBack) + 1, to: today) ?? today
            result = try result.filter { try modificationDate(of: $0) >= earliest }
        } else if includeArchivedSessions {
            result.append(contentsOf: try jsonlFiles(in: codexPath.appendingPathComponent("archived_sessions", isDirectory: true)))
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

    private func jsonlFilesRecursively(in directory: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        var urls: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            urls.append(url)
        }
        return urls
    }

    private func modificationDate(of url: URL) throws -> Date {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
        return values.contentModificationDate ?? .distantPast
    }

    private func scan(files: [URL], targetDays: Set<String>?) throws -> [String: ScanResult] {
        var results: [String: ScanResult] = [:]
        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackTimestampFormatter = ISO8601DateFormatter()
        fallbackTimestampFormatter.formatOptions = [.withInternetDateTime]
        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let timestamp = object["timestamp"] as? String,
                      let day = dayFromTimestamp(
                        timestamp,
                        formatter: timestampFormatter,
                        fallbackFormatter: fallbackTimestampFormatter
                      ),
                      let payload = object["payload"] as? [String: Any] else {
                    continue
                }
                if let targetDays, !targetDays.contains(day) {
                    continue
                }
                var result = results[day] ?? ScanResult()
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
                results[day] = result
            }
        }
        return results
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

    private func dayFromTimestamp(
        _ timestamp: String,
        formatter: ISO8601DateFormatter,
        fallbackFormatter: ISO8601DateFormatter
    ) -> String? {
        guard let date = formatter.date(from: timestamp) ?? fallbackFormatter.date(from: timestamp) else {
            return nil
        }
        return Self.dayString(from: date)
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
