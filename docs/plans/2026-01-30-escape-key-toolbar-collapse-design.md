# Escape Key and Toolbar Collapse Behavior

**Date:** 2026-01-30
**Status:** Approved

## Problem

When in Inspect Element mode, pressing Escape multiple times can cause the overlay to close while the toolbar remains expanded. This creates an "orphaned" state where:
- The toolbar is expanded (showing all controls)
- But there's no overlay window to interact with
- The user has no way to recover without re-selecting the app or minimizing/reopening

## Solution

### 1. Progressive Escape Key Behavior

Escape key presses follow a logical progression:

| Current State | Escape Action |
|---------------|---------------|
| Annotation popover open | Dismiss popover only |
| Inspection active (no popover) | Collapse toolbar → ends inspection |

**Focus behavior:** When Escape collapses the toolbar, Loupe remains the active app. Users switch apps manually.

### 2. Annotation Visibility Tied to Toolbar State

Annotations are only visible when the toolbar is expanded:

| Toolbar State | Badge Overlays on Target App | Badge Count on Toolbar |
|---------------|------------------------------|------------------------|
| Expanded | Visible | N/A (not shown in expanded view) |
| Collapsed | Hidden | Shown (e.g., "2" badge on eye icon) |

This provides clear visual feedback about inspection state while preserving annotations across sessions.

### 3. Exit Button Unchanged

The "Exit" button with X icon remains as-is. Users understand "Exit" means exit inspection mode, not quit the app.

## Implementation

### A. OverlayWindowController Changes

1. Replace `onEscape: () -> Void` callback with `onRequestCollapse: () -> Void`
2. In `keyDown` handler for Escape:
   - If popover is active, dismiss it (existing behavior via popover's own handler)
   - Otherwise, call `onRequestCollapse()`
3. Add `showAnnotationBadges: Bool` property that controls whether badges are drawn

### B. AppCoordinator Changes

1. Pass collapse callback to OverlayWindowController:
   ```swift
   controller.onRequestCollapse = { [weak self] in
       self?.floatingToolbar.isExpanded = false
   }
   ```
2. When `isExpanded` changes to `false`, existing `onCollapse` handler already calls `stopInspection()`

### C. FloatingToolbarWindowController Changes

No changes needed - setting `isExpanded = false` already triggers the collapse flow.

### D. Badge Visibility in OverlayView

Pass `isExpanded` state through to control badge rendering:
- When expanded: draw annotation badges
- When collapsed: skip badge drawing (overlay won't be visible anyway, but good for correctness)

## Files to Modify

1. `LoupePackage/Sources/LoupeFeature/Views/OverlayWindowController.swift`
2. `LoupePackage/Sources/LoupeFeature/Services/AppCoordinator.swift`

## Testing

1. Expand toolbar, start inspection
2. Press Escape → toolbar should collapse, overlay should close
3. Expand again → annotations should reappear
4. Open annotation popover, press Escape → popover closes, toolbar stays expanded
5. Press Escape again → toolbar collapses
6. Verify badge count shows on collapsed icon when annotations exist
