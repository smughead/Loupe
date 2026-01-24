import Foundation
import ApplicationServices
import AppKit

/// Represents metadata extracted from an AXUIElement
public struct AXElementInfo: Identifiable, Equatable {
    public let id = UUID()
    public let role: String
    public let identifier: String?
    public let title: String?
    public let value: String?
    public let frame: CGRect
    public let hierarchyPath: [String]

    /// The raw AXUIElement reference (for further queries if needed)
    public let element: AXUIElement

    public init(
        role: String,
        identifier: String?,
        title: String?,
        value: String?,
        frame: CGRect,
        hierarchyPath: [String],
        element: AXUIElement
    ) {
        self.role = role
        self.identifier = identifier
        self.title = title
        self.value = value
        self.frame = frame
        self.hierarchyPath = hierarchyPath
        self.element = element
    }

    /// Formatted hierarchy path for display
    public var formattedPath: String {
        hierarchyPath.joined(separator: " → ")
    }

    /// AI-friendly location string for identifying this element in code
    /// Format: AXWindow > AXGroup > AXButton[identifier="submit", title="Submit"]
    public var aiLocationString: String {
        var parts: [String] = []

        for (index, role) in hierarchyPath.enumerated() {
            if index == hierarchyPath.count - 1 {
                // Last element - add identifying attributes
                var attrs: [String] = []
                if let id = identifier, !id.isEmpty {
                    attrs.append("identifier=\"\(id)\"")
                }
                if let t = title, !t.isEmpty {
                    attrs.append("title=\"\(t)\"")
                }
                if attrs.isEmpty {
                    parts.append(role)
                } else {
                    parts.append("\(role)[\(attrs.joined(separator: ", "))]")
                }
            } else {
                parts.append(role)
            }
        }

        return parts.joined(separator: " > ")
    }

    /// Short display label for the element (role + title or identifier)
    public var displayLabel: String {
        if let t = title, !t.isEmpty {
            return "\(role) \"\(t)\""
        } else if let id = identifier, !id.isEmpty {
            return "\(role) (\(id))"
        } else {
            return role
        }
    }

    /// Search patterns that AI agents can use to find this element in code
    public var searchPatterns: [String] {
        var patterns: [String] = []

        if let identifier = identifier, !identifier.isEmpty {
            patterns.append("accessibilityIdentifier.*\(identifier)")
        }

        if let title = title, !title.isEmpty {
            // Escape special regex characters in title
            let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
            patterns.append("\(role).*\(escapedTitle)")
        }

        return patterns
    }

    public static func == (lhs: AXElementInfo, rhs: AXElementInfo) -> Bool {
        // Compare by frame and role since AXUIElement isn't Equatable
        lhs.frame == rhs.frame && lhs.role == rhs.role && lhs.identifier == rhs.identifier
    }
}

/// Represents a running application that can be inspected
public struct TargetApp: Identifiable, Hashable {
    public let id: pid_t
    public let name: String
    public let bundleIdentifier: String?
    public let icon: NSImage?

    public init(from app: NSRunningApplication) {
        self.id = app.processIdentifier
        self.name = app.localizedName ?? "Unknown"
        self.bundleIdentifier = app.bundleIdentifier
        self.icon = app.icon
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: TargetApp, rhs: TargetApp) -> Bool {
        lhs.id == rhs.id
    }
}
