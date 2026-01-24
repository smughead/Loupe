import AppKit

/// Controller for the menu bar status item
@MainActor
public final class MenuBarController {

    // MARK: - Properties

    private var statusItem: NSStatusItem?

    /// Whether inspection is currently active (affects icon appearance)
    public var isInspecting = false {
        didSet {
            updateIcon()
        }
    }

    /// Callback when the status item is clicked
    public var onToggle: (() -> Void)?

    // MARK: - Initialization

    public init() {
        setupStatusItem()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let button = statusItem?.button else { return }

        updateIcon()
        button.target = self
        button.action = #selector(statusItemClicked)
    }

    // MARK: - Actions

    @objc private func statusItemClicked() {
        onToggle?()
    }

    // MARK: - Icon Management

    private func updateIcon() {
        guard let button = statusItem?.button else { return }

        let symbolName = isInspecting ? "eye.fill" : "eye"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Loupe Inspector")

        // Configure for template rendering (adapts to menu bar appearance)
        image?.isTemplate = true

        button.image = image
    }

    /// Show the status item
    public func show() {
        statusItem?.isVisible = true
    }

    /// Hide the status item
    public func hide() {
        statusItem?.isVisible = false
    }
}
