import AppKit
import SwiftUI
import CoreVideo

// MARK: - Custom Window for Click Support

/// Custom NSWindow subclass that can become key even when borderless.
/// Required for transparent overlay windows to receive mouse click events.
private class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Observable State for SwiftUI Canvas

/// Observable state class that allows SwiftUI Canvas to automatically redraw when highlightFrame changes.
/// This bridges AppKit's mouse tracking events with SwiftUI's reactive rendering system.
@Observable
class OverlayState {
    var highlightFrame: CGRect?
    /// The index of the badge currently being hovered (nil if none)
    var hoveredBadgeIndex: Int?
}

/// Controller for the transparent overlay window that draws element highlights
@MainActor
public final class OverlayWindowController: NSWindowController {

    private let inspector: AccessibilityInspector
    private let targetApp: TargetApp
    private var displayLink: CVDisplayLink?
    private let overlayState = OverlayState()

    /// Local event monitor for capturing mouse clicks at the application level
    private var clickMonitor: Any?

    /// Whether inspection mode is active (controlled externally via toggle)
    public var isInspectionActive = false {
        didSet {
            guard isInspectionActive != oldValue else { return }
            window?.ignoresMouseEvents = !isInspectionActive

            if isInspectionActive {
                installClickMonitor()
            } else {
                removeClickMonitor()
                // Clear highlight and hide label when deactivating
                overlayState.highlightFrame = nil
                elementLabelController.hide()
            }
        }
    }

    /// Reference to self for CVDisplayLink callback (must be unowned to avoid retain cycle)
    private var displayLinkContext: DisplayLinkContext?

    /// Store for annotations on inspected elements
    public let annotationStore = AnnotationStore()

    /// Cached annotation badge positions in local coordinates (updated each frame)
    private var annotationBadges: [AnnotationBadge] = []

    /// Workspace notification observers for app activation tracking
    private var workspaceObservers: [NSObjectProtocol] = []

    /// Controller for showing annotation popovers
    private let popoverController = AnnotationPopoverController()

    /// Controller for floating element label
    private let elementLabelController = ElementLabelWindowController()

    /// Tracks whether the annotation popover is currently active (modal state)
    /// When true, hover highlighting and click-to-inspect are blocked
    private var isPopoverActive = false

    /// Container view that wraps NSHostingView (unflipped, for correct popover positioning)
    private var containerView: NSView?

    public init(inspector: AccessibilityInspector, targetApp: TargetApp) {
        self.inspector = inspector
        self.targetApp = targetApp

        // Create a transparent, borderless window (using custom subclass for click support)
        let window = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.ignoresMouseEvents = true  // Start in pass-through mode
        window.acceptsMouseMovedEvents = true  // Required to receive mouseMoved events
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        super.init(window: window)

        setupOverlayContent()
        updateWindowFrame()
        startTracking()
        setupWorkspaceObservers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupOverlayContent() {
        let overlayView = OverlayView(
            overlayState: overlayState,
            annotationBadges: { [weak self] in self?.annotationBadges ?? [] },
            onMouseMoved: { [weak self] location in self?.handleMouseMoved(location) },
            onMouseClicked: { [weak self] in self?.handleMouseClicked() },
            onBadgeDelete: { [weak self] badgeId in self?.deleteAnnotation(id: badgeId) },
            onEscape: { [weak self] in self?.close() }
        )

        // Create a container view to wrap NSHostingView
        // This allows us to add anchor subviews for popover positioning
        // (NSHostingView doesn't support adding subviews directly)
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor

        let hostingView = NSHostingView(rootView: overlayView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hostingView)

        // Pin hosting view to fill container
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: container.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        window?.contentView = container
        self.containerView = container
    }

    private func startTracking() {
        // Use CVDisplayLink for frame-perfect synchronization with display refresh
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)

        guard let displayLink = link else {
            // Fallback to timer if CVDisplayLink creation fails
            startTimerTracking()
            return
        }

        self.displayLink = displayLink

        // Create context to pass self reference to C callback
        displayLinkContext = DisplayLinkContext(controller: self)

        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, context in
            guard let context = context else { return kCVReturnSuccess }
            let linkContext = Unmanaged<DisplayLinkContext>.fromOpaque(context).takeUnretainedValue()

            Task { @MainActor in
                linkContext.controller?.updateWindowFrame()
            }

            return kCVReturnSuccess
        }

