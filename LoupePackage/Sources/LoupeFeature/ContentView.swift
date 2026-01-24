import SwiftUI
import AppKit

public struct ContentView: View {
    @Bindable var coordinator: AppCoordinator

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header with app selector
            headerView

            Divider()

            // Main content
            mainContent
        }
        .frame(minWidth: 400, minHeight: 300)
        .onAppear {
            coordinator.refreshApps()
            coordinator.showToolbar()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 16) {
            // App icon
            if let app = coordinator.selectedApp, let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }

            // App selector
            VStack(alignment: .leading, spacing: 2) {
                Text("Target Application")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                appPicker
            }

            Spacer()

            // Refresh button
            Button {
                coordinator.refreshApps()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh app list")

            // Inspection status indicator
            if coordinator.isInspecting {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text("Inspecting")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.bar)
    }

    private var appPicker: some View {
        Picker("", selection: $coordinator.selectedApp) {
            Text("Select an app...").tag(nil as TargetApp?)

            ForEach(coordinator.inspector.runningApps) { app in
                HStack {
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                    Text(app.name)
                }
                .tag(app as TargetApp?)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 250)
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if !coordinator.inspector.isAccessibilityEnabled {
            permissionView
        } else if coordinator.selectedApp == nil {
            noAppSelectedView
        } else if let store = coordinator.annotationStore {
            AnnotationListView(store: store) {
                coordinator.copyFeedbackToClipboard()
            }
        } else {
            // Inspection not started yet
            readyToInspectView
        }
    }

    // MARK: - State Views

    private var permissionView: some View {
        ContentUnavailableView {
            Label("Accessibility Permission Required", systemImage: "lock.shield")
        } description: {
            Text("Loupe needs Accessibility permission to inspect UI elements in other applications.\n\nIf you already granted permission, try toggling it off and on in System Settings, then click Check Again.")
        } actions: {
            Button("Open System Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            .buttonStyle(.borderedProminent)

            Button("Grant Permission") {
                coordinator.inspector.requestAccessibilityPermission()
            }
            .buttonStyle(.bordered)

            Button("Check Again") {
                coordinator.inspector.checkAccessibilityPermission()
            }
            .buttonStyle(.bordered)
        }
    }

    private var noAppSelectedView: some View {
        ContentUnavailableView {
            Label("Select an Application", systemImage: "app.dashed")
        } description: {
            Text("Choose a running application from the dropdown above to start inspecting.")
        }
    }

    private var readyToInspectView: some View {
        ContentUnavailableView {
            Label("Ready to Inspect", systemImage: "eye")
        } description: {
            Text("Click the Play button in the floating toolbar to start inspecting \(coordinator.selectedApp?.name ?? "the app").")
        }
    }
}
