import AppKit
import Foundation
import SQLite3
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var model: UsageViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                SettingsSection(title: settings.localized("settings.dataSource"), systemImage: "folder") {
                    SettingsTextFieldRow(
                        title: settings.localized("settings.codexPath"),
                        text: $settings.codexPath
                    )
                    SettingsToggleRow(
                        title: settings.localized("settings.includeArchived"),
                        detail: settings.localized("settings.includeArchived.detail"),
                        isOn: $settings.includeArchivedSessions
                    )
                    HStack(spacing: 10) {
                        Button {
                            Task { await model.rebuildAll(settings: settings) }
                        } label: {
                            Label(settings.localized("settings.rebuildAll"), systemImage: "arrow.triangle.2.circlepath")
                        }
                        Button {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: settings.codexPath)
                        } label: {
                            Label(settings.localized("settings.openFolder"), systemImage: "arrow.up.right.square")
                        }
                    }
                    .buttonStyle(.bordered)
                }

                SettingsSection(title: settings.localized("settings.refresh"), systemImage: "arrow.clockwise") {
                    SettingsPickerRow(title: settings.localized("settings.startupScan")) {
                        Picker("", selection: $settings.startupScanDays) {
                            Text(settings.localized("settings.scan7d")).tag(7)
                            Text(settings.localized("settings.scan30d")).tag(30)
                            Text(settings.localized("settings.scanAll")).tag(0)
                        }
                        .frame(width: 180)
                    }
                    Text(settings.localized("settings.refreshBehavior"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 10)
                }

                SettingsSection(title: settings.localized("settings.breakReminder"), systemImage: "figure.mind.and.body") {
                    SettingsToggleRow(
                        title: settings.localized("settings.breakReminder.enabled"),
                        detail: settings.localized("settings.breakReminder.enabled.detail"),
                        isOn: $settings.breakReminderEnabled
                    )
                    VStack(spacing: 0) {
                        SettingsPickerRow(title: settings.localized("settings.breakReminder.mode")) {
                            Picker("", selection: $settings.breakReminderMode) {
                                Text(settings.localized("settings.breakReminder.mode.reminder")).tag(BreakReminderMode.reminder)
                                Text(settings.localized("settings.breakReminder.mode.force")).tag(BreakReminderMode.force)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 180)
                        }
                        SettingsMinuteInputRow(
                            title: settings.localized("settings.breakReminder.work"),
                            value: $settings.breakWorkMinutes,
                            range: 1...240,
                            suffix: settings.localized("settings.minutes")
                        )
                        SettingsMinuteInputRow(
                            title: settings.localized("settings.breakReminder.duration"),
                            value: $settings.breakDurationMinutes,
                            range: 1...120,
                            suffix: settings.localized("settings.minutes")
                        )
                        SettingsMinuteInputRow(
                            title: settings.localized("settings.breakReminder.snooze"),
                            value: $settings.breakSnoozeMinutes,
                            range: 1...120,
                            suffix: settings.localized("settings.minutes")
                        )
                        SettingsValueRow(
                            title: settings.localized("settings.breakReminder.pet"),
                            detail: settings.localized("settings.breakReminder.pet.detail"),
                            value: "lovely"
                        )
                    }
                    .disabled(!settings.breakReminderEnabled)
                    .opacity(settings.breakReminderEnabled ? 1 : 0.55)
                }

                SettingsSection(title: settings.localized("settings.display"), systemImage: "rectangle.3.group") {
                    SettingsPickerRow(title: settings.localized("settings.language")) {
                        Picker("", selection: $settings.language) {
                            Text("System").tag("system")
                            Text("English").tag("en")
                            Text("简体中文").tag("zh-Hans")
                        }
                        .frame(width: 180)
                    }
                    SettingsPickerRow(title: settings.localized("settings.defaultRange")) {
                        Picker("", selection: $settings.defaultRange) {
                            ForEach(UsageRange.allCases) { range in
                                Text(settings.localized("range.\(range.rawValue)")).tag(range)
                            }
                        }
                        .frame(width: 180)
                    }
                    SettingsToggleRow(title: settings.localized("settings.showCost"), detail: nil, isOn: $settings.showEstimatedCost)
                    SettingsToggleRow(title: settings.localized("settings.showReasoning"), detail: nil, isOn: $settings.showReasoningTokens)
                }

                SettingsSection(title: settings.localized("settings.privacy"), systemImage: "lock.shield") {
                    Text(settings.localized("settings.privacyDetail"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 620, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(settings.localized("settings.windowTitle"))
                .font(.system(size: 28, weight: .bold))
            Text(settings.localized("settings.windowSubtitle"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

struct SettingsSection<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.separator.opacity(0.45), lineWidth: 1)
            }
        }
    }
}

struct SettingsTextFieldRow: View {
    var title: String
    @Binding var text: String

    var body: some View {
        SettingsRow(title: title, detail: nil) {
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 320)
        }
    }
}

struct SettingsToggleRow: View {
    var title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, detail: detail) {
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

struct SettingsPickerRow<Control: View>: View {
    var title: String
    @ViewBuilder var control: Control

    var body: some View {
        SettingsRow(title: title, detail: nil) {
            control
        }
    }
}

struct SettingsMinuteInputRow: View {
    var title: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var suffix: String

    var body: some View {
        SettingsRow(title: title, detail: nil) {
            HStack(spacing: 8) {
                TextField("", value: clampedValue, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                Text(suffix)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 132, alignment: .trailing)
        }
    }

    private var clampedValue: Binding<Int> {
        Binding(
            get: { value },
            set: { value = Self.clamped($0, in: range) }
        )
    }

    private static func clamped(_ value: Int, in range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

struct SettingsValueRow: View {
    var title: String
    var detail: String?
    var value: String

    var body: some View {
        SettingsRow(title: title, detail: detail) {
            Text(value)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

struct SettingsRow<Control: View>: View {
    var title: String
    var detail: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 24)
            control
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.35)
        }
    }
}
