import AppKit
import Foundation

/// Service for copying rich content (text + image) to the clipboard
/// Uses RTFD format to embed images within text so both appear when pasted
public struct RichClipboard {

    public init() {}

    // MARK: - Public API

    /// Copy both text and image data to the clipboard as RTFD
    /// The image is embedded at the end of the text, so both appear when pasted
    /// - Parameters:
    ///   - text: The text content (typically markdown)
    ///   - imageData: PNG image data (optional)
    public func copyTextAndImage(text: String, imageData: Data?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        guard let imageData = imageData,
              let image = NSImage(data: imageData) else {
            // No image - just copy text
            pasteboard.setString(text, forType: .string)
            return
        }

        // Create attributed string with the text
        let fontSize: CGFloat = 12
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.textColor
        ]

        let attributedString = NSMutableAttributedString(string: text, attributes: attributes)

        // Add separator before image
        attributedString.append(NSAttributedString(string: "\n\n--- Screenshot ---\n\n", attributes: attributes))

        // Create image attachment
        let attachment = NSTextAttachment()
        attachment.image = image

        // Scale image if too large (max 800px wide)
        let maxWidth: CGFloat = 800
        if image.size.width > maxWidth {
            let scale = maxWidth / image.size.width
            let newSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            attachment.bounds = CGRect(origin: .zero, size: newSize)
        }

        let imageString = NSAttributedString(attachment: attachment)
        attributedString.append(imageString)

        // Convert to RTFD data
        let range = NSRange(location: 0, length: attributedString.length)
        if let rtfdData = attributedString.rtfd(from: range, documentAttributes: [:]) {
            // Write RTFD (rich text with attachments) - this embeds the image
            pasteboard.setData(rtfdData, forType: .rtfd)
        }

        // Also include plain text as fallback for apps that don't support RTFD
        pasteboard.setString(text, forType: .string)

        // Also include the image separately for apps that prefer raw images
        pasteboard.setData(imageData, forType: .png)
    }

    /// Copy text only to the clipboard
    /// - Parameter text: The text content
    public func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Copy image only to the clipboard
    /// - Parameter imageData: PNG image data
    public func copyImage(_ imageData: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(imageData, forType: .png)
    }

    /// Copy text with an NSImage to the clipboard
    /// - Parameters:
    ///   - text: The text content
    ///   - image: The NSImage to include
    public func copyTextAndImage(text: String, image: NSImage?) {
        guard let image = image,
              let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            // Fall back to text only
            copyText(text)
            return
        }

        copyTextAndImage(text: text, imageData: pngData)
    }

    // MARK: - Convenience Methods

    /// Copy markdown and optional screenshot for feedback
    /// - Parameters:
    ///   - markdown: Formatted markdown feedback
    ///   - screenshot: Optional screenshot data
    ///   - includeImage: Whether to include the image (from settings)
    public func copyFeedback(markdown: String, screenshot: Data?, includeImage: Bool) {
        if includeImage && screenshot != nil {
            copyTextAndImage(text: markdown, imageData: screenshot)
        } else {
            copyText(markdown)
        }
    }
}
