import SwiftUI
import AppKit

/// Small floating label showing the current element's role and title
public struct ElementLabelView: View {
    let role: String
    let title: String?
    let identifier: String?

    public init(role: String, title: String?, identifier: String?) {
        self.role = role
        self.title = title
        self.identifier = identifier
    }

    public var body: some View {
        HStack(spacing: 4) {
            // Role (simplified, without AX prefix)
            Text(simplifiedRole)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            // Title or identifier if available
            if let displayText = title ?? identifier {
                Text("\"\(displayText)\"")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
        )
    }

    /// Remove "AX" prefix from role for cleaner display
    private var simplifiedRole: String {
        if role.hasPrefix("AX") {
            return String(role.dropFirst(2)).lowercased()
        }
        return role.lowercased()
    }
}

// MARK: - Element Label Window Controller

/// Controller for the floating element label window
@MainActor
public final class ElementLabelWindowController {

    private var window: NSWindow?
    private var hostingView: NSHostingView<ElementLabelView>?

    public init() {}

    /// Show the label near an element frame
    /// - Parameters:
    ///   - element: The accessibility element info
    ///   - highlightFrame: The element's frame in screen coordinates (AppKit coordinate system)
    public func show(for element: AXElementInfo, highlightFrame: CGRect) {
        let labelView = ElementLabelView(
            role: element.role,
            title: element.title,
            identifier: element.identifier
        )

        if window == nil {
            createWindow()
        }

        guard let window = window else { return }

        // Update content
        let hosting = NSHostingView(rootView: labelView)
        hosting.frame = NSRect(x: 0, y: 0, width: 200, height: 24)
        window.contentView = hosting

        // Size to fit content
        let fittingSize = hosting.fittingSize
        let labelSize = NSSize(
            width: min(fittingSize.width + 4, 300),
            height: fittingSize.height + 4
        )

        // Position above the highlight, centered horizontally
        let labelOrigin = NSPoint(
            x: highlightFrame.midX - labelSize.width / 2,
            y: highlightFrame.maxY + 8  // 8px above the element
        )

        // Ensure label stays on screen
        let adjustedOrigin = adjustOriginToScreen(labelOrigin, size: labelSize)

        window.setFrame(NSRect(origin: adjustedOrigin, size: labelSize), display: true)
        window.orderFront(nil)
    }

    /// Hide the label
    public func hide() {
        window?.orderOut(nil)
    }

    /// Update position without recreating content
    public func updatePosition(highlightFrame: CGRect) {
        guard let window = window, window.isVisible else { return }

        let labelSize = window.frame.size
        let labelOrigin = NSPoint(
            x: highlightFrame.midX - labelSize.width / 2,
            y: highlightFrame.maxY + 8
        )

        let adjustedOrigin = adjustOriginToScreen(labelOrigin, size: labelSize)
        window.setFrameOrigin(adjustedOrigin)
    }

    // MARK: - Private

    private func createWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 24),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 1)
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        self.window = window
    }

    private func adjustOriginToScreen(_ origin: NSPoint, size: NSSize) -> NSPoint {
        guard let screen = NSScreen.main else { return origin }

        let screenFrame = screen.visibleFrame
        var adjusted = origin

        // Keep within horizontal bounds
        if adjusted.x < screenFrame.minX {
            adjusted.x = screenFrame.minX + 4
        } else if adjusted.x + size.width > screenFrame.maxX {
            adjusted.x = screenFrame.maxX - size.width - 4
        }

        // Keep within vertical bounds
        if adjusted.y + size.height > screenFrame.maxY {
            // Place below the element if it would go off top
            adjusted.y = origin.y - size.height - 16 - 8
        }
        if adjusted.y < screenFrame.minY {
            adjusted.y = screenFrame.minY + 4
        }

        return adjusted
    }
}
