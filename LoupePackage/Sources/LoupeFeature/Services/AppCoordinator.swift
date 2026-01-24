import AppKit
import SwiftUI

/// Coordinates global app state and controllers
@MainActor
@Observable
public final class AppCoordinator {

    // MARK: - Controllers

    public let menuBarController = MenuBarController()
    public let floatingToolbar = FloatingToolbarWindowController()

    // MARK: - Shared State

    /// The accessibility inspector shared across the app
    public let inspector = AccessibilityInspector()

    /// The currently selected target app
    public var selectedApp: TargetApp? {
        didSet {
            if let app = selectedApp {
                inspector.setTargetApp(app)
            } else {
                inspector.clearTargetApp()
            }
            // Reset inspection state when app changes
            isInspecting = false
        }
    }

    /// Whether inspection mode is active
    public var isInspecting = false {
        didSet {
            guard isInspecting != oldValue else { return }

            if isInspecting {
                startInspection()
            } else {
                stopInspection()
            }

            // Update toolbar state
            floatingToolbar.isInspecting = isInspecting

            // Update menu bar icon
            menuBarController.isInspecting = isInspecting
        }
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
        // Menu bar click toggles floating toolbar visibility
        menuBarController.onToggle = { [weak self] in
            self?.floatingToolbar.toggleVisibility()
        }

        // Floating toolbar callbacks
        floatingToolbar.onInspectionToggle = { [weak self] inspecting in
            self?.isInspecting = inspecting
        }

        floatingToolbar.onCopyFeedback = { [weak self] in
            self?.copyFeedbackToClipboard()
        }

        floatingToolbar.onClearAnnotations = { [weak self] in
            self?.clearAnnotations()
        }

        floatingToolbar.onClose = { [weak self] in
            self?.isInspecting = false
        }
    }

    // MARK: - Inspection Control

    private func startInspection() {
        guard let app = selectedApp else { return }

        let controller = OverlayWindowController(
            inspector: inspector,
            targetApp: app
        )
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
    }
}
