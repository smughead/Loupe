import Foundation
import AppKit

/// Generates markdown output from annotations for AI agents
public struct FeedbackOutputGenerator {

    public init() {}

    /// Generate markdown feedback document from annotations
    /// - Parameters:
    ///   - annotations: The list of annotations to include
    ///   - appName: Name of the inspected application
    ///   - bundleIdentifier: Bundle ID of the inspected application
    ///   - windowTitle: Title of the inspected window
    /// - Returns: Formatted markdown string
    public func generateMarkdown(
        annotations: [Annotation],
        appName: String,
        bundleIdentifier: String?,
        windowTitle: String?
    ) -> String {
        var output = ""

        // Header with app context
        output += "## App Feedback: \(appName)\n"

        if let bundleId = bundleIdentifier {
            output += "**Bundle ID:** \(bundleId)\n"
        }

        if let window = windowTitle {
            output += "**Window:** \(window)\n"
        }

        // Screen size
        if let screen = NSScreen.main {
            let size = screen.frame.size
            output += "**Screen:** \(Int(size.width))×\(Int(size.height))\n"
        }

        output += "\n"

        if annotations.isEmpty {
            output += "_No annotations recorded._\n"
            return output
        }

        // Each annotation
        for annotation in annotations {
            output += "### \(annotation.badgeNumber). \(annotation.displayLabel)\n"
            output += "**Location:** \(annotation.aiLocationString)\n"
            output += "**Feedback:** \(annotation.text)\n"
            output += "\n"
        }

        return output
    }

    /// Generate plain text summary (for quick reference)
    public func generatePlainText(annotations: [Annotation]) -> String {
        annotations.map { annotation in
            "\(annotation.badgeNumber). [\(annotation.displayLabel)] \(annotation.text)"
        }.joined(separator: "\n")
    }

    /// Copy markdown to clipboard
    public func copyToClipboard(
        annotations: [Annotation],
        appName: String,
        bundleIdentifier: String?,
        windowTitle: String?
    ) {
        let markdown = generateMarkdown(
            annotations: annotations,
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle
        )

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }
}
