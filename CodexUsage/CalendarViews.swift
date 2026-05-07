import AppKit
import Foundation
import SQLite3
import SwiftUI

struct CalendarHeatmapCard: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var model: UsageViewModel
    @State private var selectedDay: String?
    @State private var displayMode: CalendarDisplayMode = .tokens

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button {
                        model.visibleMonth = Calendar.current.date(byAdding: .month, value: -1, to: model.visibleMonth) ?? model.visibleMonth
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.plain)

                    Text(monthTitle)
                        .font(.headline)

                    Button {
                        model.visibleMonth = Calendar.current.date(byAdding: .month, value: 1, to: model.visibleMonth) ?? model.visibleMonth
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Picker("", selection: $displayMode) {
                        ForEach(CalendarDisplayMode.allCases) { mode in
                            Text(settings.localized("calendar.mode.\(mode.rawValue)")).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .font(.caption.weight(.semibold))
                    .frame(width: 176)
                }

                CalendarGrid(selectedDay: $selectedDay, displayMode: displayMode)

                if let selectedDay, let usage = model.usage(for: selectedDay) {
                    HStack {
                        Text(selectedDay)
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text(detailText(for: usage))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        formatter.locale = settings.language == "zh-Hans" ? Locale(identifier: "zh_Hans") : Locale(identifier: "en_US")
        return formatter.string(from: model.visibleMonth)
    }

    private func detailText(for usage: DailyUsage) -> String {
        switch displayMode {
        case .tokens:
            return "\(settings.localized("calendar.totalTokens")): \(Formatters.compactTokens(usage.totals.totalTokens))"
        case .cost:
            return "\(settings.localized("calendar.totalCost")): \(Formatters.compactUSD(usage.totals.estimatedCostUSD))"
        case .all:
            return "\(settings.localized("calendar.totalTokens")): \(Formatters.compactTokens(usage.totals.totalTokens)) · \(settings.localized("calendar.totalCost")): \(Formatters.compactUSD(usage.totals.estimatedCostUSD))"
        }
    }
}

struct CalendarGrid: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var model: UsageViewModel
    @Binding var selectedDay: String?
    var displayMode: CalendarDisplayMode

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(height: 18)
            }
            ForEach(Array(monthCells.enumerated()), id: \.offset) { _, day in
                if let day {
                    let usage = model.usage(for: day)
                    Button {
                        selectedDay = day
                    } label: {
                        VStack(spacing: 2) {
                            Text(String(Int(day.suffix(2)) ?? 0))
                                .font(.caption2.weight(.bold))
                            if let usage {
                                ForEach(cellLines(for: usage), id: \.self) { line in
                                    Text(line)
                                        .font(.system(size: displayMode == .all ? 8 : 9, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.65)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(cellColor(for: usage), in: RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(selectedDay == day ? Color.accentColor : .clear, lineWidth: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                } else {
                    Color.clear.frame(height: 40)
                }
            }
        }
    }

    private var weekdaySymbols: [String] {
        settings.language == "zh-Hans"
        ? ["日", "一", "二", "三", "四", "五", "六"]
        : ["S", "M", "T", "W", "T", "F", "S"]
    }

    private var monthCells: [String?] {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: model.visibleMonth)
        guard let firstDay = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: firstDay) else {
            return []
        }
        let leading = calendar.component(.weekday, from: firstDay) - 1
        let formatter = Formatters.dayFormatter
        var cells = Array<String?>(repeating: nil, count: leading)
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDay) {
                cells.append(formatter.string(from: date))
            }
        }
        while cells.count % 7 != 0 {
            cells.append(nil)
        }
        return cells
    }

    private func cellLines(for usage: DailyUsage) -> [String] {
        switch displayMode {
        case .tokens:
            return [Formatters.compactTokens(usage.totals.totalTokens)]
        case .cost:
            return [Formatters.compactUSD(usage.totals.estimatedCostUSD)]
        case .all:
            return [
                Formatters.compactTokens(usage.totals.totalTokens),
                Formatters.compactUSD(usage.totals.estimatedCostUSD)
            ]
        }
    }

    private func cellColor(for usage: DailyUsage?) -> Color {
        guard let usage else {
            return Color.secondary.opacity(0.12)
        }
        let value: Double
        switch displayMode {
        case .tokens, .all:
            value = Double(usage.totals.totalTokens)
        case .cost:
            value = usage.totals.estimatedCostUSD * 1_000_000
        }
        let intensity = min(1, max(0.18, log10(value + 1) / 8))
        return Color.teal.opacity(intensity)
    }
}

enum CalendarDisplayMode: String, CaseIterable, Identifiable {
    case tokens
    case cost
    case all

    var id: String { rawValue }
}
