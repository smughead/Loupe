import AppKit
import SwiftUI

// MARK: - View

struct ToolbarTipView: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your Loupe Toolbar")
                    .font(.system(size: 13, weight: .semibold))

                Text("Loupe lives here as a floating toolbar. Click the icon to start inspecting any app.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 260)
        .loupeGlassBackground(cornerRadius: 10)
    }
}

// MARK: - Window Controller

@MainActor
public final class ToolbarTipWindowController {

    private var window: NSWindow?

    private static let hasShownKey = "loupe.hasShownToolbarTip"

    public init() {}

    /// Show the tooltip above the toolbar if it hasn't been shown before.
    public func showIfNeeded(relativeTo toolbarWindow: NSWindow) {
        guard !UserDefaults.standard.bool(forKey: Self.hasShownKey) else { return }

        let tipView = ToolbarTipView { [weak self] in
            self?.dismiss()
        }

        let hostingView = NSHostingView(rootView: tipView)
        hostingView.setFrameSize(hostingView.fittingSize)

        let tipWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        tipWindow.contentView = hostingView
        tipWindow.isOpaque = false
        tipWindow.backgroundColor = .clear
        tipWindow.hasShadow = true
        tipWindow.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        tipWindow.isReleasedWhenClosed = false

        // Position: right-aligned above the toolbar with a 12px gap
        let toolbarFrame = toolbarWindow.frame
        let tipSize = hostingView.fittingSize

        var tipOrigin = NSPoint(
            x: toolbarFrame.maxX - tipSize.width,
            y: toolbarFrame.maxY + 12
        )

        // Screen clamping: if it would go off the top, place below instead
        if let screen = toolbarWindow.screen ?? NSScreen.main {
            let screenTop = screen.visibleFrame.maxY
            if tipOrigin.y + tipSize.height > screenTop {
                tipOrigin.y = toolbarFrame.minY - tipSize.height - 12
            }
        }

        tipWindow.setFrameOrigin(tipOrigin)
        tipWindow.alphaValue = 0
        tipWindow.orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            tipWindow.animator().alphaValue = 1
        }

        self.window = tipWindow
        UserDefaults.standard.set(true, forKey: Self.hasShownKey)
    }

    /// Dismiss the tooltip with a fade-out animation.
    public func dismiss() {
        guard let window else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.window?.close()
                self?.window = nil
            }
        })
    }
}
