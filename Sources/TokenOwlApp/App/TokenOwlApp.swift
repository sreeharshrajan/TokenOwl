import AppKit
import SwiftUI
import TokenOwlCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let store = QuotaStore()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Menu-bar-only MVP: no Dock icon.
        _ = NSApplication.shared.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) { store.stop() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = NSApplication.shared.setActivationPolicy(.accessory)
        store.start()
    }
}

@main
struct TokenOwlApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appDelegate.store)
        } label: {
            Text(appDelegate.store.menuBarLabel)
        }
        .menuBarExtraStyle(.window)
    }
}
