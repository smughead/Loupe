import AppKit
import SwiftUI

/// Controller for the one-time accessibility permission panel
@MainActor
public final class PermissionPanelController {

    private var panel: NSPanel?
    private var onPermissionGranted: (() -> Void)?
    private var permissionCheckTimer: Timer?

    public init() {}

    /// Show the permission panel
    public func show(onPermissionGranted: @escaping () -> Void) {
        self.onPermissionGranted = onPermissionGranted

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 340),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.title = "Loupe Needs Permission"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let contentView = PermissionPanelView(
            onOpenSettings: { [weak self] in
                self?.openSystemSettings()
            },
            onCheckPermission: { [weak self] in
                self?.checkPermissionAndClose()
            }
        )

        panel.contentView = NSHostingView(rootView: contentView)
        panel.center()

        self.panel = panel
        panel.makeKeyAndOrderFront(nil)

        // Start polling for permission changes
        startPermissionPolling()
    }

    /// Dismiss the permission panel
    public func dismiss() {
        stopPermissionPolling()
        panel?.close()
        panel = nil
    }

    private func openSystemSettings() {
        // Open System Settings to Accessibility pane
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func checkPermissionAndClose() {
        if AXIsProcessTrusted() {
            dismiss()
            onPermissionGranted?()
        }
    }

    private func startPermissionPolling() {
        // Poll every second to detect when permission is granted
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkPermissionAndClose()
            }
        }
    }

    private func stopPermissionPolling() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }
}

// MARK: - Permission Panel SwiftUI View

struct PermissionPanelView: View {
    let onOpenSettings: () -> Void
    let onCheckPermission: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            // Icon
            Image(systemName: "hand.raised.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue)
                .padding(.top, 20)

            // Title
            Text("Accessibility Permission Required")
                .font(.title2)
                .fontWeight(.semibold)

            // Description
            Text("Loupe needs Accessibility permission to inspect UI elements in other applications.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            // Instructions
            VStack(alignment: .leading, spacing: 8) {
                instructionRow(number: "1", text: "Click the button below to open System Settings")
                instructionRow(number: "2", text: "Find **Loupe** in the list and toggle it on")
                instructionRow(number: "3", text: "This window will close automatically")
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.1))
            )
            .padding(.horizontal, 24)

            Spacer()

            // Single button
            Button {
                onOpenSettings()
            } label: {
                Label("Open System Settings", systemImage: "gear")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(width: 420, height: 340)
    }

    private func instructionRow(number: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(.blue))

            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
        }
    }
}
