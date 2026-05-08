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
    var timestamp: String
    var planType: String
    var primaryUsedPercent: Double
    var primaryWindowMinutes: Int
    var primaryResetsAt: Int64
    var secondaryUsedPercent: Double
    var secondaryWindowMinutes: Int
    var secondaryResetsAt: Int64
}

struct DailyUsage: Identifiable, Equatable {
    var id: String { day }
    var day: String
    var totals: UsageTotals
    var latestRateLimit: RateLimitSnapshot?
    var updatedAt: Int64
}