        let contextPointer = Unmanaged.passUnretained(displayLinkContext!).toOpaque()
        CVDisplayLinkSetOutputCallback(displayLink, callback, contextPointer)
        CVDisplayLinkStart(displayLink)
    }

    /// Fallback timer-based tracking if CVDisplayLink fails
    private func startTimerTracking() {
        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateWindowFrame()
            }
        }
    }

    private func setupWorkspaceObservers() {
        let workspace = NSWorkspace.shared
        let center = workspace.notificationCenter
        let targetPid = targetApp.id

        // Get Loupe's own process identifier to ignore self-activation
        let loupePid = ProcessInfo.processInfo.processIdentifier

        // Monitor when any app becomes active to show/hide overlay appropriately
        let activateObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }

            if app.processIdentifier == targetPid {
                // Target app became active - show overlay
                Task { @MainActor in
                    self?.window?.orderFront(nil)
                    self?.updateWindowFrame()
                }
            } else if app.processIdentifier == loupePid {
                // Loupe itself became active - clear highlights but keep overlay window visible
                // This prevents highlighting Loupe's own UI elements while allowing
                // users to interact with Loupe's main window
                Task { @MainActor in
                    self?.overlayState.highlightFrame = nil
                    self?.elementLabelController.hide()
                }
            } else {
                // Some other app (not target, not Loupe) became active - hide everything
                Task { @MainActor in
                    self?.overlayState.highlightFrame = nil
                    self?.elementLabelController.hide()
                    self?.popoverController.dismiss(animated: false)
                    self?.window?.orderOut(nil)
                }
            }
        }
        workspaceObservers.append(activateObserver)
    }

    private func updateWindowFrame() {
        guard let targetFrame = inspector.getTargetWindowFrame() else { return }

        // Convert from AX coordinate system (origin at top-left of screen)
        // to AppKit coordinate system (origin at bottom-left)
        guard let screen = NSScreen.main else { return }
        let screenHeight = screen.frame.height

        let appKitFrame = NSRect(
            x: targetFrame.origin.x,
            y: screenHeight - targetFrame.origin.y - targetFrame.height,
            width: targetFrame.width,
            height: targetFrame.height
        )

        window?.setFrame(appKitFrame, display: true)

        // Update annotation badge positions for rendering
        updateAnnotationBadges()
    }

    /// Convert an AX frame (top-left origin) to AppKit screen coordinates (bottom-left origin)
    private func convertAXFrameToScreen(_ axFrame: CGRect) -> CGRect? {
        guard let screen = NSScreen.main else { return nil }
        return NSRect(
            x: axFrame.origin.x,
            y: screen.frame.height - axFrame.origin.y - axFrame.height,
            width: axFrame.width,
            height: axFrame.height
        )
    }

    /// Convert an AX frame (top-left origin) to overlay-local coordinates for SwiftUI Canvas (top-left origin)
    private func convertAXFrameToLocal(_ axFrame: CGRect) -> CGRect? {
        guard let window = window, let screen = NSScreen.main else { return nil }
        let windowFrame = window.frame

        // Window's top edge in AX coordinates (distance from top of screen to top of window)
        let windowTopInAX = screen.frame.height - windowFrame.maxY

        // Convert to local coordinates (both AX and SwiftUI Canvas use top-left origin)
        let localFrame = CGRect(
            x: axFrame.origin.x - windowFrame.origin.x,
            y: axFrame.origin.y - windowTopInAX,
            width: axFrame.width,
            height: axFrame.height
        )

        return localFrame
    }

    /// Convert a rect from overlay-local coordinates (top-left origin, used by SwiftUI Canvas)
    /// to view coordinates (bottom-left origin, used by NSView/NSPopover positioning)
    private func convertLocalToViewCoordinates(_ localRect: CGRect) -> CGRect? {
        guard let contentView = window?.contentView else { return nil }
        let viewHeight = contentView.bounds.height

        // Flip Y: in top-left origin, Y increases downward
        // In bottom-left origin, Y increases upward
        // newY = viewHeight - localY - rectHeight
        return CGRect(
            x: localRect.origin.x,
            y: viewHeight - localRect.origin.y - localRect.height,
            width: localRect.width,
            height: localRect.height
        )
    }

    /// Update cached annotation badge positions in local coordinates
    private func updateAnnotationBadges() {
        annotationBadges = annotationStore.annotations.compactMap { annotation in
            guard let localFrame = convertAXFrameToLocal(annotation.elementFrame) else { return nil }

            // Position badge at top-right corner of the element
            let badgePosition = CGPoint(
                x: localFrame.maxX - 10,
                y: localFrame.minY + 10
            )

            return AnnotationBadge(
                id: annotation.id,
                number: annotation.badgeNumber,
                position: badgePosition,
                text: annotation.text,
                elementName: annotation.displayLabel
            )
        }
    }

    // MARK: - Mouse Handling

    /// Install application-level event monitor to capture mouse clicks.
    /// This bypasses view hierarchy hit-testing issues with transparent overlay windows.
    private func installClickMonitor() {
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self,
                  let window = self.window,
                  self.isInspectionActive else {
                return event
            }

            // When popover is active, don't consume clicks - let them reach the popover panel
            // (The popover's own click monitor handles click-outside behavior)
            guard !self.isPopoverActive else {
                return event
            }

            // Check if click is within our window using mouse location in screen coordinates
            if window.frame.contains(NSEvent.mouseLocation) {
                self.handleMouseClicked(event: event)
                return nil  // Consume the event
            }
            return event  // Pass through clicks outside our window
        }
    }

    /// Remove the click event monitor when inspection mode is deactivated
    private func removeClickMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    private func handleMouseMoved(_ screenLocation: NSPoint) {
        // Block hover highlighting while popover is active (modal state)
        guard !isPopoverActive else { return }

        // screenLocation is already in screen coordinates (bottom-left origin)
        // from NSEvent.mouseLocation - no window conversion needed

        // Only process mouse moves if the mouse is within our overlay window
        // (which is sized to match the target app's window)
        guard let window = window else { return }

        if !window.frame.contains(screenLocation) {
            // Mouse is outside the target app's window - clear highlight
            overlayState.highlightFrame = nil
            overlayState.hoveredBadgeIndex = nil
            elementLabelController.hide()
            return
        }

        // Convert screen location to local coordinates for badge hit testing
        let localLocation = convertScreenToLocal(screenLocation)

        // Check if hovering over any badge
        overlayState.hoveredBadgeIndex = nil

        if let localPoint = localLocation {
            for (index, badge) in annotationBadges.enumerated() {
                if badge.hitTestRect.contains(localPoint) {
                    overlayState.hoveredBadgeIndex = index
                    break
                }
            }
        }

        // If hovering over a badge, don't show element highlight
        if overlayState.hoveredBadgeIndex != nil {
            overlayState.highlightFrame = nil
            elementLabelController.hide()
            return
        }

        // Convert to AX coordinate system (flip Y using primary screen height)
        guard let mainScreen = NSScreen.main else {
            print("[Loupe] handleMouseMoved: no main screen")
            return
        }

        let axPoint = CGPoint(
            x: screenLocation.x,
            y: mainScreen.frame.height - screenLocation.y
        )

        // Query the accessibility element at this position
        inspector.updateElementAtPosition(axPoint)

        // Update highlight frame using shared coordinate conversion
        if let element = inspector.currentElement {
            overlayState.highlightFrame = convertAXFrameToLocal(element.frame)

            // Show element label near the element (convert AX frame to screen coordinates)
            if let screenFrame = convertAXFrameToScreen(element.frame) {
                elementLabelController.show(for: element, highlightFrame: screenFrame)
            }
        } else {
            overlayState.highlightFrame = nil
            elementLabelController.hide()
        }
    }

    /// Convert screen coordinates (AppKit, bottom-left origin) to local overlay coordinates (top-left origin)
    private func convertScreenToLocal(_ screenPoint: NSPoint) -> CGPoint? {
        guard let window = window else { return nil }

        // First convert screen to window coordinates
        let windowPoint = window.convertPoint(fromScreen: screenPoint)

        // Window uses bottom-left origin, but our local coordinates use top-left origin
        // to match the SwiftUI Canvas coordinate system
        let windowHeight = window.frame.height
        return CGPoint(x: windowPoint.x, y: windowHeight - windowPoint.y)
    }

    /// Delete an annotation by ID
    private func deleteAnnotation(id: UUID) {
        annotationStore.removeAnnotation(id: id)
        updateAnnotationBadges()
        overlayState.hoveredBadgeIndex = nil
    }

    private func handleMouseClicked(event: NSEvent? = nil) {
        // Block new clicks while popover is active (modal state)
        // The popover's click monitor handles clicks and shows wiggle animation
        guard !isPopoverActive else { return }

        guard let element = inspector.currentElement,
              let window = window else {
            return
        }

        // Get click location from the event if available, otherwise use current mouse position
        let clickInWindow: NSPoint
        if let event = event {
            clickInWindow = event.locationInWindow
        } else {
            let screenLocation = NSEvent.mouseLocation
            clickInWindow = window.convertPoint(fromScreen: screenLocation)
        }

        // Smart edge selection based on screen position to avoid collisions:
        // - Near top of screen: use .maxY (popover below, caret up) - plenty of room below
        // - Near bottom of screen: use .minY (popover above, caret down) - plenty of room above
        // - Near right edge: use .minX (popover left)
        // - Default: use .maxX (popover right) - most reliable positioning
        let clickInScreen = window.convertPoint(toScreen: clickInWindow)
        let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        let topThreshold = screenFrame.maxY - 150  // Near top of screen (within ~150px of menu bar)
        let bottomThreshold = screenFrame.minY + 200  // Near bottom of screen
        let rightThreshold = screenFrame.maxX - (screenFrame.width * 0.3)

        let preferredEdge: NSRectEdge
        let edgeName: String

        if clickInScreen.y > topThreshold {
            // Near top of screen - show popover below
            preferredEdge = .maxY
            edgeName = ".maxY (below)"
        } else if clickInScreen.y < bottomThreshold {
            // Near bottom of screen - show popover above
            preferredEdge = .minY
            edgeName = ".minY (above)"
        } else if clickInScreen.x > rightThreshold {
            // Near right edge - show popover to the left
            preferredEdge = .minX
            edgeName = ".minX (left)"
        } else {
            // Default - show popover to the right
            preferredEdge = .maxX
            edgeName = ".maxX (right)"
        }

        print("[Loupe] clickInScreen.y=\(clickInScreen.y), screenFrame.maxY=\(screenFrame.maxY), topThreshold=\(topThreshold), edge=\(edgeName)")

        // Enter modal state before showing popover
        isPopoverActive = true

        popoverController.show(
            at: clickInScreen,
            preferredEdge: preferredEdge,
            element: element,
            onSave: { [weak self] text in
                guard let self = self else { return }
                _ = self.annotationStore.addAnnotation(
                    text: text,
                    for: element,
                    windowTitle: self.inspector.getTargetWindowTitle(),
                    appName: self.targetApp.name,
                    bundleIdentifier: self.targetApp.bundleIdentifier
                )
                self.updateAnnotationBadges()
            },
            onDismiss: { [weak self] in
                guard let self = self else { return }
                // Exit modal state when popover closes
                self.isPopoverActive = false

                // Don't activate target app here - Loupe should retain focus
                // for the entire inspection session. Focus is only released
                // when the user collapses the toolbar (exits inspection mode).
            }
        )
    }

    // MARK: - Lifecycle

    public override func close() {
        // Remove click monitor before closing
        removeClickMonitor()

        if let link = displayLink {
            CVDisplayLinkStop(link)
            displayLink = nil
        }
        displayLinkContext = nil

        // Hide element label
        elementLabelController.hide()

        // Remove workspace observers
        let center = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            center.removeObserver(observer)
        }
        workspaceObservers.removeAll()

        super.close()
    }
}

