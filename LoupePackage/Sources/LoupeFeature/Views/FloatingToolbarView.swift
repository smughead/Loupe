import SwiftUI

/// Floating toolbar for controlling inspection and managing annotations
public struct FloatingToolbarView: View {
    @Binding var isExpanded: Bool
    @Binding var isInspecting: Bool
    let annotationCount: Int
    let onCopyFeedback: () -> Void
    let onClearAnnotations: () -> Void
    let onClose: () -> Void

    public init(
        isExpanded: Binding<Bool>,
        isInspecting: Binding<Bool>,
        annotationCount: Int,
        onCopyFeedback: @escaping () -> Void,
        onClearAnnotations: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self._isExpanded = isExpanded
        self._isInspecting = isInspecting
        self.annotationCount = annotationCount
        self.onCopyFeedback = onCopyFeedback
        self.onClearAnnotations = onClearAnnotations
        self.onClose = onClose
    }

    public var body: some View {
        Group {
            if isExpanded {
                expandedToolbar
            } else {
                collapsedIcon
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
    }

    // MARK: - Collapsed State

    private var collapsedIcon: some View {
        Button {
            isExpanded = true
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 48, height: 48)
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)

                Image(systemName: "eye.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(isInspecting ? .blue : .secondary)

                // Badge for annotation count
                if annotationCount > 0 {
                    Text("\(annotationCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.blue))
                        .offset(x: 16, y: -16)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded State

    private var expandedToolbar: some View {
        HStack(spacing: 8) {
            // Play/Pause toggle
            ToolbarButton(
                icon: isInspecting ? "pause.fill" : "play.fill",
                label: isInspecting ? "Pause" : "Inspect",
                isActive: isInspecting
            ) {
                isInspecting.toggle()
            }

            Divider()
                .frame(height: 24)

            // Copy feedback
            ToolbarButton(
                icon: "doc.on.clipboard",
                label: "Copy",
                isActive: false,
                isDisabled: annotationCount == 0
            ) {
                onCopyFeedback()
            }

            // Clear annotations
            ToolbarButton(
                icon: "trash",
                label: "Clear",
                isActive: false,
                isDisabled: annotationCount == 0
            ) {
                onClearAnnotations()
            }

            Divider()
                .frame(height: 24)

            // Minimize
            ToolbarButton(
                icon: "minus",
                label: "Min",
                isActive: false
            ) {
                isExpanded = false
            }

            // Close
            ToolbarButton(
                icon: "xmark",
                label: "Close",
                isActive: false
            ) {
                onClose()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
    }
}

// MARK: - Toolbar Button

private struct ToolbarButton: View {
    let icon: String
    let label: String
    let isActive: Bool
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(iconColor)

                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .opacity(isDisabled ? 0.5 : 1.0)
            }
            .frame(width: 40, height: 36)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private var iconColor: Color {
        if isActive {
            return .blue
        } else if isDisabled {
            return .gray
        } else {
            return .primary
        }
    }
}
