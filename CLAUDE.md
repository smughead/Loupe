# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Build the app (from project root)
xcodebuild -workspace Loupe.xcworkspace -scheme Loupe -configuration Debug build

# Run all tests (unit + UI)
xcodebuild -workspace Loupe.xcworkspace -scheme Loupe -configuration Debug test

# Run only SPM package unit tests
xcodebuild -workspace Loupe.xcworkspace -scheme LoupeFeature test

# Run only UI tests
xcodebuild -workspace Loupe.xcworkspace -scheme Loupe -only-testing:LoupeUITests test

# Clean build
xcodebuild -workspace Loupe.xcworkspace -scheme Loupe clean
```

Open `Loupe.xcworkspace` in Xcode (not the `.xcodeproj`).

## Architecture

This is a macOS accessibility inspection app using a **Workspace + SPM Package** architecture:

```
Loupe.xcworkspace
├── Loupe.xcodeproj        # App shell (minimal - just imports LoupeFeature)
│   └── Loupe/LoupeApp.swift   # @main entry point
└── LoupePackage           # SPM package (all feature code lives here)
    └── Sources/LoupeFeature/
        ├── ContentView.swift          # Main UI (NavigationSplitView)
        ├── Models/AXElementInfo.swift # Accessibility element data
        ├── Services/AccessibilityInspector.swift  # macOS Accessibility API wrapper
        └── Views/OverlayWindowController.swift    # Transparent inspection overlay
```

### Core Components

**AccessibilityInspector** (`@Observable`, `@MainActor`): Wraps macOS Accessibility APIs (`AXUIElement*` functions). Manages permission checking, app enumeration, and element inspection at screen coordinates.

**OverlayWindowController**: Creates a transparent, borderless `NSWindow` that floats above the target app. Uses timer-based position tracking and a custom `NSView` for mouse event capture. Draws green dashed highlight rectangles around hovered elements.

**AXElementInfo**: Value type holding extracted accessibility metadata (role, identifier, title, value, frame, hierarchy path). Includes `searchPatterns` property that generates regex patterns for AI agents to locate elements in code.

### Coordinate Systems

The app handles coordinate conversion between:
- **Accessibility API**: Origin at top-left of screen
- **AppKit/NSWindow**: Origin at bottom-left of screen

Conversion happens in `OverlayWindowController` when mapping element frames to overlay positions.

## Key Patterns

**Public API requirement**: Types used by the app target must be marked `public` with `public init()`:
```swift
public struct MyView: View {
    public init() {}
    public var body: some View { ... }
}
```

**SPM dependencies**: Add to `LoupePackage/Package.swift`, not the Xcode project.

**Build configuration**: Managed via XCConfig files in `Config/` directory (Shared, Debug, Release, Tests).

**App Sandbox**: Currently disabled in `Config/Loupe.entitlements` to allow accessibility API access.

## Platform

- macOS 14.0+ (Sonoma)
- Swift 6.1
- Swift Testing framework for unit tests
- XCUITest for UI tests