// MARK: - Overlay SwiftUI View

struct OverlayView: View {
    let overlayState: OverlayState
    let annotationBadges: () -> [AnnotationBadge]
    let onMouseMoved: (NSPoint) -> Void
    let onMouseClicked: () -> Void
    let onBadgeDelete: (UUID) -> Void
    let onEscape: () -> Void

    private let badgeSize: CGFloat = 20
    private let badgeColor = Color.blue
    private let deleteColor = Color.red

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Transparent background that captures events
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onMouseClicked()
                    }

                // Highlight and badges drawing
                Canvas { context, size in
                    // Draw element highlight
                    if let frame = overlayState.highlightFrame {
                        let rect = CGRect(
                            x: frame.origin.x - 2,
                            y: frame.origin.y - 2,
                            width: frame.width + 4,
                            height: frame.height + 4
                        )

                        let path = Path(roundedRect: rect, cornerRadius: 3)

                        // Draw outer glow (multiple strokes with increasing blur/opacity)
                        context.stroke(
                            path,
                            with: .color(.green.opacity(0.3)),
                            style: StrokeStyle(lineWidth: 8)
                        )

                        context.stroke(
                            path,
                            with: .color(.green.opacity(0.5)),
                            style: StrokeStyle(lineWidth: 5)
                        )

                        // Draw solid green border
                        context.stroke(
                            path,
                            with: .color(.green),
                            style: StrokeStyle(lineWidth: 3)
                        )

                        // Draw subtle fill
                        context.fill(
                            path,
                            with: .color(.green.opacity(0.08))
                        )
                    }

                    // Draw annotation badges
                    let badges = annotationBadges()
                    for (index, badge) in badges.enumerated() {
                        let isHovered = overlayState.hoveredBadgeIndex == index
                        drawBadge(context: context, badge: badge, isHovered: isHovered)
                    }
                }

                // Overlay SwiftUI buttons for hovered badge tooltips
                // This provides proper tooltip and click handling that Canvas can't do
                ForEach(Array(annotationBadges().enumerated()), id: \.element.id) { index, badge in
                    if overlayState.hoveredBadgeIndex == index {
                        BadgeDeleteButton(badge: badge) {
                            onBadgeDelete(badge.id)
                        }
                        .position(badge.position)
                    }
                }
            }
            .background(MouseTrackingView(
                onMouseMoved: onMouseMoved,
                onMouseClicked: onMouseClicked,
                onEscape: onEscape
            ))
        }
    }

    private func drawBadge(context: GraphicsContext, badge: AnnotationBadge, isHovered: Bool) {
        let badgeRect = CGRect(
            x: badge.position.x - badgeSize / 2,
            y: badge.position.y - badgeSize / 2,
            width: badgeSize,
            height: badgeSize
        )

        // Draw circle background (red when hovered for delete)
        let circlePath = Path(ellipseIn: badgeRect)
        context.fill(circlePath, with: .color(isHovered ? deleteColor : badgeColor))

        // Draw white border for visibility
        context.stroke(circlePath, with: .color(.white), lineWidth: 2)

        if isHovered {
            // Draw X icon when hovered
            let xSize: CGFloat = 8
            let center = badge.position

            var xPath = Path()
            xPath.move(to: CGPoint(x: center.x - xSize/2, y: center.y - xSize/2))
            xPath.addLine(to: CGPoint(x: center.x + xSize/2, y: center.y + xSize/2))
            xPath.move(to: CGPoint(x: center.x + xSize/2, y: center.y - xSize/2))
            xPath.addLine(to: CGPoint(x: center.x - xSize/2, y: center.y + xSize/2))

            context.stroke(xPath, with: .color(.white), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        } else {
            // Draw number text
            let numberText = Text("\(badge.number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)

            context.draw(
                context.resolve(numberText),
                at: badge.position,
                anchor: .center
            )
        }
    }
}

// MARK: - Badge Delete Button (for hover tooltip and click handling)

private struct BadgeDeleteButton: View {
    let badge: AnnotationBadge
    let onDelete: () -> Void

    var body: some View {
        Button(action: onDelete) {
            Color.clear
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("\(badge.elementName)\n\(badge.text)\n\nClick to delete")
    }
}

// MARK: - Mouse Tracking NSView

struct MouseTrackingView: NSViewRepresentable {
    let onMouseMoved: (NSPoint) -> Void
    let onMouseClicked: () -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> MouseTrackingNSView {
        let view = MouseTrackingNSView()
        view.onMouseMoved = onMouseMoved
        view.onMouseClicked = onMouseClicked
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: MouseTrackingNSView, context: Context) {
        nsView.onMouseMoved = onMouseMoved
        nsView.onMouseClicked = onMouseClicked
        nsView.onEscape = onEscape
    }
}

class MouseTrackingNSView: NSView {
    var onMouseMoved: ((NSPoint) -> Void)?
    var onMouseClicked: (() -> Void)?
    var onEscape: (() -> Void)?

    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existing = trackingArea {
            removeTrackingArea(existing)
        }

        let options: NSTrackingArea.Options = [
            .mouseMoved,
            .activeAlways,
            .inVisibleRect
        ]

        trackingArea = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )

        addTrackingArea(trackingArea!)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func mouseMoved(with event: NSEvent) {
        // Use NSEvent.mouseLocation for reliable screen coordinates
        // This bypasses coordinate confusion from the NSHostingView hierarchy
        let screenLocation = NSEvent.mouseLocation
        onMouseMoved?(screenLocation)
    }

    override func mouseDown(with event: NSEvent) {
        onMouseClicked?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape key
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - CVDisplayLink Context

/// Context object to safely pass OverlayWindowController reference to CVDisplayLink callback
private final class DisplayLinkContext {
    weak var controller: OverlayWindowController?

    init(controller: OverlayWindowController) {
        self.controller = controller
    }
}

// MARK: - Annotation Badge

/// Represents an annotation badge position in overlay-local coordinates for rendering
struct AnnotationBadge {
    let id: UUID
    let number: Int
    let position: CGPoint
    let text: String
    let elementName: String

    /// The hit test rect for this badge (used for hover detection)
    var hitTestRect: CGRect {
        let size: CGFloat = 20
        return CGRect(
            x: position.x - size / 2,
            y: position.y - size / 2,
            width: size,
            height: size
        )
    }
}
