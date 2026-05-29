import AppKit
import Foundation
import SQLite3
import SwiftUI

enum Formatters {
    static func compactTokens(_ value: Int64) -> String {
        let absValue = abs(value)
        if absValue >= 1_000_000_000 {
            return String(format: "%.1fb", Double(value) / 1_000_000_000)
        }
        if absValue >= 1_000_000 {
            return String(format: "%.1fm", Double(value) / 1_000_000)
        }
        if absValue >= 1_000 {
            return String(format: "%.1fk", Double(value) / 1_000)
        }
        return value.formatted()
    }

    static func compactUSD(_ value: Double) -> String {
        if value >= 1_000 {
            return String(format: "$%.1fk", value / 1_000)
        }
        if value >= 10 {
            return String(format: "$%.1f", value)
        }
        if value >= 0.01 {
            return String(format: "$%.2f", value)
        }
        if value > 0 {
            return "<$0.01"
        }
        return "$0.00"
    }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

enum L10n {
    static func text(_ key: String, language: String) -> String {
        let resolved = resolve(language)
        return strings[resolved]?[key] ?? strings["en"]?[key] ?? key
    }

    private static func resolve(_ language: String) -> String {
        if language == "zh-Hans" || language == "en" {
            return language
        }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("zh") ? "zh-Hans" : "en"
    }

