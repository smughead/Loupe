import SwiftUI

/// Popover view for adding or editing an annotation on an accessibility element
struct AnnotationPopover: View {
    let element: AXElementInfo
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var annotationText = ""
    @State private var isDetailsExpanded = false
    @FocusState private var isTextFieldFocused: Bool

    private var elementSummary: String {
        element.displayLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Expandable element details header
            DisclosureGroup(isExpanded: $isDetailsExpanded) {
                elementDetailsView
            } label: {
                Text(elementSummary)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            Divider()

            // Feedback text input
            TextField("What should change?", text: $annotationText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
                .focused($isTextFieldFocused)

            // Action buttons
            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { onSave(annotationText) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(annotationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 320)
        .onAppear { isTextFieldFocused = true }
    }

    private var elementDetailsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            detailRow("Role", element.role)
            if let id = element.identifier, !id.isEmpty {
                detailRow("Identifier", id)
            }
            if let title = element.title, !title.isEmpty {
                detailRow("Title", title)
            }
            if let value = element.value, !value.isEmpty {
                detailRow("Value", value)
            }
            if !element.hierarchyPath.isEmpty {
                detailRow("Path", element.hierarchyPath.joined(separator: " > "))
            }
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.vertical, 8)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text("\(label):")
                .foregroundStyle(.tertiary)
                .frame(width: 70, alignment: .trailing)
            Text(value)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Popover Panel

/// Custom NSPanel subclass for popover-style presentation without a caret
private class PopoverPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        // Handle Escape key
        close()
    }
}

/// Controller for managing the annotation popover presentation using a borderless panel
@MainActor
final class AnnotationPopoverController {
    private var panel: NSPanel?
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var onDismissCallback: (() -> Void)?

    /// Spacing between click point and panel edge
    private let panelOffset: CGFloat = 8

    /// Show the annotation popover at a screen position
    func show(
        at screenPoint: NSPoint,
        preferredEdge: NSRectEdge,
        element: AXElementInfo,
        onSave: @escaping (String) -> Void,
        onDismiss: (() -> Void)? = nil
    ) {
        // Dismiss any existing panel immediately (no animation when replacing)
        dismiss(animated: false)

        self.onDismissCallback = onDismiss

        // Note: Glassmorphism dim overlay removed - NSVisualEffectView with .behindWindow
        // covering all screens causes WindowServer hangs. The modal behavior (wiggle on
        // click-outside, Escape to dismiss) works without the visual dim effect.

        // Create the SwiftUI content
        let content = AnnotationPopover(
            element: element,
            onSave: { [weak self] text in
                onSave(text)
                self?.dismiss()
            },
            onCancel: { [weak self] in
                self?.dismiss()
            }
        )

        // Create hosting controller to get content size
        let hostingController = NSHostingController(rootView: content)
        let contentSize = hostingController.view.fittingSize

        // Calculate panel position based on preferred edge
        let panelOrigin = calculatePanelOrigin(
            screenPoint: screenPoint,
            contentSize: contentSize,
            preferredEdge: preferredEdge
        )

        // Create the panel (without .nonactivatingPanel so it can receive keyboard focus)
        let panel = PopoverPanel(
            contentRect: NSRect(origin: panelOrigin, size: contentSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.contentViewController = hostingController
        panel.isFloatingPanel = true  // Stay above other windows

        // Style the content view with rounded corners and background
        if let contentView = panel.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 8
            contentView.layer?.masksToBounds = true
            contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            contentView.layer?.borderColor = NSColor.separatorColor.cgColor
            contentView.layer?.borderWidth = 0.5
        }

        // Set up initial state for animation (scaled down and transparent)
        panel.alphaValue = 0
        if let layer = panel.contentView?.layer {
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            // Adjust position to account for anchor point change
            layer.position = CGPoint(
                x: layer.frame.midX,
                y: layer.frame.midY
            )
            layer.transform = CATransform3DMakeScale(0.95, 0.95, 1.0)
        }

        self.panel = panel

        // Activate Loupe app and show panel with focus
        // Use makeKeyAndOrderFront for more reliable focus handling
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        // Ensure the panel's content view becomes first responder
        // This helps with subsequent popover shows when Loupe is already active
        if let contentView = panel.contentView {
            panel.makeFirstResponder(contentView)
        }

        // Animate in with scale + fade
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        }

        // Animate the scale transform separately using Core Animation
        if let layer = panel.contentView?.layer {
            let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
            scaleAnimation.fromValue = 0.95
            scaleAnimation.toValue = 1.0
            scaleAnimation.duration = 0.15
            scaleAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            scaleAnimation.fillMode = .forwards
            scaleAnimation.isRemovedOnCompletion = false
            layer.add(scaleAnimation, forKey: "scaleIn")
            layer.transform = CATransform3DIdentity
        }

        // Install event monitors
        installClickOutsideMonitor()
        installKeyboardMonitor()
    }

