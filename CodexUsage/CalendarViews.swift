import AppKit
import Foundation
import SQLite3
import SwiftUI

struct CalendarHeatmapCard: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var model: UsageViewModel
    @State private var selectedDay: String?

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
                }

                CalendarGrid(selectedDay: $selectedDay)

                if let selectedDay, let usage = model.usage(for: selectedDay) {
                    HStack {
                        Text(selectedDay)
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text("\(settings.localized("calendar.totalTokens")): \(Formatters.compactTokens(usage.totals.totalTokens))")
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
}

struct CalendarGrid: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var model: UsageViewModel
    @Binding var selectedDay: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(height: 18)
            }
            ForEach(monthCells, id: \.self) { day in
                if let day {
                    let usage = model.usage(for: day)
                    Button {
                        selectedDay = day
                    } label: {
                        VStack(spacing: 2) {
                            Text(String(Int(day.suffix(2)) ?? 0))
                                .font(.caption2.weight(.bold))
                            Text(usage.map { Formatters.compactTokens($0.totals.totalTokens) } ?? "")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, minHeight: 40)
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

    private func cellColor(for usage: DailyUsage?) -> Color {
        guard let usage else {
            return Color.secondary.opacity(0.12)
        }
        let value = Double(usage.totals.totalTokens)
        let intensity = min(1, max(0.18, log10(value + 1) / 8))
        return Color.teal.opacity(intensity)
    }
}
