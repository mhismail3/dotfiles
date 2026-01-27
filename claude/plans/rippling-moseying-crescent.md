# Fix: iOS Model Picker Pill Clipping on Model Switch

## Problem
When switching from a model with a shorter name (e.g., "Medium") to a longer name (e.g., "GPT-5.2 Codex"), the model picker pill appears cut off on either side, then abruptly snaps to the correct width.

## Root Cause
In `StatusPillBar.swift`, the model picker pill's width is derived from its content (HStack with icon + text + chevron). The existing animation modifiers (lines 125-127) only animate:
- `hasAppeared` - initial appearance
- `showModelPill` - visibility toggling
- `showReasoningPill` - visibility toggling

None of these animate the width change when `modelName` changes to a different length.

## Fix
Add an animation modifier that responds to `modelName` changes so the pill width animates smoothly.

### File to Modify
`/Users/moose/Downloads/projects/tron/packages/ios-app/Sources/Views/InputBar/StatusPillBar.swift`

### Change
Add animation for `modelName` at line 128 (after the existing animations):

```swift
.animation(.spring(response: 0.3, dampingFraction: 0.8), value: modelName)
```

This tells SwiftUI to animate any layout changes that occur when `modelName` changes, resulting in a smooth width transition for the pill.

## Verification
1. Build and run the iOS app on simulator or device
2. Open a chat session
3. Tap the model picker pill and switch from a short model name (e.g., "Opus 4") to a longer one (e.g., "GPT-5.2 Codex")
4. Observe the pill width animates smoothly instead of clipping/snapping
5. Switch back to a shorter model name and verify the reverse animation also works smoothly
