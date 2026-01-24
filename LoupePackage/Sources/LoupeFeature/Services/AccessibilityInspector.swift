import Foundation
@preconcurrency import ApplicationServices
import AppKit

/// Service that wraps macOS Accessibility APIs for UI element inspection
@MainActor
@Observable
public final class AccessibilityInspector {

    // MARK: - Published State

    public private(set) var isAccessibilityEnabled = false
    public private(set) var runningApps: [TargetApp] = []
    public private(set) var currentElement: AXElementInfo?

    // MARK: - Private State

    private var targetAppElement: AXUIElement?

    // MARK: - Initialization

    public init() {
        checkAccessibilityPermission()
        refreshRunningApps()
    }

    // MARK: - Permission Management

    /// Check if accessibility permission is granted
    public func checkAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()
        print("[Loupe] Accessibility check: \(trusted ? "GRANTED" : "DENIED")")
        isAccessibilityEnabled = trusted
    }

    /// Request accessibility permission (shows system prompt)
    public func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        // Check again after a short delay (user might grant permission)
        Task {
            try? await Task.sleep(for: .seconds(1))
            checkAccessibilityPermission()
        }
    }

    // MARK: - App Management

    /// Refresh the list of running applications
    public func refreshRunningApps() {
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .map { TargetApp(from: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Set the target application to inspect
    public func setTargetApp(_ app: TargetApp) {
        targetAppElement = AXUIElementCreateApplication(app.id)
        currentElement = nil
    }

    /// Clear the target application
    public func clearTargetApp() {
        targetAppElement = nil
        currentElement = nil
    }

    // MARK: - Element Inspection

    /// Get the UI element at a screen position
    public func elementAt(screenPosition: CGPoint) -> AXElementInfo? {
        guard let appElement = targetAppElement else { return nil }

        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            appElement,
            Float(screenPosition.x),
            Float(screenPosition.y),
            &element
        )

        guard result == .success, let element = element else {
            return nil
        }

        return extractElementInfo(from: element)
    }

    /// Update the current element based on mouse position
    public func updateElementAtPosition(_ screenPosition: CGPoint) {
        currentElement = elementAt(screenPosition: screenPosition)
    }

    // MARK: - Element Info Extraction

    private func extractElementInfo(from element: AXUIElement) -> AXElementInfo? {
        let role = getStringAttribute(element, kAXRoleAttribute as CFString)

        guard let role = role else { return nil }

        let identifier = getStringAttribute(element, kAXIdentifierAttribute as CFString)
        let title = getStringAttribute(element, kAXTitleAttribute as CFString)
        let value = getStringAttribute(element, kAXValueAttribute as CFString)
        let frame = getFrameAttribute(element)
        let hierarchyPath = buildHierarchyPath(from: element)

        return AXElementInfo(
            role: role,
            identifier: identifier,
            title: title,
            value: value,
            frame: frame,
            hierarchyPath: hierarchyPath,
            element: element
        )
    }

    private func getStringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)

        guard result == .success, let cfValue = value else { return nil }

        if let stringValue = cfValue as? String {
            return stringValue
        }

        return nil
    }

    private func getFrameAttribute(_ element: AXUIElement) -> CGRect {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        let posResult = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
        let sizeResult = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)

        var position = CGPoint.zero
        var size = CGSize.zero

        if posResult == .success, let posValue = positionValue {
            var point = CGPoint.zero
            if AXValueGetValue(posValue as! AXValue, .cgPoint, &point) {
                position = point
            }
        }

        if sizeResult == .success, let szValue = sizeValue {
            var sz = CGSize.zero
            if AXValueGetValue(szValue as! AXValue, .cgSize, &sz) {
                size = sz
            }
        }

        return CGRect(origin: position, size: size)
    }

    private func buildHierarchyPath(from element: AXUIElement) -> [String] {
        var path: [String] = []
        var current: AXUIElement? = element

        while let el = current {
            if let role = getStringAttribute(el, kAXRoleAttribute as CFString) {
                path.insert(role, at: 0)
            }

            // Get parent
            var parentValue: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &parentValue)

            if result == .success, let parent = parentValue {
                current = (parent as! AXUIElement)
            } else {
                current = nil
            }

            // Safety limit to prevent infinite loops
            if path.count > 20 { break }
        }

        return path
    }

    // MARK: - Window Tracking

    /// Get the frame of the target app's focused window
    public func getTargetWindowFrame() -> CGRect? {
        guard let appElement = targetAppElement else { return nil }

        // Get the focused window
        var windowValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        )

        if result != .success {
            // Try getting the first window instead
            var windowsValue: CFTypeRef?
            let windowsResult = AXUIElementCopyAttributeValue(
                appElement,
                kAXWindowsAttribute as CFString,
                &windowsValue
            )

            guard windowsResult == .success,
                  let windows = windowsValue as? [AXUIElement],
                  let firstWindow = windows.first else {
                return nil
            }

            return getFrameAttribute(firstWindow)
        }

        guard let window = windowValue else { return nil }
        return getFrameAttribute(window as! AXUIElement)
    }

    /// Get the title of the target app's focused window
    public func getTargetWindowTitle() -> String? {
        guard let appElement = targetAppElement else { return nil }

        // Get the focused window
        var windowValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        )

        let windowElement: AXUIElement

        if result == .success, let window = windowValue {
            windowElement = window as! AXUIElement
        } else {
            // Try getting the first window instead
            var windowsValue: CFTypeRef?
            let windowsResult = AXUIElementCopyAttributeValue(
                appElement,
                kAXWindowsAttribute as CFString,
                &windowsValue
            )

            guard windowsResult == .success,
                  let windows = windowsValue as? [AXUIElement],
                  let firstWindow = windows.first else {
                return nil
            }

            windowElement = firstWindow
        }

        return getStringAttribute(windowElement, kAXTitleAttribute as CFString)
    }
}
