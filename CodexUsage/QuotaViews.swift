import AppKit
import Foundation
import SQLite3
import SwiftUI

struct QuotaSnapshotCard: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var model: UsageViewModel

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(settings.localized("quota.title"))
                            .font(.headline)
                        Text(updatedText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let plan = model.latestRateLimit?.planType, !plan.isEmpty {
                        Text(plan.capitalized)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.quaternary, in: Capsule())
                    }
                }

                if model.quotaSnapshots.count > 1 {
                    Picker("", selection: $model.selectedQuotaKey) {
                        ForEach(model.quotaSnapshots, id: \.quotaKey) { snapshot in
                            Text(snapshot.displayName).tag(snapshot.quotaKey as String?)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                }

                if let snapshot = model.latestRateLimit {
                    QuotaRow(
                        title: settings.localized("quota.primary"),
                        usedPercent: snapshot.primaryUsedPercent,
                        resetAt: snapshot.primaryResetsAt,
                        color: .teal
                    )
                    QuotaRow(
                        title: settings.localized("quota.secondary"),
                        usedPercent: snapshot.secondaryUsedPercent,
                        resetAt: snapshot.secondaryResetsAt,
                        color: .pink
                    )
                } else {
                    ContentUnavailableMini(
                        title: settings.localized("quota.empty.title"),
                        detail: settings.localized("quota.empty.detail")
                    )
                }
            }
        }
    }

    private var updatedText: String {
        guard let timestamp = model.latestRateLimit?.timestamp else {
            return settings.localized("quota.updated.none")
        }
        return "\(settings.localized("quota.updated.local")) · \(timestamp.replacingOccurrences(of: "T", with: " ").replacingOccurrences(of: "Z", with: " UTC"))"
    }
}

struct QuotaRow: View {
    @EnvironmentObject private var settings: AppSettings
    var title: String
    var usedPercent: Double
    var resetAt: Int64
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(usedPercent.rounded()))% \(settings.localized("usage.used"))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: usedPercent, total: 100)
                .tint(color)
            HStack {
                Text("\(Int((100 - usedPercent).rounded()))% \(settings.localized("usage.remaining"))")
                Spacer()
                Text(resetText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var resetText: String {
        let resetDate = Date(timeIntervalSince1970: TimeInterval(resetAt))
        let seconds = max(0, Int(resetDate.timeIntervalSinceNow))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 {
            return "\(settings.localized("quota.resetsIn")) \(days)d \(hours)h"
        }
        if hours > 0 {
            return "\(settings.localized("quota.resetsIn")) \(hours)h \(minutes)m"
        }
        return "\(settings.localized("quota.resetsIn")) \(minutes)m"
    }
}
