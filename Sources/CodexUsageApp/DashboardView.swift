import AppKit
import Foundation
import SQLite3
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var model: UsageViewModel
    @State private var isRefreshAnimating = false
    @State private var refreshRotation = 0.0

    var body: some View {
        VStack(spacing: 16) {
            header
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    QuotaSnapshotCard()
                    LocalUsageCard()
                    CalendarHeatmapCard()
                }
                .padding(.bottom, 18)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(settings.localized("app.title"))
                    .font(.system(size: 25, weight: .bold))
                if let error = model.lastRefreshError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button {
                playRefreshInteraction()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(refreshRotation))
                    .frame(width: 18, height: 18)
            }
            .help(settings.localized("refresh.title"))
            .buttonStyle(.bordered)
            .disabled(model.isRefreshing || isRefreshAnimating)

            Button {
                SettingsWindowPresenter.shared.show(settings: settings, model: model)
            } label: {
                Image(systemName: "gearshape")
            }
            .help(settings.localized("settings.title"))
            .buttonStyle(.bordered)
        }
    }
    private func playRefreshInteraction() {
        guard !isRefreshAnimating else { return }
        isRefreshAnimating = true
        refreshRotation = 0
        withAnimation(.linear(duration: 1.0)) {
            refreshRotation = 360
        }

        Task {
            let startedAt = Date()
            await model.refreshRecentDays(settings: settings)
            let elapsed = Date().timeIntervalSince(startedAt)
            if elapsed < 1.0 {
                try? await Task.sleep(nanoseconds: UInt64((1.0 - elapsed) * 1_000_000_000))
            }
            await MainActor.run {
                isRefreshAnimating = false
                refreshRotation = 0
            }
        }
    }

}
