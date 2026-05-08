import AppKit
import Foundation
import SQLite3
import SwiftUI

struct CodexUsageScanner {
    var codexPath: URL

    func scan(source: UsageSource, daysBack: Int?) throws -> [DailyUsage] {
        let sessionScans = try scanSessions(source: source, daysBack: daysBack)
        var totalsByDay: [String: ScanResult] = [:]
        for sessionScan in sessionScans {
            for usage in sessionScan.usages {
                var result = totalsByDay[usage.day] ?? ScanResult()
                result.totals.add(usage.totals)
                if let snapshot = usage.latestRateLimit,
                   result.latestRateLimit?.timestamp ?? "" < snapshot.timestamp {
                    result.latestRateLimit = snapshot
                }
                totalsByDay[usage.day] = result
            }
        }
        return dailyUsages(from: totalsByDay, targetDays: daysBack.map { Set(daysToScan(daysBack: $0)) })
    }

    func scanSessions(
        source: UsageSource,
        daysBack: Int?,
        scanStates: [String: UsageSessionScanState] = [:]
    ) throws -> [UsageSessionScan] {
        let files = try files(source: source, daysBack: daysBack)
        let status: UsageSessionStatus = source == .active ? .active : .archived
        return try files.map { file in
            let sessionKey = sessionKey(for: file)
            let fileSize = try fileSize(of: file)
            let fileMtime = try modificationTimeMilliseconds(of: file)
            let plan = scanPlan(fileSize: fileSize, fileMtime: fileMtime, state: scanStates[sessionKey])
            if plan.mode == .unchanged {
                return UsageSessionScan(
                    sessionKey: sessionKey,
                    source: source,
                    status: status,
                    scanMode: .unchanged,
                    path: file.path,
                    fileSize: fileSize,
                    fileMtime: fileMtime,
                    lastScannedOffset: plan.startOffset,
                    usages: []
                )
            }
            // Persisted offsets are only safe after every reachable row has been considered.
            let scan = try scan(file: file, targetDays: nil, startOffset: plan.startOffset)
            return UsageSessionScan(
                sessionKey: sessionKey,
                source: source,
                status: status,
                scanMode: plan.mode,
                path: file.path,
                fileSize: fileSize,
                fileMtime: fileMtime,
                lastScannedOffset: scan.scannedOffset,
                usages: dailyUsages(from: scan.results, targetDays: nil)
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

    private func files(source: UsageSource, daysBack: Int?) throws -> [URL] {
        let directory: URL
        switch source {
        case .active:
            directory = codexPath.appendingPathComponent("sessions", isDirectory: true)
        case .archived:
            directory = codexPath.appendingPathComponent("archived_sessions", isDirectory: true)
        }

        var result = try jsonlFilesRecursively(in: directory)
        if let daysBack {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let earliest = calendar.date(byAdding: .day, value: -max(1, daysBack) + 1, to: today) ?? today
            result = try result.filter { try modificationDate(of: $0) >= earliest }
        }
        return result
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

    private func modificationTimeMilliseconds(of url: URL) throws -> Int64 {
        Int64((try modificationDate(of: url).timeIntervalSince1970 * 1_000).rounded(.down))
    }

    private func fileSize(of url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    private func sessionKey(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    private func dailyUsages(from results: [String: ScanResult], targetDays: Set<String>?) -> [DailyUsage] {
        let updatedAt = Int64(Date().timeIntervalSince1970)
        let days = targetDays?.sorted() ?? results.keys.sorted()
        return days.map { day in
            let result = results[day] ?? ScanResult()
            return DailyUsage(
                day: day,
                totals: result.totals.withEstimatedCost(),
                latestRateLimit: result.latestRateLimit,
                updatedAt: updatedAt
            )
        }
    }

    private func scan(files: [URL], targetDays: Set<String>?) throws -> [String: ScanResult] {
        var results: [String: ScanResult] = [:]
        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackTimestampFormatter = ISO8601DateFormatter()
        fallbackTimestampFormatter.formatOptions = [.withInternetDateTime]
        for file in files {
            let scan = try scan(file: file, targetDays: targetDays)
            for (day, fileResult) in scan.results {
                var result = results[day] ?? ScanResult()
                result.totals.add(fileResult.totals)
                if let snapshot = fileResult.latestRateLimit,
                   result.latestRateLimit?.timestamp ?? "" < snapshot.timestamp {
                    result.latestRateLimit = snapshot
                }
                results[day] = result
            }
        }
        return results
    }

    private func scan(file: URL, targetDays: Set<String>?, startOffset: Int64 = 0) throws -> FileScan {
        var results: [String: ScanResult] = [:]
        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackTimestampFormatter = ISO8601DateFormatter()
        fallbackTimestampFormatter.formatOptions = [.withInternetDateTime]
        let scannedOffset = try scan(
            file: file,
            targetDays: targetDays,
            startOffset: startOffset,
            results: &results,
            timestampFormatter: timestampFormatter,
            fallbackTimestampFormatter: fallbackTimestampFormatter
        )
        return FileScan(results: results, scannedOffset: scannedOffset)
    }

    private func scan(
        file: URL,
        targetDays: Set<String>?,
        startOffset: Int64,
        results: inout [String: ScanResult],
        timestampFormatter: ISO8601DateFormatter,
        fallbackTimestampFormatter: ISO8601DateFormatter
    ) throws -> Int64 {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(max(0, startOffset)))

        let newline = Data([0x0A])
        var buffer = Data()
        var scannedOffset = max(0, startOffset)
        while true {
            guard let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty else {
                break
            }
            buffer.append(chunk)
            while let range = buffer.firstRange(of: newline) {
                let line = buffer[..<range.lowerBound]
                process(
                    line: Data(line),
                    targetDays: targetDays,
                    results: &results,
                    timestampFormatter: timestampFormatter,
                    fallbackTimestampFormatter: fallbackTimestampFormatter
                )
                scannedOffset += Int64(range.upperBound)
                buffer.removeSubrange(..<range.upperBound)
            }
        }
        if !buffer.isEmpty, isCompleteJSONLine(buffer) {
            process(
                line: buffer,
                targetDays: targetDays,
                results: &results,
                timestampFormatter: timestampFormatter,
                fallbackTimestampFormatter: fallbackTimestampFormatter
            )
            scannedOffset += Int64(buffer.count)
        }
        return scannedOffset
    }

    private func scanPlan(
        fileSize: Int64,
        fileMtime: Int64,
        state: UsageSessionScanState?
    ) -> (mode: UsageSessionScanMode, startOffset: Int64) {
        guard let state else {
            return (.full, 0)
        }
        let offset = max(0, state.lastScannedOffset)
        if fileSize == state.fileSize, isSameStoredMtime(fileMtime, state.fileMtime), offset == fileSize {
            return (.unchanged, offset)
        }
        if offset > 0,
           fileSize >= offset,
           isNotOlderStoredMtime(fileMtime, state.fileMtime),
           (fileSize > state.fileSize || offset < fileSize) {
            return (.incremental, offset)
        }
        return state.lastScannedOffset > 0 ? (.fullReset, 0) : (.full, 0)
    }

    private func isSameStoredMtime(_ fileMtime: Int64, _ storedMtime: Int64) -> Bool {
        fileMtime == storedMtime || isSecondPrecisionMatch(fileMtime, storedMtime)
    }

    private func isNotOlderStoredMtime(_ fileMtime: Int64, _ storedMtime: Int64) -> Bool {
        fileMtime >= storedMtime || fileMtime / 1_000 >= storedMtime
    }

    private func isSecondPrecisionMatch(_ fileMtime: Int64, _ storedMtime: Int64) -> Bool {
        storedMtime < 10_000_000_000 && fileMtime / 1_000 == storedMtime
    }

    private func process(
        line data: Data,
        targetDays: Set<String>?,
        results: inout [String: ScanResult],
        timestampFormatter: ISO8601DateFormatter,
        fallbackTimestampFormatter: ISO8601DateFormatter
    ) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let timestamp = object["timestamp"] as? String,
              let day = dayFromTimestamp(
                timestamp,
                formatter: timestampFormatter,
                fallbackFormatter: fallbackTimestampFormatter
              ),
              let payload = object["payload"] as? [String: Any] else {
            return
        }
        if let targetDays, !targetDays.contains(day) {
            return
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

    private func isCompleteJSONLine(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data)) != nil
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

private struct FileScan {
    var results: [String: ScanResult]
    var scannedOffset: Int64
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
