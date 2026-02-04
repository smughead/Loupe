import SwiftUI
import AppKit

/// A compact app icon picker that shows the selected app's icon
/// and expands to a picker when clicked
public struct AppIconPicker: View {
    @Binding var selectedApp: TargetApp?
    let availableApps: [TargetApp]
    let onRefresh: () -> Void

    @State private var isExpanded = false

    public init(
        selectedApp: Binding<TargetApp?>,
        availableApps: [TargetApp],
        onRefresh: @escaping () -> Void
    ) {
        self._selectedApp = selectedApp
        self.availableApps = availableApps
        self.onRefresh = onRefresh
    }

    public var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 4) {
                appIconView

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 36)
        }
        .buttonStyle(AppIconPickerButtonStyle())
        .popover(isPresented: $isExpanded, arrowEdge: .bottom) {
            appPickerPopover
        }
    }

    // MARK: - App Icon View

    private var appIconView: some View {
        Group {
            if let app = selectedApp, let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .help("Target: \(app.name)\nClick to change")
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 34, height: 34)

                    Image(systemName: "app.dashed")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }
                .help("Select target app")
            }
        }
    }

    // MARK: - Picker Popover

    private var appPickerPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Select Target App")
                    .font(.headline)

                Spacer()

                Button {
                    onRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help("Refresh app list")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // App list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(availableApps) { app in
                        AppPickerRow(
                            app: app,
                            isSelected: selectedApp?.id == app.id
                        ) {
                            selectedApp = app
                            isExpanded = false
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 280)
    }
}

// MARK: - App Icon Picker Button Style

/// Custom button style for the app icon picker with press feedback.
private struct AppIconPickerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

// MARK: - App Picker Row

private struct AppPickerRow: View {
    let app: TargetApp
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                // App icon
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "app.fill")
                        .frame(width: 24, height: 24)
                }

                // App name
                Text(app.name)
                    .font(.body)
                    .lineLimit(1)

                Spacer()

                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.loupeAccent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - NSImage Grayscale Extension

public extension NSImage {
    /// Returns a grayscale version of the image
    func grayscale() -> NSImage {
        guard let tiffData = self.tiffRepresentation,
              let ciImage = CIImage(data: tiffData) else {
            return self
        }

        let filter = CIFilter(name: "CIColorControls")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(0.0, forKey: kCIInputSaturationKey)

        guard let outputImage = filter?.outputImage else {
            return self
        }

        let rep = NSCIImageRep(ciImage: outputImage)
        let grayscaleImage = NSImage(size: rep.size)
        grayscaleImage.addRepresentation(rep)

        return grayscaleImage
    }
}
