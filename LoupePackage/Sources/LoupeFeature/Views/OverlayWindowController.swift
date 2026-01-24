import AppKit
import SwiftUI
import CoreVideo

// MARK: - Observable State for SwiftUI Canvas

/// Observable state class that allows SwiftUI Canvas to automatically redraw when highlightFrame changes.
/// This bridges AppKit's mouse tracking events with SwiftUI's reactive rendering system.
@Observable
class OverlayState {
    var highlightFrame: CGRect?
}

/// Controller for the transparent overlay window that draws element highlights
@MainActor
public final class OverlayWindowController: NSWindowController {

    private let inspector: AccessibilityInspector
    private let targetApp: TargetApp
    private var displayLink: CVDisplayLink?
    private let overlayState = OverlayState()

    /// Whether inspection mode is active (controlled externally via toggle)
    public var isInspectionActive = false {
        didSet {
            guard isInspectionActive != oldValue else { return }
            window?.ignoresMouseEvents = !isInspectionActive

            if !isInspectionActive {
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

    public init(inspector: AccessibilityInspector, targetApp: TargetApp) {
        self.inspector = inspector
        self.targetApp = targetApp

        // Create a transparent, borderless window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.ignoresMouseEvents = true  // Start in pass-through mode
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
            onEscape: { [weak self] in self?.close() }
        )

        window?.contentView = NSHostingView(rootView: overlayView)
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

        // Monitor when any app becomes active
        let activateObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }

            // If target app became active, ensure overlay is visible and positioned
            if app.processIdentifier == targetPid {
                Task { @MainActor in
                    self?.window?.orderFront(nil)
                    self?.updateWindowFrame()
                }
            }
        }
        workspaceObservers.append(activateObserver)

        // Monitor when any app is deactivated
        let deactivateObserver = center.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }

            // If target app was deactivated, clear the highlight
            if app.processIdentifier == targetPid {
                Task { @MainActor in
                    self?.overlayState.highlightFrame = nil
                }
            }
        }
        workspaceObservers.append(deactivateObserver)
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
                number: annotation.badgeNumber,
                position: badgePosition,
                text: annotation.text
            )
        }
    }

    // MARK: - Mouse Handling

    private func handleMouseMoved(_ windowLocation: NSPoint) {
        guard let window = window else { return }

        // Convert window-local coordinates to screen coordinates
        let screenPoint = window.convertPoint(toScreen: windowLocation)

        // Convert to AX coordinate system (flip Y)
        guard let screen = NSScreen.main else { return }
        let axPoint = CGPoint(
            x: screenPoint.x,
            y: screen.frame.height - screenPoint.y
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

    private func handleMouseClicked() {
        guard let element = inspector.currentElement,
              let highlightFrame = overlayState.highlightFrame,
              let contentView = window?.contentView else {
            return
        }

        // Create a positioning rect centered in the highlight
        let positioningRect = NSRect(
            x: highlightFrame.midX - 1,
            y: highlightFrame.midY - 1,
            width: 2,
            height: 2
        )

        popoverController.show(
            relativeTo: positioningRect,
            of: contentView,
            elementRole: element.role,
            elementIdentifier: element.identifier
        ) { [weak self] text in
            guard let self = self else { return }
            _ = self.annotationStore.addAnnotation(
                text: text,
                for: element,
                windowTitle: self.inspector.getTargetWindowTitle(),
                appName: self.targetApp.name,
                bundleIdentifier: self.targetApp.bundleIdentifier
            )
            self.updateAnnotationBadges()
        }
    }

    // MARK: - Lifecycle

    public override func close() {
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
    let onEscape: () -> Void

    private let badgeSize: CGFloat = 20
    private let badgeColor = Color.blue

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Transparent background that captures events
                Color.clear
                    .contentShape(Rectangle())

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
                    for badge in annotationBadges() {
                        drawBadge(context: context, badge: badge)
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

    private func drawBadge(context: GraphicsContext, badge: AnnotationBadge) {
        let badgeRect = CGRect(
            x: badge.position.x - badgeSize / 2,
            y: badge.position.y - badgeSize / 2,
            width: badgeSize,
            height: badgeSize
        )

        // Draw circle background
        let circlePath = Path(ellipseIn: badgeRect)
        context.fill(circlePath, with: .color(badgeColor))

        // Draw white border for visibility
        context.stroke(circlePath, with: .color(.white), lineWidth: 2)

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
        let location = convert(event.locationInWindow, from: nil)
        onMouseMoved?(location)
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
    let number: Int
    let position: CGPoint
    let text: String
}
