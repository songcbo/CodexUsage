import AppKit
import Combine
import Foundation
import IOKit
import SwiftUI

@MainActor
final class BreakReminderController {
    private let settings: AppSettings
    private let windowPresenter = BreakReminderWindowPresenter()

    private var settingsCancellable: AnyCancellable?
    private var pollTask: Task<Void, Never>?
    private var workStartedAt: Date?
    private var snoozeUntil: Date?
    private var restEndDate: Date?
    private var isReminderVisible = false
    private var petCodexPath: String?
    private var petSpritesheet: PetSpritesheet?

    init(settings: AppSettings) {
        self.settings = settings
        observeSettings()
        handleSettingsChanged()
    }

    deinit {
        pollTask?.cancel()
    }

    func stop() {
        stopPolling()
        windowPresenter.closeAll()
        resetCycle(closeReminder: false)
        restEndDate = nil
    }

    private func observeSettings() {
        settingsCancellable = settings.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.handleSettingsChanged()
            }
        }
    }

    private func handleSettingsChanged() {
        guard settings.breakReminderEnabled else {
            stop()
            return
        }

        startPollingIfNeeded()
    }

    private func startPollingIfNeeded() {
        guard pollTask == nil else { return }
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func tick(now: Date = Date()) {
        guard settings.breakReminderEnabled else {
            handleSettingsChanged()
            return
        }

        if let restEndDate {
            if now >= restEndDate {
                finishRest()
            }
            return
        }

        let idleSeconds = SystemInputIdleTime.secondsSinceLastInput()
        if idleSeconds >= TimeInterval(AppSettings.idleResetMinutes * 60) {
            resetCycle(closeReminder: true)
            return
        }

        if workStartedAt == nil {
            workStartedAt = now
        }

        if isReminderVisible {
            return
        }

        if let snoozeUntil {
            guard now >= snoozeUntil else { return }
            self.snoozeUntil = nil
            triggerBreak()
            return
        }

        guard let workStartedAt else { return }
        let workSeconds = TimeInterval(settings.breakWorkMinutes * 60)
        if now.timeIntervalSince(workStartedAt) >= workSeconds {
            triggerBreak()
        }
    }

    private func triggerBreak() {
        switch settings.breakReminderMode {
        case .reminder:
            showReminder()
        case .force:
            startRest()
        }
    }

    private func showReminder() {
        guard !isReminderVisible else { return }
        isReminderVisible = true

        windowPresenter.showReminder(
            settings: settings,
            pet: currentPetSpritesheet(),
            onStartRest: { [weak self] in
                self?.startRest()
            },
            onSnooze: { [weak self] in
                self?.snooze()
            },
            onSkip: { [weak self] in
                self?.skipOnce()
            }
        )
    }

    private func startRest() {
        isReminderVisible = false
        snoozeUntil = nil
        windowPresenter.closeReminder()

        let endDate = Date().addingTimeInterval(TimeInterval(settings.breakDurationMinutes * 60))
        restEndDate = endDate
        windowPresenter.showRestWindows(
            settings: settings,
            endDate: endDate,
            pet: currentPetSpritesheet(),
            onExit: { [weak self] in
                self?.finishRest()
            }
        )
    }

    private func snooze() {
        isReminderVisible = false
        windowPresenter.closeReminder()
        snoozeUntil = Date().addingTimeInterval(TimeInterval(settings.breakSnoozeMinutes * 60))
    }

    private func skipOnce() {
        resetCycle(closeReminder: true)
    }

    private func finishRest() {
        restEndDate = nil
        windowPresenter.closeRestWindows()
        resetCycle(closeReminder: true)
    }

    private func resetCycle(closeReminder: Bool) {
        workStartedAt = nil
        snoozeUntil = nil
        isReminderVisible = false
        if closeReminder {
            windowPresenter.closeReminder()
        }
    }

    private func currentPetSpritesheet() -> PetSpritesheet {
        if petCodexPath != settings.codexPath || petSpritesheet == nil {
            petCodexPath = settings.codexPath
            petSpritesheet = PetSpritesheet.load(codexPath: settings.codexPath)
        }
        return petSpritesheet ?? PetSpritesheet.load(codexPath: settings.codexPath)
    }
}

enum SystemInputIdleTime {
    private static let nanosecondsPerSecond: Double = 1_000_000_000

    static func secondsSinceLastInput() -> TimeInterval {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { return 0 }
        defer { IOObjectRelease(service) }

        let property = IORegistryEntryCreateCFProperty(
            service,
            "HIDIdleTime" as CFString,
            kCFAllocatorDefault,
            0
        )
        guard let idleNanoseconds = property?.takeRetainedValue() as? NSNumber else { return 0 }
        return idleNanoseconds.doubleValue / nanosecondsPerSecond
    }
}

@MainActor
private final class BreakReminderWindowPresenter {
    private var reminderWindow: BreakReminderPanel?
    private var restWindows: [BreakRestWindow] = []

    func showReminder(
        settings: AppSettings,
        pet: PetSpritesheet,
        onStartRest: @escaping () -> Void,
        onSnooze: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) {
        closeReminder()

        let rootView = BreakReminderPromptView(
            pet: pet,
            onStartRest: onStartRest,
            onSnooze: onSnooze,
            onSkip: onSkip
        )
        .environmentObject(settings)

        let panel = BreakReminderPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 240),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = settings.localized("break.title")
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: rootView)
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        center(panel)

        reminderWindow = panel
        panel.orderFrontRegardless()
    }

    func showRestWindows(
        settings: AppSettings,
        endDate: Date,
        pet: PetSpritesheet,
        onExit: @escaping () -> Void
    ) {
        closeRestWindows()
        NSApp.activate(ignoringOtherApps: true)

        for screen in NSScreen.screens {
            let rootView = BreakRestOverlayView(endDate: endDate, pet: pet, onExit: onExit)
                .environmentObject(settings)

            let window = BreakRestWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.onEscape = onExit
            window.isReleasedWhenClosed = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.contentView = NSHostingView(rootView: rootView)
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            restWindows.append(window)
        }

        restWindows.last?.makeKeyAndOrderFront(nil)
    }

    func closeReminder() {
        reminderWindow?.orderOut(nil)
        reminderWindow?.close()
        reminderWindow = nil
    }

    func closeRestWindows() {
        for window in restWindows {
            window.orderOut(nil)
            window.close()
        }
        restWindows.removeAll()
    }

    func closeAll() {
        closeReminder()
        closeRestWindows()
    }

    private func center(_ window: NSWindow) {
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        let origin = NSPoint(
            x: screenFrame.midX - window.frame.width / 2,
            y: screenFrame.midY - window.frame.height / 2
        )
        window.setFrameOrigin(origin)
    }
}

private final class BreakReminderPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class BreakRestWindow: NSWindow {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}
