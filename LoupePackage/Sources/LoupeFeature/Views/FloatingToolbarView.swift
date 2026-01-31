import SwiftUI

// MARK: - Liquid Glass Background

extension View {
    /// Applies Apple's liquid glass effect on macOS 26+, falling back to ultraThinMaterial on earlier versions
    @ViewBuilder
    func loupeGlassBackground(cornerRadius: CGFloat = 12) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.tint(.clear), in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            self.background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
            )
        }
    }

    /// Circle variant for collapsed state
    @ViewBuilder
    func loupeGlassCircle() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.tint(.clear), in: Circle())
        } else {
            self.background(
                Circle()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            )
        }
    }
}

/// Floating toolbar for controlling inspection and managing annotations
///
/// Mental model:
/// - Collapsed = inspection OFF, target app has focus
/// - Expanded = inspection ON, Loupe owns focus
public struct FloatingToolbarView: View {
    @Binding var isExpanded: Bool
    @Binding var selectedApp: TargetApp?
    let availableApps: [TargetApp]
    let showCopySuccess: Bool
    let annotationCount: Int
    let onCopyFeedback: () -> Void
    let onClearAnnotations: () -> Void
    let onRefreshApps: () -> Void

    public init(
        isExpanded: Binding<Bool>,
        selectedApp: Binding<TargetApp?>,
        availableApps: [TargetApp],
        showCopySuccess: Bool,
        annotationCount: Int,
        onCopyFeedback: @escaping () -> Void,
        onClearAnnotations: @escaping () -> Void,
        onRefreshApps: @escaping () -> Void
    ) {
        self._isExpanded = isExpanded
        self._selectedApp = selectedApp
        self.availableApps = availableApps
        self.showCopySuccess = showCopySuccess
        self.annotationCount = annotationCount
        self.onCopyFeedback = onCopyFeedback
        self.onClearAnnotations = onClearAnnotations
        self.onRefreshApps = onRefreshApps
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
                Image(systemName: "eye.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)

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
            .frame(width: 48, height: 48)
            .loupeGlassCircle()
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Quit Loupe") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    // MARK: - Expanded State

    private var expandedToolbar: some View {
        HStack(spacing: 8) {
            // App icon picker
            AppIconPicker(
                selectedApp: $selectedApp,
                availableApps: availableApps,
                onRefresh: onRefreshApps
            )

            Divider()
                .frame(height: 24)

            // Copy feedback (with success animation)
            CopyButton(
                showSuccess: showCopySuccess,
                isDisabled: annotationCount == 0,
                action: onCopyFeedback
            )

            // Clear annotations
            ToolbarButton(
                icon: "trash",
                label: "Clear",
                isActive: false,
                isDisabled: annotationCount == 0
            ) {
                onClearAnnotations()
            }

            // Settings (placeholder, disabled)
            ToolbarButton(
                icon: "gearshape",
                label: "Settings",
                isActive: false,
                isDisabled: true
            ) {
                // Placeholder - no action yet
            }

            Divider()
                .frame(height: 24)

            // Exit (collapse toolbar and stop inspection)
            ToolbarButton(
                icon: "xmark",
                label: "Exit",
                isActive: false
            ) {
                isExpanded = false
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .loupeGlassBackground(cornerRadius: 12)
    }
}

// MARK: - Copy Button with Success Animation

private struct CopyButton: View {
    let showSuccess: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                ZStack {
                    // Clipboard icon (fades out on success)
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isDisabled ? .gray : .primary)
                        .opacity(showSuccess ? 0 : 1)

                    // Checkmark icon (fades in on success)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.green)
                        .opacity(showSuccess ? 1 : 0)
                        .scaleEffect(showSuccess ? 1.0 : 0.5)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showSuccess)

                Text(showSuccess ? "Copied!" : "Copy")
                    .font(.system(size: 9))
                    .foregroundColor(showSuccess ? .green : .secondary)
                    .opacity(isDisabled && !showSuccess ? 0.5 : 1.0)
            }
            .frame(width: 40, height: 36)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
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
