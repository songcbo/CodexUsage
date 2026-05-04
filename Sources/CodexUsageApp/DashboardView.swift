import AppKit
import Foundation
import SQLite3
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var model: UsageViewModel
    @State private var refreshFeedback: RefreshFeedback = .idle
    @State private var refreshGeneration = 0

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
                RefreshFeedbackIcon(state: refreshFeedback)
                    .frame(width: 18, height: 18)
            }
            .help(settings.localized("refresh.title"))
            .buttonStyle(HeaderIconButtonStyle())

            Button {
                SettingsWindowPresenter.shared.show(settings: settings, model: model)
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 18, height: 18)
            }
            .help(settings.localized("settings.title"))
            .buttonStyle(HeaderIconButtonStyle())
        }
    }
    private func playRefreshInteraction() {
        guard refreshFeedback != .refreshing, !model.isRefreshing else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        withAnimation(.easeOut(duration: 0.12)) {
            refreshFeedback = .refreshing
        }

        Task {
            await model.refreshRecentDays(settings: settings)
            await MainActor.run {
                guard generation == refreshGeneration else { return }
                withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                    refreshFeedback = .done
                }
            }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run {
                guard generation == refreshGeneration, refreshFeedback == .done else { return }
                withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                    refreshFeedback = .idle
                }
            }
        }
    }

    fileprivate enum RefreshFeedback {
        case idle
        case refreshing
        case done
    }

}

private struct RefreshFeedbackIcon: View {
    var state: DashboardView.RefreshFeedback

    var body: some View {
        ZStack {
            Image(systemName: "arrow.clockwise")
                .opacity(state == .done ? 0 : (state == .refreshing ? 0.65 : 1))
                .scaleEffect(state == .refreshing ? 0.92 : (state == .done ? 0.82 : 1))

            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.green)
                .opacity(state == .done ? 1 : 0)
                .scaleEffect(state == .done ? 1 : 0.82)
        }
    }
}
