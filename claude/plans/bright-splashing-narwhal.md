# Fix: Model Pill Interaction Blocked in iOS Chat View

## Problem
The model pill in the chat view cannot be tapped/dragged, and its popup menu cannot be scrolled. This is specific to the model pill - other elements like the context progress pill and settings button work correctly with iOS 26 liquid glass native behavior.

## Root Cause Analysis

**File:** `packages/ios-app/Sources/Views/InputBar/StatusPillBar.swift`

### Issue 1: `.geometryGroup()` Modifier (PRIMARY BLOCKER)
**Location:** Line 160

```swift
private var modelPickerMenu: some View {
    ModelPickerMenuContent(...) {
        HStack(spacing: 4) { ... }
            .contentShape(Capsule())
            .geometryGroup()  // ← THIS BREAKS GESTURE RECOGNITION
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: modelName)
    }
}
```

The `.geometryGroup()` modifier creates an isolated coordinate space that **breaks hit-testing for Menu labels**. It prevents:
- Tap gestures from reaching the menu trigger
- Drag gestures from working on the popup
- Scrolling inside the menu content

### Issue 2: Missing `.interactive()` on glassEffect (SECONDARY)
**Location:** Lines 154-158

```swift
.background {
    Capsule()
        .fill(.clear)
        .glassEffect(.regular.tint(Color.tronPhthaloGreen.opacity(0.35)), in: .capsule)
        // ← MISSING .interactive() modifier
}
```

Compare with the working token stats pill (line 246):
```swift
.glassEffect(.regular.tint(Color.tronPhthaloGreen.opacity(0.35)).interactive(), in: .capsule)
```

The `.interactive()` modifier enables proper touch handling with iOS 26 liquid glass.

## Why Other Elements Work

| Element | Implementation | .geometryGroup() | .interactive() | Works? |
|---------|----------------|------------------|----------------|--------|
| Model pill | ModelPickerMenuContent | YES | NO | NO |
| Reasoning pill | Direct Menu | NO | NO | YES |
| Token stats pill | Button | NO | YES | YES |

The reasoning menu works because it has no `.geometryGroup()`. The token pill works because it's a simple Button with `.interactive()`.

## Fix

**File:** `packages/ios-app/Sources/Views/InputBar/StatusPillBar.swift`

### Change 1: Remove `.geometryGroup()` from model pill label (lines 135-164)

Replace the `modelPickerMenu` computed property:

```swift
private var modelPickerMenu: some View {
    ModelPickerMenuContent(
        models: cachedModels,
        notificationName: .modelPickerAction
    ) {
        HStack(spacing: 4) {
            Image(systemName: "cpu")
                .font(TronTypography.pill)
            Text(modelName.shortModelName)
                .font(TronTypography.pillValue)
                .contentTransition(.interpolate)
            if !readOnly {
                Image(systemName: "chevron.up.chevron.down")
                    .font(TronTypography.labelSM)
            }
        }
        .foregroundStyle(readOnly ? .tronEmerald.opacity(0.5) : .tronEmerald)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular.tint(Color.tronPhthaloGreen.opacity(0.35)), in: .capsule)
        }
        .contentShape(Capsule())
        // REMOVED: .geometryGroup()
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: modelName)
    }
    .disabled(readOnly)
}
```

**Key change:** Remove line 160 (`.geometryGroup()`)

### Why This Fix Is Robust

1. **Directly addresses root cause**: `.geometryGroup()` isolates geometry and breaks Menu hit-testing
2. **Matches working patterns**: The reasoning menu (lines 168-209) uses nearly identical code without `.geometryGroup()` and works correctly
3. **Minimal change**: Single line removal preserves all other functionality
4. **Animation still works**: The `.animation()` modifier on line 161 handles model name transitions without needing `.geometryGroup()`

### Optional Enhancement: Add `.interactive()` to glassEffect

If further touch responsiveness is needed, consider changing the background glass effect to include `.interactive()`:

```swift
.glassEffect(.regular.tint(Color.tronPhthaloGreen.opacity(0.35)).interactive(), in: .capsule)
```

However, this may not be necessary since Menu components handle their own hit-testing once `.geometryGroup()` is removed.

## Verification

1. Build the iOS app: `cd packages/ios-app && xcodebuild -scheme TronMobile -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
2. Run on iOS 26 simulator or device
3. Verify:
   - [ ] Model pill can be tapped to open menu
   - [ ] Model pill popup can be scrolled (if it has many items)
   - [ ] Model pill can be dragged with liquid glass behavior
   - [ ] Model name animation still works when switching models
   - [ ] Reasoning pill still works correctly
   - [ ] Token stats pill still works correctly
