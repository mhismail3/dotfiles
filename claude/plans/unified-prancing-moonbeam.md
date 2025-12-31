# iOS Virtual Keyboard Handling Implementation Plan

## Problem
When the iOS virtual keyboard appears, it covers the bottom toolbar and input area instead of pushing content up. The `position: fixed` on body (required for PWA) prevents iOS's native keyboard avoidance.

## Solution
Use the `visualViewport` API to detect keyboard appearance and dynamically adjust layout height. When keyboard shows, `visualViewport.height` shrinks by the keyboard height while `innerHeight` stays the same.

## Files to Modify

| File | Change |
|------|--------|
| `frontend/src/lib/keyboard.ts` | **NEW** - Keyboard detection hook |
| `frontend/src/components/terminal/TerminalView.tsx` | Use keyboard hook, adjust height dynamically |
| `frontend/src/index.css` | Add CSS variables for keyboard state |
| `frontend/src/components/chat/InputBar.tsx` | Adjust bottom padding when keyboard visible |

## Implementation Steps

### 1. Create `keyboard.ts` utility (~60 lines)

```typescript
// frontend/src/lib/keyboard.ts
import { createSignal, onMount, onCleanup, Accessor } from 'solid-js';
import { isIOS } from './fonts';

export function useKeyboard(options?: {
  onShow?: (height: number) => void;
  onHide?: () => void;
}): {
  isVisible: Accessor<boolean>;
  keyboardHeight: Accessor<number>;
  viewportHeight: Accessor<number>;
}
```

Key logic:
- Listen to `visualViewport.resize` and `visualViewport.scroll` events
- Track stable viewport height (without keyboard)
- Detect keyboard when height diff > 150px (threshold filters address bar changes)
- Debounce events (16ms) for performance
- Handle orientation changes by resetting stable height
- Early return on non-iOS platforms (no overhead on desktop)

### 2. Integrate with TerminalView

In `TerminalView.tsx`:
- Import `useKeyboard` and `isIOS`
- Add keyboard hook with callbacks to trigger `doFitAndResize()`
- Change container height from `100%` to `${viewportHeight()}px` on iOS
- Reduce toolbar bottom padding when keyboard visible (no home indicator needed)
- Add CSS transition for smooth animation

```tsx
// Key changes:
const { isVisible, keyboardHeight, viewportHeight } = useKeyboard({
  onShow: () => requestAnimationFrame(() => doFitAndResize()),
  onHide: () => requestAnimationFrame(() => doFitAndResize()),
});

// Container style:
height: isIOS() ? `${viewportHeight()}px` : '100%',

// Toolbar padding:
'padding-bottom': isVisible() ? '10px' : 'calc(max(env(safe-area-inset-bottom), 12px) + 16px)',
```

### 3. Add CSS variables (optional, for future use)

```css
:root {
  --keyboard-height: 0px;
  --keyboard-visible: 0;
  --viewport-height: 100vh;
}
```

### 4. Update InputBar (chat mode)

Similar pattern - reduce bottom safe area padding when keyboard is visible.

## Why This Works

1. **visualViewport API**: Reports actual visible area, shrinks when keyboard appears
2. **150px threshold**: Filters false positives (address bar = ~50px, keyboard = 300-400px)
3. **Fixed body preserved**: PWA fullscreen behavior maintained
4. **Debouncing**: Prevents jank during keyboard animation
5. **Platform detection**: No overhead on desktop/Android

## Verification

1. iOS Safari (standalone PWA): Keyboard should push toolbar up
2. iOS Safari (browser): Same behavior
3. Desktop browsers: No change in behavior
4. Orientation change: Layout adjusts correctly
5. Terminal resize: FitAddon remeasures when keyboard shows/hides
