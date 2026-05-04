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

@main
struct CodexUsageApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var model = UsageViewModel()

    var body: some Scene {
        MenuBarExtra {
            DashboardView()
                .environmentObject(settings)
                .environmentObject(model)
                .frame(width: 380, height: 740)
                .task {
                    await model.start(settings: settings)
                }
                .onAppear {
                    model.resetVisibleMonthToCurrent()
                }
        } label: {
            Image(nsImage: MenuBarIcon.image)
                .accessibilityLabel("Codex Usage")
        }
        .menuBarExtraStyle(.window)
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
