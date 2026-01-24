import Foundation
import CoreGraphics

/// Represents an annotation attached to an accessibility element
public struct Annotation: Identifiable, Equatable {
    public let id: UUID
    public let badgeNumber: Int
    public var text: String
    public let elementFrame: CGRect
    public let elementRole: String
    public let elementIdentifier: String?
    public let elementTitle: String?
    public let elementValue: String?
    public let hierarchyPath: [String]
    public let windowTitle: String?
    public let appName: String
    public let bundleIdentifier: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        badgeNumber: Int,
        text: String,
        elementFrame: CGRect,
        elementRole: String,
        elementIdentifier: String?,
        elementTitle: String? = nil,
        elementValue: String? = nil,
        hierarchyPath: [String] = [],
        windowTitle: String? = nil,
        appName: String = "",
        bundleIdentifier: String? = nil
    ) {
        self.id = id
        self.badgeNumber = badgeNumber
        self.text = text
        self.elementFrame = elementFrame
        self.elementRole = elementRole
        self.elementIdentifier = elementIdentifier
        self.elementTitle = elementTitle
        self.elementValue = elementValue
        self.hierarchyPath = hierarchyPath
        self.windowTitle = windowTitle
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.createdAt = Date()
    }

    /// AI-friendly location string for identifying this element
    public var aiLocationString: String {
        var parts: [String] = []

        // Build the path from hierarchy
        for (index, role) in hierarchyPath.enumerated() {
            if index == hierarchyPath.count - 1 {
                // Last element - add attributes
                var attrs: [String] = []
                if let identifier = elementIdentifier, !identifier.isEmpty {
                    attrs.append("identifier=\"\(identifier)\"")
                }
                if let title = elementTitle, !title.isEmpty {
                    attrs.append("title=\"\(title)\"")
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

    /// Display label for the element (role + title or identifier)
    public var displayLabel: String {
        if let title = elementTitle, !title.isEmpty {
            return "\(elementRole) \"\(title)\""
        } else if let identifier = elementIdentifier, !identifier.isEmpty {
            return "\(elementRole) (\(identifier))"
        } else {
            return elementRole
        }
    }

    /// Position for the badge (top-right corner of the element)
    public var badgePosition: CGPoint {
        CGPoint(
            x: elementFrame.maxX - 8,
            y: elementFrame.minY + 8
        )
    }
}

/// Manages a collection of annotations for an inspection session
@MainActor
public final class AnnotationStore: ObservableObject {
    @Published public private(set) var annotations: [Annotation] = []

    private var nextBadgeNumber = 1

    public init() {}

    /// Add a new annotation for an element
    public func addAnnotation(
        text: String,
        for element: AXElementInfo,
        windowTitle: String? = nil,
        appName: String = "",
        bundleIdentifier: String? = nil
    ) -> Annotation {
        let annotation = Annotation(
            badgeNumber: nextBadgeNumber,
            text: text,
            elementFrame: element.frame,
            elementRole: element.role,
            elementIdentifier: element.identifier,
            elementTitle: element.title,
            elementValue: element.value,
            hierarchyPath: element.hierarchyPath,
            windowTitle: windowTitle,
            appName: appName,
            bundleIdentifier: bundleIdentifier
        )
        annotations.append(annotation)
        nextBadgeNumber += 1
        return annotation
    }

    /// Remove an annotation by ID
    public func removeAnnotation(id: UUID) {
        annotations.removeAll { $0.id == id }
    }

    /// Update annotation text
    public func updateAnnotation(id: UUID, text: String) {
        if let index = annotations.firstIndex(where: { $0.id == id }) {
            annotations[index].text = text
        }
    }

    /// Find annotation near a given point (for click detection)
    public func annotation(near point: CGPoint, tolerance: CGFloat = 20) -> Annotation? {
        annotations.first { annotation in
            let badgePos = annotation.badgePosition
            let distance = hypot(point.x - badgePos.x, point.y - badgePos.y)
            return distance <= tolerance
        }
    }

    /// Clear all annotations
    public func clear() {
        annotations.removeAll()
        nextBadgeNumber = 1
    }
}
