import AppKit
import SwiftUI

/// Manages the onboarding window that requests accessibility permission.
/// Uses a normal-level NSWindow (not floating) so the native macOS
/// permission dialog can appear above it naturally.
@MainActor
public final class OnboardingWindowController {

    private var window: NSWindow?
    private var permissionCheckTimer: Timer?
    private var onComplete: (() -> Void)?
    private let state = OnboardingState()

    public init() {}

    // MARK: - Public API

    /// Show the onboarding window.
    /// - Parameter onComplete: Called after the permission-granted animation finishes.
    public func show(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete

        let contentView = OnboardingView(
            state: state,
            onGrantAccess: { [weak self] in
                self?.requestPermission()
            },
            onOpenSettings: { [weak self] in
                self?.openSystemSettings()
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.level = .normal
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: contentView)
        window.center()

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        startPermissionPolling()
    }

    /// Dismiss the onboarding window immediately (e.g., on app termination).
    public func dismiss() {
        stopPermissionPolling()
        window?.close()
        window = nil
    }

    // MARK: - Permission Handling

    private func requestPermission() {
        // Trigger the native macOS accessibility permission dialog.
        // Using the string literal avoids a Swift 6 concurrency warning
        // on the C global kAXTrustedCheckOptionPrompt.
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Polling

    private func startPermissionPolling() {
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkPermission()
            }
        }
    }

    private func stopPermissionPolling() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }

    private func checkPermission() {
        guard AXIsProcessTrusted() else { return }

        stopPermissionPolling()

        // Transition to granted phase with animation
        withAnimation(.easeOut(duration: 0.4)) {
            state.phase = .permissionGranted
        }

        // After a short delay, fade out the window and call onComplete
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.fadeOutAndComplete()
        }
    }

    // MARK: - Fade Out

    private func fadeOutAndComplete() {
        guard let window else {
            onComplete?()
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.4
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.window?.close()
                self?.window = nil
                self?.onComplete?()
            }
        })
    }
}
