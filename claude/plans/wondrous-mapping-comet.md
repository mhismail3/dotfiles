# Fix iPad Sidebar Animation Asymmetry

## Problem

On iPad, the empty dashboard placeholder and "no session selected" placeholder have inconsistent animations when toggling the sidebar:
- **Expanding sidebar**: Placeholder shifts smoothly to the right
- **Hiding sidebar**: Placeholder jumps abruptly to the left (no animation)

The "no session selected" placeholder doesn't animate smoothly in either direction.

## Root Cause

1. **`toggleSidebar()` doesn't use `withAnimation()`**: The state change for `columnVisibility` isn't wrapped in an animation context, so dependent computed properties like `isSidebarVisible` don't animate.

2. **Conditional floating buttons lack transitions**: The `if !isSidebarVisible` block in `WelcomePage` creates/destroys views without a `.transition()` modifier telling SwiftUI how to animate the insertion/removal.

The `.animation()` modifier on NavigationSplitView only animates the split view's internal changes, not the dependent state changes in child views.

## Solution

### Change 1: Wrap `toggleSidebar()` with `withAnimation()`

**File**: `packages/ios-app/Sources/Views/ContentView.swift` (lines 140-146)

```swift
// Before:
private func toggleSidebar() {
    if columnVisibility == .detailOnly {
        columnVisibility = .all
    } else {
        columnVisibility = .detailOnly
    }
}

// After:
private func toggleSidebar() {
    withAnimation(.easeInOut(duration: 0.35)) {
        if columnVisibility == .detailOnly {
            columnVisibility = .all
        } else {
            columnVisibility = .detailOnly
        }
    }
}
```

### Change 2: Add `.transition()` to floating buttons in `WelcomePage`

**File**: `packages/ios-app/Sources/Views/ContentView.swift` (lines 446-453)

```swift
// Before:
if !isSidebarVisible {
    HStack(spacing: 12) {
        FloatingVoiceNotesButton(action: onVoiceNote)
        FloatingNewSessionButton(action: onNewSession)
    }
    .padding(.trailing, 20)
    .padding(.bottom, 24)
}

// After:
if !isSidebarVisible {
    HStack(spacing: 12) {
        FloatingVoiceNotesButton(action: onVoiceNote)
        FloatingNewSessionButton(action: onNewSession)
    }
    .padding(.trailing, 20)
    .padding(.bottom, 24)
    .transition(.opacity.combined(with: .scale(scale: 0.9)))
}
```

## Why This Works

1. **`withAnimation()` creates a unified animation context**: All state changes derived from `columnVisibility` (including `isSidebarVisible`) will animate together.

2. **`.transition()` defines how views insert/remove**: Without it, SwiftUI snaps views in/out instantly. The opacity + scale transition provides a smooth fade effect.

3. **iPhone unaffected**: `toggleSidebar()` is only called from iPad toolbar buttons, and `isSidebarVisible` is always `false` on iPhone due to the `horizontalSizeClass == .regular` check.

## Files to Modify

- `packages/ios-app/Sources/Views/ContentView.swift`

## Verification

1. Build the iOS app: `cd packages/ios-app && xcodebuild -scheme Tron -destination 'platform=iOS Simulator,name=iPad Pro'`
2. On iPad simulator:
   - Navigate to empty state (no sessions) - verify sidebar toggle animates placeholder smoothly in both directions
   - Create a session, then deselect it - verify "Select a Session" placeholder animates smoothly in both directions
3. On iPhone simulator:
   - Verify no changes to existing behavior
