import AppKit
import Foundation
import SQLite3
import SwiftUI

enum MenuBarIcon {
    static var image: NSImage {
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        let fallback = NSImage(systemSymbolName: "c.circle", accessibilityDescription: "Codex Usage") ?? NSImage()
        fallback.isTemplate = true
        fallback.size = NSSize(width: 18, height: 18)
        return fallback
    }
}

enum MenuBarStatusItem {
#if DEBUG
    static let autosaveName = "CodexUsageDebugStatusItem"
#else
    static let autosaveName = "CodexUsageMenuBarStatusItem"
#endif
}

@main
struct CodexUsageApp: App {
    @NSApplicationDelegateAdaptor(CodexUsageAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class CodexUsageAppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let model = UsageViewModel()
    private var statusBarController: StatusBarController?
    private var breakReminderController: BreakReminderController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("CodexUsage status item is active")
        statusBarController = StatusBarController(settings: settings, model: model)
        breakReminderController = BreakReminderController(settings: settings)

        Task {
            await model.start(settings: settings)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        breakReminderController?.stop()
    }
}

@MainActor
final class StatusBarController: NSObject {
    private let settings: AppSettings
    private let model: UsageViewModel
    private let statusItem: NSStatusItem
    private let popover: NSPopover

    init(settings: AppSettings, model: UsageViewModel) {
        self.settings = settings
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        popover = NSPopover()
        super.init()

        statusItem.autosaveName = MenuBarStatusItem.autosaveName
        configureStatusItem()
        configurePopover()
    }

    private func configureStatusItem() {
        statusItem.isVisible = true

        guard let button = statusItem.button else { return }
        button.image = MenuBarIcon.image
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = "Codex Usage"
        button.setAccessibilityLabel("Codex Usage")
        button.target = self
        button.action = #selector(togglePopover(_:))
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 380, height: 740)
        popover.contentViewController = NSHostingController(
            rootView: DashboardView()
                .environmentObject(settings)
                .environmentObject(model)
                .frame(width: 380, height: 740)
        )
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }

        model.resetVisibleMonthToCurrent()
        Task {
            await model.refreshOnMenuOpen(settings: settings)
        }
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}


@MainActor
final class SettingsWindowPresenter {
    static let shared = SettingsWindowPresenter()

    private var window: NSWindow?

    private init() {}

    func show(settings: AppSettings, model: UsageViewModel) {
        let rootView = SettingsView()
            .environmentObject(settings)
            .environmentObject(model)

        if let window {
            window.contentView = NSHostingView(rootView: rootView)
            bringToFront(window)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = settings.localized("settings.windowTitle")
        window.minSize = NSSize(width: 620, height: 560)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: rootView)
        window.center()
        self.window = window
        bringToFront(window)
    }

    private func bringToFront(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
