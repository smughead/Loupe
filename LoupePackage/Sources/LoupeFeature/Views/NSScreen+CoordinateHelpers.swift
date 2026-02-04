import AppKit

extension NSScreen {

    /// The primary screen (the one with the menu bar), which is the anchor
    /// for macOS Accessibility API coordinates.
    ///
    /// `NSScreen.main` returns the screen with keyboard focus, which changes
    /// as the user works across monitors. AX coordinates are always relative
    /// to the primary screen's top-left corner, so Y-flip calculations must
    /// use the primary screen's height — not the focused screen's height.
    static var primaryScreen: NSScreen? {
        screens.first
    }

    /// Height of the primary screen, used for the AX ↔ AppKit Y-flip formula.
    ///
    /// Returns 0 if no screens are available (shouldn't happen in practice).
    static var primaryScreenHeight: CGFloat {
        primaryScreen?.frame.height ?? 0
    }

    /// Returns the screen whose frame contains `point` (in AppKit screen coordinates).
    ///
    /// Useful for clamping UI elements (labels, popovers) to the correct monitor
    /// instead of always clamping to `NSScreen.main`.
    static func screen(containing point: NSPoint) -> NSScreen? {
        screens.first { $0.frame.contains(point) }
    }

    /// Returns the screen whose frame contains the center of `rect`.
    static func screen(containing rect: NSRect) -> NSScreen? {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        return screen(containing: center)
    }
}
