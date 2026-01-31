import AppKit
import SwiftUI

/// Coordinates global app state and controllers
@MainActor
@Observable
public final class AppCoordinator {

    // MARK: - UserDefaults Keys

    private enum DefaultsKeys {
        static let lastSelectedAppBundleID = "lastSelectedAppBundleID"
        static let hasShownPermissionPanel = "hasShownPermissionPanel"
    }

    // MARK: - Controllers

    public let floatingToolbar = FloatingToolbarWindowController()
    private let permissionPanel = PermissionPanelController()

    // MARK: - Shared State

    /// The accessibility inspector shared across the app
    public let inspector = AccessibilityInspector()

    /// The currently selected target app
    public var selectedApp: TargetApp? {
        didSet {
            if let app = selectedApp {
                inspector.setTargetApp(app)
                // Persist the selection
                UserDefaults.standard.set(app.bundleIdentifier, forKey: DefaultsKeys.lastSelectedAppBundleID)
            } else {
                inspector.clearTargetApp()
                UserDefaults.standard.removeObject(forKey: DefaultsKeys.lastSelectedAppBundleID)
            }
            // Stop inspection when app changes (if currently inspecting)
            if overlayController != nil {
                stopInspection()
            }

            // Update toolbar with new app selection
            floatingToolbar.updateSelectedApp(selectedApp)
        }
    }

    /// Whether inspection mode is active (derived from toolbar expanded state)
    public var isInspecting: Bool {
        floatingToolbar.isExpanded && overlayController != nil
    }

    /// The overlay controller (created when inspection starts)
    public private(set) var overlayController: OverlayWindowController?

    /// Convenience access to the annotation store from the overlay
    public var annotationStore: AnnotationStore? {
        overlayController?.annotationStore
    }

    // MARK: - Initialization

    public init() {
        setupCallbacks()
    }

    // MARK: - Setup

    private func setupCallbacks() {
        // Floating toolbar expand/collapse callbacks
        floatingToolbar.onExpand = { [weak self] in
            self?.startInspection()
        }

        floatingToolbar.onCollapse = { [weak self] in
            self?.stopInspectionAndReleaseFocus()
        }

        floatingToolbar.onCopyFeedback = { [weak self] in
            self?.copyFeedbackToClipboard()
        }

        floatingToolbar.onClearAnnotations = { [weak self] in
            self?.clearAnnotations()
        }

        floatingToolbar.onAppSelected = { [weak self] app in
            self?.selectedApp = app
        }

        floatingToolbar.onRefreshApps = { [weak self] in
            self?.refreshApps()
        }
    }

    // MARK: - Inspection Control

    private func startInspection() {
        guard let app = selectedApp else {
            // No app selected - collapse toolbar back
            floatingToolbar.isExpanded = false
            return
        }

        // Create overlay (Loupe stays active and owns focus)
        let controller = OverlayWindowController(
            inspector: inspector,
            targetApp: app
        )

        // Register the toolbar window as an exclusion zone so mouse events
        // over the toolbar are passed through instead of being consumed
        if let toolbarWindow = floatingToolbar.window {
            controller.addExclusionWindow(toolbarWindow)
        }

        controller.isInspectionActive = true
        controller.showWindow(nil)
        overlayController = controller

        // Connect toolbar to annotation store for badge updates
        floatingToolbar.setAnnotationStore(controller.annotationStore)
    }

    private func stopInspection() {
        overlayController?.isInspectionActive = false
        overlayController?.close()
        overlayController = nil
    }

    /// Stop inspection and release focus to the target app.
    /// Called when user collapses the toolbar (exits inspection mode).
    private func stopInspectionAndReleaseFocus() {
        stopInspection()

        // NOW release focus to target app
        if let app = selectedApp,
           let runningApp = NSRunningApplication(processIdentifier: app.id) {
            runningApp.activate(options: [])
        }
    }

    // MARK: - Actions

    /// Copy all annotations as markdown to clipboard
    public func copyFeedbackToClipboard() {
        guard let store = annotationStore,
              let app = selectedApp else { return }

        let generator = FeedbackOutputGenerator()
        generator.copyToClipboard(
            annotations: store.annotations,
            appName: app.name,
            bundleIdentifier: app.bundleIdentifier,
            windowTitle: inspector.getTargetWindowTitle()
        )
    }

    /// Clear all annotations
    public func clearAnnotations() {
        annotationStore?.clear()
        floatingToolbar.refreshContent()
    }

    // MARK: - Lifecycle

    /// Show the floating toolbar
    public func showToolbar() {
        floatingToolbar.show()
    }

    /// Refresh running apps list
    public func refreshApps() {
        inspector.refreshRunningApps()
        // Update toolbar with the new app list
        floatingToolbar.updateAvailableApps(inspector.runningApps)
    }

    // MARK: - App Lifecycle (called from AppDelegate)

    /// Show the permission panel for first-time setup
    public func showPermissionPanel() {
        permissionPanel.show { [weak self] in
            self?.startApp()
        }
    }

    /// Start the app after permission is granted
    public func startApp() {
        // Refresh apps and restore last selection
        refreshApps()
        restoreLastSelectedApp()

        // Show the floating toolbar
        showToolbar()

        // Update toolbar with initial state
        floatingToolbar.updateAvailableApps(inspector.runningApps)
        floatingToolbar.updateSelectedApp(selectedApp)
    }

    /// Restore the previously selected app if it's still running
    private func restoreLastSelectedApp() {
        guard let lastBundleID = UserDefaults.standard.string(forKey: DefaultsKeys.lastSelectedAppBundleID) else {
            return
        }

        // Find the app in running apps
        if let matchingApp = inspector.runningApps.first(where: { $0.bundleIdentifier == lastBundleID }) {
            selectedApp = matchingApp
        }
    }

    /// Ensure toolbar is visible (called when app becomes active)
    public func ensureToolbarVisible() {
        if !floatingToolbar.isVisible {
            floatingToolbar.show()
        }
    }

    /// Cleanup before app terminates
    public func cleanup() {
        stopInspection()
        permissionPanel.dismiss()
    }
}
