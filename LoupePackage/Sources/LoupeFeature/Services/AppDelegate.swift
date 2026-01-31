import AppKit
import SwiftUI

/// App delegate that manages the toolbar-only app lifecycle.
/// This replaces the traditional WindowGroup approach to avoid creating a main window.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {

    /// The central coordinator for the app
    public let coordinator = AppCoordinator()

    /// Menu bar status item for quick access
    private var statusItem: NSStatusItem?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Configure as agent app (no dock icon initially - we'll show dock presence)
        // Actually, we want dock presence, so we leave activation policy as regular

        // Set up menu bar icon
        setupMenuBarIcon()

        // Check accessibility permission and show appropriate UI
        coordinator.inspector.checkAccessibilityPermission()

        if !coordinator.inspector.isAccessibilityEnabled {
            // Show permission panel on first launch or if permission revoked
            coordinator.showPermissionPanel()
        } else {
            // Permission granted - start normal flow
            coordinator.startApp()
        }
    }

    // MARK: - Menu Bar Setup

    private func setupMenuBarIcon() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "eye.circle", accessibilityDescription: "Loupe")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Loupe", action: #selector(showLoupe), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Loupe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func showLoupe() {
        coordinator.floatingToolbar.show()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Terminate when the toolbar is closed
        return true
    }

    public func applicationWillTerminate(_ notification: Notification) {
        // Cleanup if needed
        coordinator.cleanup()
    }

    public func applicationDidBecomeActive(_ notification: Notification) {
        // Ensure toolbar is visible when app becomes active
        coordinator.ensureToolbarVisible()
    }
}
