import AppKit
import Foundation
import SQLite3
import SwiftUI

@MainActor
final class UsageViewModel: ObservableObject {
    @Published private(set) var dailyUsages: [DailyUsage] = []
    @Published private(set) var selectedRangeTotals = UsageTotals()
    @Published private(set) var latestRateLimit: RateLimitSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshError: String?
    @Published var selectedRange: UsageRange = .today {
        didSet { recalculateSelectedRange() }
    }
    @Published var visibleMonth = Date()

    private let database: UsageDatabase
    private var didStart = false
    private var settings: AppSettings?

    init() {
        do {
            database = try UsageDatabase()
        } catch {
            fatalError("Unable to open usage database: \(error)")
        }
    }

    func start(settings: AppSettings) async {
        guard !didStart else { return }
        didStart = true
        self.settings = settings
        selectedRange = settings.defaultRange
        await refreshStartupRange(settings: settings)
    }

    func refreshToday(settings: AppSettings) async {
        await refresh(daysBack: 1, settings: settings)
    }

    func refreshRecentDays(settings: AppSettings) async {
        await refresh(daysBack: 7, settings: settings)
    }

    func refreshStartupRange(settings: AppSettings) async {
        await refresh(daysBack: settings.startupScanDays == 0 ? nil : settings.startupScanDays, settings: settings)
    }

    func rebuildAll(settings: AppSettings) async {
        await refresh(daysBack: nil, settings: settings)
    }

    func usage(for day: String) -> DailyUsage? {
        dailyUsages.first { $0.day == day }
    }

    func resetVisibleMonthToCurrent() {
        visibleMonth = Date()
    }

    private func refresh(daysBack: Int?, settings: AppSettings) async {
        isRefreshing = true
        lastRefreshError = nil
        do {
            let scanner = CodexUsageScanner(
                codexPath: URL(fileURLWithPath: settings.codexPath),
                includeArchivedSessions: settings.includeArchivedSessions
            )
            let usages = try scanner.scan(daysBack: daysBack)
            try database.upsert(usages: usages)
            try reloadFromDatabase()
        } catch {
            lastRefreshError = error.localizedDescription
        }
        isRefreshing = false
    }

    private func reloadFromDatabase() throws {
        dailyUsages = try database.fetchAllDailyUsage()
        latestRateLimit = dailyUsages
            .compactMap(\.latestRateLimit)
            .max { $0.timestamp < $1.timestamp }
        recalculateSelectedRange()
    }

    private func recalculateSelectedRange() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lowerBound: String?
        switch selectedRange {
        case .today:
            lowerBound = Self.dayFormatter.string(from: today)
        case .sevenDays:
            lowerBound = Self.dayFormatter.string(from: calendar.date(byAdding: .day, value: -6, to: today) ?? today)
        case .thirtyDays:
            lowerBound = Self.dayFormatter.string(from: calendar.date(byAdding: .day, value: -29, to: today) ?? today)
        case .all:
            lowerBound = nil
        }

        selectedRangeTotals = dailyUsages.reduce(into: UsageTotals()) { result, usage in
            if let lowerBound, usage.day < lowerBound {
                return
            }
            result.add(usage.totals)
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
