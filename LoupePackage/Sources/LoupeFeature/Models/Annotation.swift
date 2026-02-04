import Foundation
import CoreGraphics

/// Represents an annotation attached to an accessibility element
public struct Annotation: Identifiable, Equatable {
    public let id: UUID
    public let badgeNumber: Int
    public var text: String
    public let elementFrame: CGRect
    public let elementRole: String
    public let elementSubrole: String?
    public let elementIdentifier: String?
    public let elementTitle: String?
    public let elementValue: String?
    public let hierarchyPath: [HierarchyNode]
    public let windowTitle: String?
    public let appName: String
    public let bundleIdentifier: String?
    public let createdAt: Date

    // Extended properties for detailed/forensic output
    public let siblings: [SiblingInfo]
    public let windowLevel: Int?
    public let allAttributes: [String: String]?

    // Region ID if this annotation was created from a multi-select region
    public let regionId: UUID?

    /// Sibling context as a formatted string (backward-compatible computed property)
    public var siblingContext: String? {
        guard !siblings.isEmpty else { return nil }
        return siblings.map { $0.displayString }.joined(separator: ", ")
    }

    public init(
        id: UUID = UUID(),
        badgeNumber: Int,
        text: String,
        elementFrame: CGRect,
        elementRole: String,
        elementSubrole: String? = nil,
        elementIdentifier: String?,
        elementTitle: String? = nil,
        elementValue: String? = nil,
        hierarchyPath: [HierarchyNode] = [],
        windowTitle: String? = nil,
        appName: String = "",
        bundleIdentifier: String? = nil,
        siblings: [SiblingInfo] = [],
        windowLevel: Int? = nil,
        allAttributes: [String: String]? = nil,
        regionId: UUID? = nil
    ) {
        self.id = id
        self.badgeNumber = badgeNumber
        self.text = text
        self.elementFrame = elementFrame
        self.elementRole = elementRole
        self.elementSubrole = elementSubrole
        self.elementIdentifier = elementIdentifier
        self.elementTitle = elementTitle
        self.elementValue = elementValue
        self.hierarchyPath = hierarchyPath
        self.windowTitle = windowTitle
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.createdAt = Date()
        self.siblings = siblings
        self.windowLevel = windowLevel
        self.allAttributes = allAttributes
        self.regionId = regionId
    }

    /// AI-friendly location string for identifying this element
    public var aiLocationString: String {
        hierarchyPath.aiLocationString
    }

    /// Display label formatted according to the naming style
    /// - Parameter style: The naming style to use
    /// - Returns: Formatted element name
    public func displayLabel(style: NamingStyle) -> String {
        switch style {
        case .humanized:
            let cleanRole = elementRole.hasPrefix("AX") ? String(elementRole.dropFirst(2)).lowercased() : elementRole.lowercased()
            if let title = elementTitle, !title.isEmpty {
                return "\(cleanRole) \"\(title)\""
            } else if let identifier = elementIdentifier, !identifier.isEmpty {
                return "\(cleanRole) (\(identifier))"
            } else {
                return cleanRole
            }
        case .technical:
            var attrs: [String] = []
            if let identifier = elementIdentifier, !identifier.isEmpty {
                attrs.append("identifier=\"\(identifier)\"")
            }
            if let title = elementTitle, !title.isEmpty {
                attrs.append("title=\"\(title)\"")
            }
            if attrs.isEmpty {
                return elementRole
            } else {
                return "\(elementRole)[\(attrs.joined(separator: ", "))]"
            }
        }
    }

    /// Display label for the element (defaults to humanized)
    public var displayLabel: String {
        displayLabel(style: .humanized)
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
            elementSubrole: element.subrole,
            elementIdentifier: element.identifier,
            elementTitle: element.title,
            elementValue: element.value,
            hierarchyPath: element.hierarchyPath,
            windowTitle: windowTitle,
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            siblings: element.siblings,
            windowLevel: element.windowLevel,
            allAttributes: element.allAttributes
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
