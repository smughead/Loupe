import AppKit
import SwiftUI

// MARK: - State

enum OnboardingPhase {
    case requestingPermission
    case permissionGranted
}

@Observable @MainActor
final class OnboardingState {
    var phase: OnboardingPhase = .requestingPermission
}

// MARK: - View

struct OnboardingView: View {
    let state: OnboardingState
    let onGrantAccess: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        Group {
            switch state.phase {
            case .requestingPermission:
                requestingPermissionContent
            case .permissionGranted:
                permissionGrantedContent
            }
        }
        .frame(width: 480, height: 400)
        .background(.regularMaterial)
    }

    // MARK: - Phase 1: Requesting Permission

    private var requestingPermissionContent: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 8)

            // App icon
            appIcon
                .frame(width: 80, height: 80)

            // Title
            Text("Loupe needs Accessibility access")
                .font(.title2)
                .fontWeight(.semibold)

            // Explanation
            Text("To inspect UI elements in other apps, Loupe uses the macOS Accessibility API. You'll need to grant permission in System Settings.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Instructions
            VStack(alignment: .leading, spacing: 8) {
                instructionRow(number: "1", text: "Click **Grant Access** below")
                instructionRow(number: "2", text: "Toggle **Loupe** on in System Settings")
                instructionRow(number: "3", text: "This window will close automatically")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.08))
            )
            .padding(.horizontal, 40)

            Spacer()

            // Actions
            VStack(spacing: 10) {
                Button {
                    onGrantAccess()
                } label: {
                    Text("Grant Access")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.loupeAccent)
                .controlSize(.large)

                Button {
                    onOpenSettings()
                } label: {
                    Text("Open System Settings")
                        .font(.callout)
                }
                .buttonStyle(.link)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 60)
            .padding(.bottom, 28)
        }
    }

    // MARK: - Phase 2: Permission Granted

    private var permissionGrantedContent: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.loupeAccent)
                .transition(.scale.combined(with: .opacity))

            Text("You're all set!")
                .font(.title2)
                .fontWeight(.semibold)
                .transition(.opacity)

            Spacer()
        }
        .animation(.easeOut(duration: 0.4), value: state.phase == .permissionGranted)
    }

    // MARK: - Helpers

    private var appIcon: some View {
        Group {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "eye.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.loupeAccent)
            }
        }
    }

    private func instructionRow(number: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.loupeAccent))

            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
        }
    }
}
