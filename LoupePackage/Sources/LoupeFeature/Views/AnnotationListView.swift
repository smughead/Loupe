import SwiftUI

/// View showing the list of annotations with edit/delete capabilities
public struct AnnotationListView: View {
    @ObservedObject var store: AnnotationStore
    let onCopyFeedback: () -> Void

    public init(store: AnnotationStore, onCopyFeedback: @escaping () -> Void) {
        self._store = ObservedObject(wrappedValue: store)
        self.onCopyFeedback = onCopyFeedback
    }

    public var body: some View {
        VStack(spacing: 0) {
            if store.annotations.isEmpty {
                emptyState
            } else {
                annotationList
                bottomBar
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Annotations", systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text("Click on elements while inspecting to add feedback annotations.")
        }
    }

    // MARK: - Annotation List

    private var annotationList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(store.annotations) { annotation in
                    AnnotationRow(
                        annotation: annotation,
                        onUpdate: { newText in
                            store.updateAnnotation(id: annotation.id, text: newText)
                        },
                        onDelete: {
                            store.removeAnnotation(id: annotation.id)
                        }
                    )
                }
            }
            .padding()
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Text("\(store.annotations.count) annotation\(store.annotations.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                onCopyFeedback()
            } label: {
                Label("Copy Feedback", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.bar)
    }
}

// MARK: - Annotation Row

private struct AnnotationRow: View {
    let annotation: Annotation
    let onUpdate: (String) -> Void
    let onDelete: () -> Void

    @State private var isEditing = false
    @State private var editText = ""

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Badge number
            badgeView

            // Content
            VStack(alignment: .leading, spacing: 6) {
                // Element label
                Text(annotation.displayLabel)
                    .font(.headline)

                // Location path (simplified)
                if !annotation.hierarchyPath.isEmpty {
                    Text(annotation.aiLocationString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Feedback text or edit field
                if isEditing {
                    editingView
                } else {
                    feedbackView
                }
            }

            Spacer(minLength: 0)

            // Actions
            actionButtons
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.background)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
    }

    private var badgeView: some View {
        Text("\(annotation.badgeNumber)")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Color.loupeBadge))
    }

    private var feedbackView: some View {
        Text(annotation.text)
            .font(.body)
            .foregroundStyle(.primary)
    }

    private var editingView: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Feedback", text: $editText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)

            HStack {
                Button("Cancel") {
                    isEditing = false
                    editText = annotation.text
                }
                .buttonStyle(.bordered)

                Button("Save") {
                    onUpdate(editText)
                    isEditing = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 4) {
            Button {
                editText = annotation.text
                isEditing = true
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .disabled(isEditing)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .foregroundStyle(.secondary)
    }
}
