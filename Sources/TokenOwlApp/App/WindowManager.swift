import AppKit
import SwiftUI
import TokenOwlCore

/// Manages standalone macOS modal/floating windows for Settings and About,
/// ensuring the widget view popover is closed when they open.
@MainActor
final class WindowManager {

    static let shared = WindowManager()

    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?

    private init() {}

    /// Closes any open widget/popover window so the standalone modal window takes focus cleanly.
    func closeWidgetWindow() {
        for window in NSApp.windows where window.isVisible {
            if window == settingsWindow || window == aboutWindow {
                continue
            }
            let name = window.className
            if name.contains("StatusItem") || name.contains("StatusBar") {
                continue
            }
            window.orderOut(nil)
        }
    }

    func openSettings(store: QuotaStore) {
        closeWidgetWindow()

        if let window = settingsWindow, window.isVisible {
            bringToFrontAndFocus(window)
            return
        }

        let preferencesView = PreferencesView { [weak self] in
            self?.closeSettings()
        }
        .environment(store)

        let hostingController = NSHostingController(rootView: preferencesView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "TokenOwl Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(NSWindow.Level.popUpMenu.rawValue + 5)
        window.center()

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkRestoreAccessoryPolicy()
            }
        }

        self.settingsWindow = window
        bringToFrontAndFocus(window)
    }

    func closeSettings() {
        settingsWindow?.close()
        checkRestoreAccessoryPolicy()
    }

    func openAbout(store: QuotaStore? = nil) {
        closeWidgetWindow()

        if let window = aboutWindow, window.isVisible {
            bringToFrontAndFocus(window)
            return
        }

        let aboutView = AboutView { [weak self] in
            self?.closeAbout()
        }
        .environment(store)

        let hostingController = NSHostingController(rootView: aboutView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "About TokenOwl"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(NSWindow.Level.popUpMenu.rawValue + 5)
        window.center()

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkRestoreAccessoryPolicy()
            }
        }

        self.aboutWindow = window
        bringToFrontAndFocus(window)
    }

    func closeAbout() {
        aboutWindow?.close()
        checkRestoreAccessoryPolicy()
    }

    private func bringToFrontAndFocus(_ window: NSWindow) {
        // Switch to regular activation policy so macOS grants full foreground keyboard and window focus
        NSApp.setActivationPolicy(.regular)
        window.level = NSWindow.Level(NSWindow.Level.popUpMenu.rawValue + 5)
        window.center()
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func checkRestoreAccessoryPolicy() {
        let hasOpenWindows = (settingsWindow?.isVisible == true) || (aboutWindow?.isVisible == true)
        if !hasOpenWindows {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
