import AppKit
import Foundation
import SQLite3
import SwiftUI

enum BreakReminderMode: String, CaseIterable, Identifiable {
    case reminder
    case force

    var id: String { rawValue }
}

@MainActor
final class AppSettings: ObservableObject {
    static let idleResetMinutes = 10

    @Published var codexPath: String {
        didSet { defaults.set(codexPath, forKey: Keys.codexPath) }
    }

    @Published var includeArchivedSessions: Bool {
        didSet { defaults.set(includeArchivedSessions, forKey: Keys.includeArchivedSessions) }
    }

    @Published var language: String {
        didSet { defaults.set(language, forKey: Keys.language) }
    }

    @Published var startupScanDays: Int {
        didSet { defaults.set(startupScanDays, forKey: Keys.startupScanDays) }
    }

    @Published var showEstimatedCost: Bool {
        didSet { defaults.set(showEstimatedCost, forKey: Keys.showEstimatedCost) }
    }

    @Published var showReasoningTokens: Bool {
        didSet { defaults.set(showReasoningTokens, forKey: Keys.showReasoningTokens) }
    }

    @Published var defaultRange: UsageRange {
        didSet { defaults.set(defaultRange.rawValue, forKey: Keys.defaultRange) }
    }

    @Published var breakReminderEnabled: Bool {
        didSet { defaults.set(breakReminderEnabled, forKey: Keys.breakReminderEnabled) }
    }

    @Published var breakReminderMode: BreakReminderMode {
        didSet { defaults.set(breakReminderMode.rawValue, forKey: Keys.breakReminderMode) }
    }

    @Published var breakWorkMinutes: Int {
        didSet { defaults.set(breakWorkMinutes, forKey: Keys.breakWorkMinutes) }
    }

    @Published var breakDurationMinutes: Int {
        didSet { defaults.set(breakDurationMinutes, forKey: Keys.breakDurationMinutes) }
    }

    @Published var breakSnoozeMinutes: Int {
        didSet { defaults.set(breakSnoozeMinutes, forKey: Keys.breakSnoozeMinutes) }
    }

    private let defaults = UserDefaults.standard

    init() {
        Self.migrateLegacyDefaultsIfNeeded(to: defaults)

        codexPath = defaults.string(forKey: Keys.codexPath) ?? "\(NSHomeDirectory())/.codex"
        includeArchivedSessions = defaults.object(forKey: Keys.includeArchivedSessions) as? Bool ?? true
        language = defaults.string(forKey: Keys.language) ?? "en"
        startupScanDays = defaults.object(forKey: Keys.startupScanDays) as? Int ?? 7
        showEstimatedCost = defaults.object(forKey: Keys.showEstimatedCost) as? Bool ?? true
        showReasoningTokens = defaults.object(forKey: Keys.showReasoningTokens) as? Bool ?? true
        defaultRange = UsageRange(rawValue: defaults.string(forKey: Keys.defaultRange) ?? "") ?? .today
        breakReminderEnabled = defaults.object(forKey: Keys.breakReminderEnabled) as? Bool ?? false
        breakReminderMode = BreakReminderMode(rawValue: defaults.string(forKey: Keys.breakReminderMode) ?? "") ?? .reminder
        breakWorkMinutes = Self.clamped(defaults.object(forKey: Keys.breakWorkMinutes) as? Int ?? 50, in: 1...240)
        breakDurationMinutes = Self.clamped(defaults.object(forKey: Keys.breakDurationMinutes) as? Int ?? 10, in: 1...120)
        breakSnoozeMinutes = Self.clamped(defaults.object(forKey: Keys.breakSnoozeMinutes) as? Int ?? 10, in: 1...120)
    }

    func localized(_ key: String) -> String {
        L10n.text(key, language: language)
    }

    private static func clamped(_ value: Int, in range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func migrateLegacyDefaultsIfNeeded(to defaults: UserDefaults) {
        guard Bundle.main.bundleIdentifier == "com.songcbo.CodexUsage.App",
              defaults.object(forKey: Keys.legacyDefaultsMigrated) == nil,
              let legacyDefaults = UserDefaults(suiteName: "com.songcbo.CodexUsage")
        else { return }

        for key in Keys.migratedKeys where defaults.object(forKey: key) == nil {
            if let value = legacyDefaults.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: Keys.legacyDefaultsMigrated)
    }

    private enum Keys {
        static let codexPath = "codexPath"
        static let includeArchivedSessions = "includeArchivedSessions"
        static let language = "language"
        static let startupScanDays = "startupScanDays"
        static let showEstimatedCost = "showEstimatedCost"
        static let showReasoningTokens = "showReasoningTokens"
        static let defaultRange = "defaultRange"
        static let breakReminderEnabled = "breakReminderEnabled"
        static let breakReminderMode = "breakReminderMode"
        static let breakWorkMinutes = "breakWorkMinutes"
        static let breakDurationMinutes = "breakDurationMinutes"
        static let breakSnoozeMinutes = "breakSnoozeMinutes"
        static let legacyDefaultsMigrated = "legacyDefaultsMigratedFromComSongcboCodexUsage"

        static let migratedKeys = [
            codexPath,
            includeArchivedSessions,
            language,
            startupScanDays,
            showEstimatedCost,
            showReasoningTokens,
            defaultRange,
            breakReminderEnabled,
            breakReminderMode,
            breakWorkMinutes,
            breakDurationMinutes,
            breakSnoozeMinutes
        ]
    }
}
