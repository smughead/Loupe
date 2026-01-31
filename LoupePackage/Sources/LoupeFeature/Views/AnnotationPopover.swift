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

            // Feedback text input with explicit focus styling
            TextField("What should change?", text: $annotationText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(3...6)
                .focused($isTextFieldFocused)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isTextFieldFocused ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isTextFieldFocused ? 2 : 1)
                )

            // Action buttons
            HStack {
                Spacer()
                Button("Cancel") {
                    print("[Loupe] CANCEL BUTTON: Action fired!")
                    onCancel()
                }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    print("[Loupe] ADD BUTTON: Action fired!")
                    onSave(annotationText)
                }
                    .keyboardShortcut(.defaultAction)
                    .disabled(annotationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 320)
        .onAppear {
            // Delay focus slightly to ensure the panel is fully key
            // and the responder chain is properly set up
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
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

/// Custom NSView subclass that accepts first mouse to ensure clicks work
/// immediately when the panel appears, even if it's not yet the key window.
private class FirstMouseView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        // Critical: Return true to accept mouse clicks even when panel isn't key window
        // Without this, borderless panels may ignore the first click
        return true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Let subviews (the SwiftUI hosting view) handle the hit test
        // This ensures mouse events reach the actual controls
        return super.hitTest(point)
    }
}

/// Controller for managing the annotation popover presentation using a borderless panel
@MainActor
final class AnnotationPopoverController {
    private var panel: NSPanel?
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var onDismissCallback: (() -> Void)?

    /// Spacing between element and panel edge
    private let panelOffset: CGFloat = 8

    /// Show the annotation popover adjacent to an element
    /// - Parameters:
    ///   - elementFrame: The element's frame in screen coordinates (AppKit: origin at bottom-left)
    ///   - preferredEdge: Which edge of the element to attach the popover to
    ///   - element: The accessibility element info to display
    ///   - onSave: Callback when user saves the annotation
    ///   - onDismiss: Callback when popover is dismissed
    func show(
        forElementFrame elementFrame: NSRect,
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

        // Calculate panel position based on preferred edge and element frame
        let panelOrigin = calculatePanelOrigin(
            elementFrame: elementFrame,
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
        panel.isFloatingPanel = true  // Stay above other windows
        panel.becomesKeyOnlyIfNeeded = false  // Always become key when clicked
        panel.hidesOnDeactivate = false  // Stay visible when app loses focus

        // Wrap the hosting view in a FirstMouseView to ensure clicks work immediately
        let hostingView = hostingController.view
        let firstMouseContainer = FirstMouseView()
        firstMouseContainer.wantsLayer = true
        firstMouseContainer.addSubview(hostingView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: firstMouseContainer.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: firstMouseContainer.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: firstMouseContainer.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: firstMouseContainer.bottomAnchor)
        ])

        panel.contentView = firstMouseContainer
        panel.contentViewController = hostingController  // Retain the hosting controller

        // IMPORTANT: Setting contentView can change the frame, so explicitly set it again
        // to ensure the panel is positioned at our calculated origin
        panel.setFrameOrigin(panelOrigin)

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

        // Debug: Log intended vs actual panel frame
        print("[Loupe] POPOVER: intended origin = \(panelOrigin), size = \(contentSize)")
        print("[Loupe] POPOVER: panel.frame AFTER setFrameOrigin = \(panel.frame)")

        // Activate Loupe app and show panel with focus
        // Use makeKeyAndOrderFront for more reliable focus handling
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        // Debug: Log actual frame after showing
        print("[Loupe] POPOVER: panel.frame AFTER show = \(panel.frame)")

        // Delay making the hosting view first responder to allow SwiftUI's
        // @FocusState to properly focus the text field via onAppear
        DispatchQueue.main.async {
            panel.makeFirstResponder(hostingView)
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

    /// Calculate where to position the panel origin based on the element frame and preferred edge
    private func calculatePanelOrigin(
        elementFrame: NSRect,
        contentSize: NSSize,
        preferredEdge: NSRectEdge
    ) -> NSPoint {
        var origin: NSPoint
        let edgeName: String

        // Position the popover adjacent to the element's edge, vertically/horizontally centered
        switch preferredEdge {
        case .minX:
            // Panel appears to the left of element
            origin = NSPoint(
                x: elementFrame.minX - contentSize.width - panelOffset,
                y: elementFrame.midY - contentSize.height / 2
            )
            edgeName = "minX (left of element)"
        case .maxX:
            // Panel appears to the right of element
            origin = NSPoint(
                x: elementFrame.maxX + panelOffset,
                y: elementFrame.midY - contentSize.height / 2
            )
            edgeName = "maxX (right of element)"
        case .minY:
            // Panel appears above element (in AppKit coords, minY is bottom, so "above" means higher Y)
            origin = NSPoint(
                x: elementFrame.midX - contentSize.width / 2,
                y: elementFrame.maxY + panelOffset
            )
            edgeName = "minY (above element)"
        case .maxY:
            // Panel appears below element
            origin = NSPoint(
                x: elementFrame.midX - contentSize.width / 2,
                y: elementFrame.minY - contentSize.height - panelOffset
            )
            edgeName = "maxY (below element)"
        @unknown default:
            origin = NSPoint(
                x: elementFrame.maxX + panelOffset,
                y: elementFrame.midY - contentSize.height / 2
            )
            edgeName = "unknown"
        }

        print("[Loupe] calculatePanelOrigin:")
        print("[Loupe]   elementFrame = \(elementFrame)")
        print("[Loupe]   contentSize = \(contentSize)")
        print("[Loupe]   preferredEdge = \(edgeName)")
        print("[Loupe]   calculated origin = \(origin)")

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

            print("[Loupe]   final origin (after clamping) = \(origin)")
        }

        return origin
    }

    /// Install event monitor to show wiggle animation when clicking outside the panel (modal behavior)
    private func installClickOutsideMonitor() {
        // Use a GLOBAL monitor to detect clicks anywhere, including clicks that go to other apps.
        // This is necessary because the overlay window ignores mouse events when the popover is active,
        // allowing clicks to pass through to the target app. Global monitors observe but cannot consume events.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let panel = self.panel else { return }

            let clickLocation = NSEvent.mouseLocation
            let isInsidePanel = panel.frame.contains(clickLocation)

            print("[Loupe] CLICK (global): location=\(clickLocation), panelFrame=\(panel.frame), isInsidePanel=\(isInsidePanel)")

            if !isInsidePanel {
                // Click outside panel - wiggle to indicate modal behavior
                print("[Loupe] CLICK (global): Outside panel - wiggling")
                self.wiggle()
                // Re-activate Loupe and bring popover to front
                NSApp.activate(ignoringOtherApps: true)
                panel.makeKeyAndOrderFront(nil)
            }
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