    private static let strings: [String: [String: String]] = [
        "en": [
            "app.title": "Codex Usage",
            "refresh.title": "Refresh",
            "settings.title": "Settings",
            "settings.windowTitle": "CodexUsage Settings",
            "settings.windowSubtitle": "Local-first Codex usage monitor. No login required.",
            "quota.title": "Quota Snapshot",
            "quota.primary": "5h window",
            "quota.secondary": "Weekly",
            "quota.updated.none": "No local quota snapshot",
            "quota.updated.local": "Updated from local logs",
            "quota.empty.title": "No quota snapshot",
            "quota.empty.detail": "Run Codex once to update local logs.",
            "quota.resetsIn": "Resets in",
            "usage.title": "Local Usage",
            "usage.input": "Input",
            "usage.output": "Output",
            "usage.cached": "Cached",
            "usage.reasoning": "Reasoning",
            "usage.cacheHit": "Cache hit rate",
            "usage.runs": "runs",
            "usage.used": "used",
            "usage.remaining": "remaining",
            "calendar.totalTokens": "Total tokens",
            "calendar.totalCost": "Cost",
            "calendar.mode.tokens": "Token",
            "calendar.mode.cost": "Cost",
            "calendar.mode.all": "All",
            "range.today": "Today",
            "range.sevenDays": "7d",
            "range.thirtyDays": "30d",
            "range.all": "All",
            "settings.dataSource": "Data Source",
            "settings.codexPath": "Codex data path",
            "settings.includeArchived": "Include archived sessions",
            "settings.includeArchived.detail": "Include JSONL files moved into archived_sessions.",
            "settings.rebuildAll": "Rebuild all usage data",
            "settings.openFolder": "Open Codex Folder",
            "settings.refresh": "Refresh",
            "settings.startupScan": "Startup scan range",
            "settings.scan7d": "7 days",
            "settings.scan30d": "30 days",
            "settings.scanAll": "All history",
            "settings.refreshBehavior": "The app refreshes today's usage when the menu opens. The toolbar refresh button recalculates the last 7 days.",
            "settings.breakReminder": "Break Reminder",
            "settings.breakReminder.enabled": "Enable break reminder",
            "settings.breakReminder.enabled.detail": "Default is off. Idle for 10 minutes counts as a completed break.",
            "settings.breakReminder.mode": "Mode",
            "settings.breakReminder.mode.reminder": "Reminder",
            "settings.breakReminder.mode.force": "Force",
            "settings.breakReminder.work": "Work interval",
            "settings.breakReminder.duration": "Break duration",
            "settings.breakReminder.snooze": "Snooze",
            "settings.breakReminder.pet": "Pet",
            "settings.breakReminder.pet.detail": "Uses the Codex pet asset from pets/lovely.",
            "settings.minutes": "min",
            "settings.display": "Display",
            "settings.language": "Language",
            "settings.defaultRange": "Default range",
            "settings.showCost": "Show estimated cost",
            "settings.showReasoning": "Show reasoning tokens",
            "settings.privacy": "Privacy",
            "settings.privacyDetail": "The app only parses token metadata from local Codex JSONL files. It does not display prompts or model responses.",
            "settings.quit": "Quit CodexUsage",
            "break.title": "Take a break",
            "break.subtitle": "You have focused for %d minutes",
            "break.start": "Start break",
            "break.snooze": "Snooze",
            "break.skip": "Skip once",
            "break.exit": "Exit",
            "break.escToExit": "Esc to exit",
            "break.petMissing": "lovely pet asset is missing; using fallback."
        ],
        "zh-Hans": [
            "app.title": "Codex 用量",
            "refresh.title": "刷新",
            "settings.title": "设置",
            "settings.windowTitle": "CodexUsage 设置",
            "settings.windowSubtitle": "本地优先的 Codex 用量监测工具，无需登录。",
            "quota.title": "额度快照",
            "quota.primary": "5 小时窗口",
            "quota.secondary": "每周额度",
            "quota.updated.none": "没有本地额度快照",
            "quota.updated.local": "来自本地日志",
            "quota.empty.title": "暂无额度快照",
            "quota.empty.detail": "运行一次 Codex 后会更新本地日志。",
            "quota.resetsIn": "重置于",
            "usage.title": "本地用量",
            "usage.input": "输入",
            "usage.output": "输出",
            "usage.cached": "缓存",
            "usage.reasoning": "推理",
            "usage.cacheHit": "缓存命中率",
            "usage.runs": "次运行",
            "usage.used": "已用",
            "usage.remaining": "剩余",
            "calendar.totalTokens": "总 Token",
            "calendar.totalCost": "费用",
            "calendar.mode.tokens": "Token",
            "calendar.mode.cost": "费用",
            "calendar.mode.all": "全部",
            "range.today": "今天",
            "range.sevenDays": "7 天",
            "range.thirtyDays": "30 天",
            "range.all": "全部",
            "settings.dataSource": "数据来源",
            "settings.codexPath": "Codex 数据路径",
            "settings.includeArchived": "包含归档会话",
            "settings.includeArchived.detail": "包含已移动到 archived_sessions 的 JSONL 文件。",
            "settings.rebuildAll": "重建全部用量数据",
            "settings.openFolder": "打开 Codex 文件夹",
            "settings.refresh": "刷新",
            "settings.startupScan": "启动扫描范围",
            "settings.scan7d": "7 天",
            "settings.scan30d": "30 天",
            "settings.scanAll": "全部历史",
            "settings.refreshBehavior": "点开菜单时会刷新今天的用量；顶部刷新按钮会重算最近 7 天。",
            "settings.breakReminder": "休息提醒",
            "settings.breakReminder.enabled": "启用休息提醒",
            "settings.breakReminder.enabled.detail": "默认关闭。空闲达到 10 分钟会视为已经休息。",
            "settings.breakReminder.mode": "模式",
            "settings.breakReminder.mode.reminder": "提醒",
            "settings.breakReminder.mode.force": "强制",
            "settings.breakReminder.work": "工作间隔",
            "settings.breakReminder.duration": "休息时长",
            "settings.breakReminder.snooze": "稍后提醒",
            "settings.breakReminder.pet": "当前 pet",
            "settings.breakReminder.pet.detail": "使用 Codex 的 pets/lovely 资产。",
            "settings.minutes": "分钟",
            "settings.display": "显示",
            "settings.language": "语言",
            "settings.defaultRange": "默认范围",
            "settings.showCost": "显示预估费用",
            "settings.showReasoning": "显示推理 token",
            "settings.privacy": "隐私",
            "settings.privacyDetail": "应用只解析本地 Codex JSONL 文件中的 token 元数据，不展示提示词或模型回复内容。",
            "settings.quit": "退出 CodexUsage",
            "break.title": "休息一下",
            "break.subtitle": "你已经专注工作 %d 分钟",
            "break.start": "开始休息",
            "break.snooze": "稍后提醒",
            "break.skip": "跳过一次",
            "break.exit": "Exit",
            "break.escToExit": "Esc to exit",
            "break.petMissing": "lovely pet 资产缺失，当前使用占位图。"
        ]
    ]
}
