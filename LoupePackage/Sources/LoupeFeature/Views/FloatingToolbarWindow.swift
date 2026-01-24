import AppKit
import SwiftUI

/// Controller for the floating toolbar window
@MainActor
public final class FloatingToolbarWindowController: NSWindowController, ObservableObject {

    // MARK: - Published State

    @Published public var isExpanded = true
    @Published public var isInspecting = false

    // MARK: - Callbacks

    public var onInspectionToggle: ((Bool) -> Void)?
    public var onCopyFeedback: (() -> Void)?
    public var onClearAnnotations: (() -> Void)?
    public var onClose: (() -> Void)?

    // MARK: - Private State

    private var annotationStore: AnnotationStore?
    private var hostingView: NSHostingView<AnyView>?

    // Window sizes
    private let expandedSize = NSSize(width: 320, height: 60)
    private let collapsedSize = NSSize(width: 64, height: 64)

    // MARK: - Initialization

    public init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 320, height: 60)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.isMovableByWindowBackground = true

        super.init(window: window)

        setupContent()
        positionWindow()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Configuration

    /// Set the annotation store to observe for badge counts
    public func setAnnotationStore(_ store: AnnotationStore) {
        self.annotationStore = store
        updateContent()
    }

    // MARK: - Setup

    private func setupContent() {
        updateContent()
    }

    private func updateContent() {
        let annotationCount = annotationStore?.annotations.count ?? 0

        let toolbarView = FloatingToolbarView(
            isExpanded: Binding(
                get: { [weak self] in self?.isExpanded ?? true },
                set: { [weak self] newValue in
                    self?.isExpanded = newValue
                    self?.updateWindowSize()
                }
            ),
            isInspecting: Binding(
                get: { [weak self] in self?.isInspecting ?? false },
                set: { [weak self] newValue in
                    self?.isInspecting = newValue
                    self?.onInspectionToggle?(newValue)
                }
            ),
            annotationCount: annotationCount,
            onCopyFeedback: { [weak self] in
                self?.onCopyFeedback?()
            },
            onClearAnnotations: { [weak self] in
                self?.onClearAnnotations?()
            },
            onClose: { [weak self] in
                self?.onClose?()
                self?.close()
            }
        )

        let hosting = NSHostingView(rootView: AnyView(toolbarView))
        hosting.frame = window?.contentView?.bounds ?? NSRect.zero
        hosting.autoresizingMask = [.width, .height]

        window?.contentView = hosting
        hostingView = hosting
    }

    private func updateWindowSize() {
        guard let window = window, let screen = NSScreen.main else { return }

        let targetSize = isExpanded ? expandedSize : collapsedSize
        let screenFrame = screen.visibleFrame

        // Keep bottom-right position
        let newOrigin = NSPoint(
            x: screenFrame.maxX - targetSize.width - 20,
            y: screenFrame.minY + 20
        )

        let newFrame = NSRect(origin: newOrigin, size: targetSize)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }
    }

    private func positionWindow() {
        guard let window = window, let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let size = isExpanded ? expandedSize : collapsedSize

        // Position at bottom-right with padding
        let origin = NSPoint(
            x: screenFrame.maxX - size.width - 20,
            y: screenFrame.minY + 20
        )

        window.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    // MARK: - Public Methods

    /// Refresh the toolbar content (call when annotation count changes)
    public func refreshContent() {
        updateContent()
    }

    /// Show the toolbar window
    public func show() {
        showWindow(nil)
        window?.orderFront(nil)
    }

    /// Hide the toolbar window
    public func hide() {
        window?.orderOut(nil)
    }

    /// Toggle visibility
    public func toggleVisibility() {
        if window?.isVisible == true {
            hide()
        } else {
            show()
        }
    }
}
