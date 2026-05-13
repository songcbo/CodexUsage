import AppKit
import Foundation
import SQLite3
import SwiftUI

enum UsageRange: String, CaseIterable, Identifiable {
    case today
    case sevenDays
    case thirtyDays
    case all

    var id: String { rawValue }
}

enum UsageSource: String {
    case active
    case archived
}

enum UsageSessionStatus: String {
    case active
    case archived
    case missing
}

enum UsageSessionScanMode {
    case full
    case fullReset
    case incremental
    case unchanged
}

struct UsageSessionScanState {
    var fileSize: Int64
    var fileMtime: Int64
    var lastScannedOffset: Int64
}

struct UsageTotals: Codable, Equatable {
    var inputTokens: Int64 = 0
    var cachedInputTokens: Int64 = 0
    var outputTokens: Int64 = 0
    var reasoningOutputTokens: Int64 = 0
    var totalTokens: Int64 = 0
    var runs: Int64 = 0
    var estimatedCostUSD: Double = 0

    var cacheHitRate: Double {
        guard inputTokens > 0 else { return 0 }
        return Double(cachedInputTokens) / Double(inputTokens)
    }

    mutating func add(_ other: UsageTotals) {
        inputTokens += other.inputTokens
        cachedInputTokens += other.cachedInputTokens
        outputTokens += other.outputTokens
        reasoningOutputTokens += other.reasoningOutputTokens
        totalTokens += other.totalTokens
        runs += other.runs
        estimatedCostUSD += other.estimatedCostUSD
    }
}

struct RateLimitSnapshot: Codable, Equatable {
    var limitId: String?
    var limitName: String?
    var timestamp: String
    var planType: String
    var primaryUsedPercent: Double
    var primaryWindowMinutes: Int
    var primaryResetsAt: Int64
    var secondaryUsedPercent: Double
    var secondaryWindowMinutes: Int
    var secondaryResetsAt: Int64

    var quotaKey: String {
        if let limitId, !limitId.isEmpty {
            return limitId
        }
        if let limitName, !limitName.isEmpty {
            return limitName
        }
        return "default"
    }

    var displayName: String {
        if let limitName, !limitName.isEmpty {
            return limitName
        }
        if quotaKey == "codex" || quotaKey == "default" {
            return "Codex"
        }
        return quotaKey
    }
}

struct DailyUsage: Identifiable, Equatable {
    var id: String { day }
    var day: String
    var totals: UsageTotals
    var latestRateLimit: RateLimitSnapshot?
    var rateLimits: [RateLimitSnapshot] = []
    var updatedAt: Int64
}

struct UsageSessionScan {
    var sessionKey: String
    var source: UsageSource
    var status: UsageSessionStatus
    var scanMode: UsageSessionScanMode
    var path: String
    var fileSize: Int64
    var fileMtime: Int64
    var lastScannedOffset: Int64
    var usages: [DailyUsage]
}
