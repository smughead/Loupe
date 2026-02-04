import SwiftUI

/// Settings popover for configuring output format and naming style
public struct SettingsView: View {
    @Bindable var settings: LoupeSettings

    public init(settings: LoupeSettings) {
        self.settings = settings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("Output Settings")
                .font(.headline)
                .foregroundStyle(.primary)

            Divider()

            // Output Format
            VStack(alignment: .leading, spacing: 6) {
                Text("Output Format")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Format", selection: $settings.outputFormat) {
                    ForEach(OutputFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                Text(settings.outputFormat.description)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Naming Style (UI display only)
            VStack(alignment: .leading, spacing: 6) {
                Text("Display Style")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Style", selection: $settings.namingStyle) {
                    ForEach(NamingStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(settings.namingStyle.description)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fontDesign(.monospaced)

                Text("Affects hover labels and popovers only.\nClipboard output is always technical.")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }

        }
        .padding(16)
        .frame(width: 260)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    SettingsView(settings: LoupeSettings())
        .background(.regularMaterial)
}
#endif
