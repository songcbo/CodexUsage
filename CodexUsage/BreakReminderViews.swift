import AppKit
import Foundation
import SwiftUI

struct BreakReminderPromptView: View {
    @EnvironmentObject private var settings: AppSettings

    var pet: PetSpritesheet
    var onStartRest: () -> Void
    var onSnooze: () -> Void
    var onSkip: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                Image(nsImage: pet.frame(row: 0, column: 0))
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 104, height: 112)

                VStack(alignment: .leading, spacing: 8) {
                    Text(settings.localized("break.title"))
                        .font(.system(size: 25, weight: .bold))
                    Text(String(format: settings.localized("break.subtitle"), settings.breakWorkMinutes))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if pet.isFallback {
                        Text(settings.localized("break.petMissing"))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button {
                    onStartRest()
                } label: {
                    Text(settings.localized("break.start"))
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)

                Button {
                    onSnooze()
                } label: {
                    Text(settings.localized("break.snooze"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    onSkip()
                } label: {
                    Text(settings.localized("break.skip"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(22)
        .frame(width: 420, height: 240)
        .background(.regularMaterial)
    }
}

struct BreakRestOverlayView: View {
    @EnvironmentObject private var settings: AppSettings

    var endDate: Date
    var pet: PetSpritesheet
    var onExit: () -> Void

    @State private var animationRow = Int.random(in: 0..<PetSpritesheet.rows)
    @State private var animationColumn = 0

    private let animationTimer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.86),
                    Color(red: 0.04, green: 0.08, blue: 0.12).opacity(0.9)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()

                Image(nsImage: pet.frame(row: animationRow, column: animationColumn))
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 220, height: 238)
                    .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 16)

                Text(remainingText)
                    .font(.system(size: 80, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)

                Text(settings.localized("break.title"))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.86))

                if pet.isFallback {
                    Text(settings.localized("break.petMissing"))
                        .font(.callout)
                        .foregroundStyle(.orange)
                }

                Spacer()
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        onExit()
                    } label: {
                        Text(settings.localized("break.exit"))
                            .font(.body.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .padding(26)
                }
                Spacer()
                Text(settings.localized("break.escToExit"))
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.bottom, 28)
            }
        }
        .onReceive(animationTimer) { _ in
            advanceAnimation()
        }
    }

    private var remainingText: String {
        let seconds = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func advanceAnimation() {
        let nextColumn = (animationColumn + 1) % PetSpritesheet.columns
        animationColumn = nextColumn
        if nextColumn == 0 {
            animationRow = Self.randomRow(excluding: animationRow)
        }
    }

    private static func randomRow(excluding current: Int) -> Int {
        guard PetSpritesheet.rows > 1 else { return current }
        var next = Int.random(in: 0..<PetSpritesheet.rows)
        if next == current {
            next = (next + 1) % PetSpritesheet.rows
        }
        return next
    }
}
