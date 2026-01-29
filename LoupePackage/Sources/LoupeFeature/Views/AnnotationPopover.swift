import SwiftUI

/// Popover view for adding or editing an annotation on an accessibility element
struct AnnotationPopover: View {
    let element: AXElementInfo
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var annotationText = ""
    @State private var isDetailsExpanded = false
    @FocusState private var isTextFieldFocused: Bool

    private var elementSummary: String {
        element.displayLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Expandable element details header
            DisclosureGroup(isExpanded: $isDetailsExpanded) {
                elementDetailsView
            } label: {
                Text(elementSummary)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            Divider()

            // Feedback text input
            TextField("What should change?", text: $annotationText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
                .focused($isTextFieldFocused)

            // Action buttons
            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { onSave(annotationText) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(annotationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 320)
        .onAppear { isTextFieldFocused = true }
    }

    private var elementDetailsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            detailRow("Role", element.role)
            if let id = element.identifier, !id.isEmpty {
                detailRow("Identifier", id)
            }
            if let title = element.title, !title.isEmpty {
                detailRow("Title", title)
            }
            if let value = element.value, !value.isEmpty {
                detailRow("Value", value)
            }
            if !element.hierarchyPath.isEmpty {
                detailRow("Path", element.hierarchyPath.joined(separator: " > "))
            }
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.vertical, 8)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text("\(label):")
                .foregroundStyle(.tertiary)
                .frame(width: 70, alignment: .trailing)
            Text(value)
                .textSelection(.enabled)
        }
    }
}

/// Controller for managing the annotation popover presentation
@MainActor
final class AnnotationPopoverController {
    private var popover: NSPopover?
    private var onDismissCallback: (() -> Void)?

    /// Show the annotation popover near a view
    func show(
        relativeTo positioningRect: NSRect,
        of positioningView: NSView,
        preferredEdge: NSRectEdge = .maxY,
        element: AXElementInfo,
        onSave: @escaping (String) -> Void,
        onDismiss: (() -> Void)? = nil
    ) {
        // Dismiss any existing popover
        dismiss()

        self.onDismissCallback = onDismiss

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        let content = AnnotationPopover(
            element: element,
            onSave: { [weak self] text in
                onSave(text)
                self?.dismiss()
            },
            onCancel: { [weak self] in
                self?.dismiss()
            }
        )

        popover.contentViewController = NSHostingController(rootView: content)
        popover.show(relativeTo: positioningRect, of: positioningView, preferredEdge: preferredEdge)

        self.popover = popover
    }

    /// Dismiss the current popover if shown
    func dismiss() {
        popover?.close()
        popover = nil
        onDismissCallback?()
        onDismissCallback = nil
    }
}
