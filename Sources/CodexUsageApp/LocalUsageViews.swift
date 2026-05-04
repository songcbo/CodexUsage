import AppKit
import Foundation
import SQLite3
import SwiftUI

struct LocalUsageCard: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var model: UsageViewModel

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(settings.localized("usage.title"))
                        .font(.headline)
                    Spacer()
                    Picker("", selection: $model.selectedRange) {
                        ForEach(UsageRange.allCases) { range in
                            Text(settings.localized("range.\(range.rawValue)")).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .font(.caption.weight(.semibold))
                    .frame(width: 176)
                }

                HStack(alignment: .firstTextBaseline) {
                    if settings.showEstimatedCost {
                        Text(model.selectedRangeTotals.estimatedCostUSD, format: .currency(code: "USD"))
                            .font(.system(size: 30, weight: .bold))
                    }
                    Spacer()
                    Text("\(model.selectedRangeTotals.runs.formatted()) \(settings.localized("usage.runs"))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 8) {
                    UsageStatRow(title: settings.localized("usage.input"), value: model.selectedRangeTotals.inputTokens, color: .blue)
                    UsageStatRow(title: settings.localized("usage.output"), value: model.selectedRangeTotals.outputTokens, color: .orange)
                    UsageStatRow(title: settings.localized("usage.cached"), value: model.selectedRangeTotals.cachedInputTokens, color: .yellow)
                    if settings.showReasoningTokens {
                        UsageStatRow(title: settings.localized("usage.reasoning"), value: model.selectedRangeTotals.reasoningOutputTokens, color: .purple)
                    }
                }
                UsageStatRow(
                    title: settings.localized("usage.cacheHit"),
                    valueText: model.selectedRangeTotals.cacheHitRate.formatted(.percent.precision(.fractionLength(0))),
                    color: .green
                )
            }
        }
    }

}

struct UsageStatRow: View {
    var title: String
    var value: Int64?
    var valueText: String?
    var color: Color

    init(title: String, value: Int64, color: Color) {
        self.title = title
        self.value = value
        self.valueText = nil
        self.color = color
    }

    init(title: String, valueText: String, color: Color) {
        self.title = title
        self.value = nil
        self.valueText = valueText
        self.color = color
    }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 4, height: 16)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(valueText ?? Formatters.compactTokens(value ?? 0))
                .font(.subheadline.weight(.bold))
        }
    }
}
