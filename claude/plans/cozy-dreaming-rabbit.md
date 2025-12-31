# Fix Terminal Flickering When "/" Shows Claude Code's Command Picker

## Problem
When "/" is typed in terminal mode, Claude Code's TUI shows a full-height command picker. This causes flickering that continues AFTER the picker is shown.

## Root Cause
ResizeObserver + terminal resize logic creates a feedback loop:

1. Claude Code draws its TUI → xterm.js internal viewport changes
2. ResizeObserver fires → `handleResize()` (50ms debounce)
3. `doFitAndResize()` calls `terminal.resize()` → more xterm layout changes
4. ResizeObserver fires again → cycle continues

**Key insight**: The container dimensions haven't actually changed - only xterm's internal viewport. The ResizeObserver is too sensitive.

## Solution: Dimension-Based Filtering

Track last known container dimensions and only trigger resize logic when they **actually change**.

### File: `frontend/src/components/terminal/TerminalView.tsx`

**Change 1**: Add dimension tracking variables (near line 349-355, after `let charHeight`)
```typescript
// Track last container dimensions to filter spurious ResizeObserver events
let lastContainerWidth: number = 0;
let lastContainerHeight: number = 0;
```

**Change 2**: Modify `handleResize()` to filter unchanged dimensions (lines 537-542)

Replace:
```typescript
function handleResize() {
  if (resizeTimeout) {
    clearTimeout(resizeTimeout);
  }
  resizeTimeout = window.setTimeout(doFitAndResize, 50);
}
```

With:
```typescript
function handleResize() {
  if (!containerRef) return;

  // Filter spurious ResizeObserver events when container size hasn't changed
  // This prevents flickering when Claude Code's TUI causes xterm viewport
  // changes without actual container resize
  const width = containerRef.clientWidth;
  const height = containerRef.clientHeight;

  if (width === lastContainerWidth && height === lastContainerHeight) {
    return; // Container unchanged, ignore
  }

  lastContainerWidth = width;
  lastContainerHeight = height;

  if (resizeTimeout) {
    clearTimeout(resizeTimeout);
  }
  resizeTimeout = window.setTimeout(doFitAndResize, 50);
}
```

**Change 3**: Initialize dimensions in `onMount()` (after `terminal.open(containerRef!)`, around line 587)
```typescript
// Initialize dimension tracking to current container size
lastContainerWidth = containerRef!.clientWidth;
lastContainerHeight = containerRef!.clientHeight;
```

## Why This Works

- ResizeObserver still fires for xterm internal changes
- handleResize checks actual container size - if unchanged, returns immediately
- No resize cascade because we don't call `terminal.resize()` or `props.onResize()`
- Legitimate resizes still work (window resize, keyboard, orientation) because they actually change container dimensions

## Verification
1. Type "/" in terminal mode - command picker should appear without flickering
2. Tap "/" toolbar button - same, no flickering
3. Rotate device - terminal should resize correctly
4. Show/hide iOS keyboard - terminal should resize correctly
5. Switch between chat/terminal tabs - terminal should size correctly