    /// Calculate where to position the panel origin based on the click point and preferred edge
    private func calculatePanelOrigin(
        screenPoint: NSPoint,
        contentSize: NSSize,
        preferredEdge: NSRectEdge
    ) -> NSPoint {
        var origin = screenPoint

        switch preferredEdge {
        case .minX:
            // Panel appears to the left of click point
            origin.x = screenPoint.x - contentSize.width - panelOffset
            origin.y = screenPoint.y - contentSize.height / 2
        case .maxX:
            // Panel appears to the right of click point
            origin.x = screenPoint.x + panelOffset
            origin.y = screenPoint.y - contentSize.height / 2
        case .minY:
            // Panel appears above click point (in AppKit coords, minY is bottom)
            origin.x = screenPoint.x - contentSize.width / 2
            origin.y = screenPoint.y + panelOffset
        case .maxY:
            // Panel appears below click point
            origin.x = screenPoint.x - contentSize.width / 2
            origin.y = screenPoint.y - contentSize.height - panelOffset
        @unknown default:
            origin.x = screenPoint.x + panelOffset
            origin.y = screenPoint.y - contentSize.height / 2
        }

        // Ensure panel stays on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame

            // Clamp horizontal position
            if origin.x < screenFrame.minX {
                origin.x = screenFrame.minX
            } else if origin.x + contentSize.width > screenFrame.maxX {
                origin.x = screenFrame.maxX - contentSize.width
            }

            // Clamp vertical position
            if origin.y < screenFrame.minY {
                origin.y = screenFrame.minY
            } else if origin.y + contentSize.height > screenFrame.maxY {
                origin.y = screenFrame.maxY - contentSize.height
            }
        }

        return origin
    }

    /// Install event monitor to show wiggle animation when clicking outside the panel (modal behavior)
    private func installClickOutsideMonitor() {
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let panel = self.panel else { return event }

            // Check if click is outside the panel
            let clickLocation = NSEvent.mouseLocation
            if !panel.frame.contains(clickLocation) {
                // Wiggle the popover to indicate it's modal - user must complete/cancel the annotation
                self.wiggle()
                // Consume the event to prevent it from reaching the overlay controller
                return nil
            }

            // Let clicks inside the panel through normally
            return event
        }
    }

    /// Remove the click-outside monitor
    private func removeClickOutsideMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    /// Install keyboard event monitor for Escape key
    private func installKeyboardMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            // Check for Escape key (keyCode 53)
            if event.keyCode == 53 {
                self.dismiss()
                return nil  // Consume the event
            }

            return event
        }
    }

    /// Remove the keyboard monitor
    private func removeKeyboardMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    /// Animate a "wiggle" shake to indicate the popover is modal and cannot be dismissed by clicking outside
    private func wiggle() {
        guard let panel = panel else { return }

        // Use the panel's frame for the wiggle animation
        let originalFrame = panel.frame

        // Apply animation by adjusting the window frame directly with timed offsets
        let shakeOffsets: [CGFloat] = [-8, 8, -6, 6, -3, 3, 0]
        let interval: UInt64 = 57_000_000  // ~57ms per step (0.4s / 7 steps)

        Task { @MainActor [weak self] in
            for offset in shakeOffsets {
                guard let self = self, let panel = self.panel else { return }
                var frame = originalFrame
                frame.origin.x = originalFrame.origin.x + offset
                panel.setFrame(frame, display: false)
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    /// Dismiss the current panel if shown
    /// - Parameter animated: Whether to animate the dismissal. Use `false` when replacing with a new popover.
    func dismiss(animated: Bool = true) {
        removeClickOutsideMonitor()
        removeKeyboardMonitor()
        // dismissDimWindow removed - see note in show()

        guard let panel = panel else {
            onDismissCallback?()
            onDismissCallback = nil
            return
        }

        // Clear reference immediately to prevent multiple popovers
        self.panel = nil

        if animated {
            // Animate out with scale + fade
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                Task { @MainActor in
                    panel.close()
                    self?.onDismissCallback?()
                    self?.onDismissCallback = nil
                }
            }

            // Animate the scale transform
            if let layer = panel.contentView?.layer {
                let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
                scaleAnimation.fromValue = 1.0
                scaleAnimation.toValue = 0.95
                scaleAnimation.duration = 0.12
                scaleAnimation.timingFunction = CAMediaTimingFunction(name: .easeIn)
                scaleAnimation.fillMode = .forwards
                scaleAnimation.isRemovedOnCompletion = false
                layer.add(scaleAnimation, forKey: "scaleOut")
            }
        } else {
            // Immediate dismissal (no animation)
            panel.close()
            onDismissCallback?()
            onDismissCallback = nil
        }
    }
}
