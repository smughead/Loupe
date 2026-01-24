import SwiftUI

/// Popover view for adding or editing an annotation on an accessibility element
struct AnnotationPopover: View {
    let elementRole: String
    let elementIdentifier: String?
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var annotationText = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header showing element info
            VStack(alignment: .leading, spacing: 4) {
                Text("Add Annotation")
                    .font(.headline)

                Text("\(elementRole)\(elementIdentifier.map { " (\($0))" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Text input
            TextField("Annotation text...", text: $annotationText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
                .focused($isTextFieldFocused)

            // Buttons
            HStack {
                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    onSave(annotationText)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(annotationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 280)
        .onAppear {
            isTextFieldFocused = true
        }
    }
}

/// Controller for managing the annotation popover presentation
@MainActor
final class AnnotationPopoverController {
    private var popover: NSPopover?

    /// Show the annotation popover near a view
    func show(
        relativeTo positioningRect: NSRect,
        of positioningView: NSView,
        elementRole: String,
        elementIdentifier: String?,
        onSave: @escaping (String) -> Void
    ) {
        // Dismiss any existing popover
        dismiss()

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        let content = AnnotationPopover(
            elementRole: elementRole,
            elementIdentifier: elementIdentifier,
            onSave: { [weak self] text in
                onSave(text)
                self?.dismiss()
            },
            onCancel: { [weak self] in
                self?.dismiss()
            }
        )

        popover.contentViewController = NSHostingController(rootView: content)
        popover.show(relativeTo: positioningRect, of: positioningView, preferredEdge: .maxY)

        self.popover = popover
    }

    /// Dismiss the current popover if shown
    func dismiss() {
        popover?.close()
        popover = nil
    }
}
