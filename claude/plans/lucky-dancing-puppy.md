# PWA Viewport Scroll Fix Plan

## Problem
On iOS PWA, the viewport rubber-bands/bounces when scrolling even when content doesn't need scrolling:
- **Session page (empty chat)**: Entire window shifts up/down when swiping
- **Dashboard (few sessions)**: Scrollbar appears but content doesn't actually scroll

## Root Cause
The CSS safe-area fix (`html { min-height: calc(100% + safe-area-insets) }`) extends the document past the viewport. Despite `body { position: fixed; overflow: hidden; overscroll-behavior: none }`, iOS WebKit still allows rubber-banding because the html element is technically larger than the viewport.

## Constraint
**DO NOT modify CSS** - the safe-area styling prevents a visible status bar at the bottom and must be preserved.

## Solution: JavaScript Touch Event Interception

Create a global touch handler that prevents `touchmove` default behavior when the touch isn't inside a legitimately scrollable area.

### Implementation

**File: `/frontend/src/lib/preventOverscroll.ts`** (new)

Create a utility hook `usePreventOverscroll()` that:
1. Attaches a `touchmove` listener to `document` with `{ passive: false }`
2. On each touch move, walks up from `event.target` to find scrollable containers
3. Checks if the container has actual scrollable content (`scrollHeight > clientHeight`)
4. If no scrollable container is found, calls `event.preventDefault()`
5. Cleans up on unmount

```typescript
// Pseudo-logic:
function handleTouchMove(e: TouchEvent) {
  let target = e.target as HTMLElement | null;

  while (target && target !== document.body) {
    const style = getComputedStyle(target);
    const isScrollable = style.overflowY === 'auto' || style.overflowY === 'scroll';
    const hasContent = target.scrollHeight > target.clientHeight;

    if (isScrollable && hasContent) {
      // Allow scroll - this container has content
      return;
    }
    target = target.parentElement;
  }

  // No scrollable container found - prevent body scroll
  e.preventDefault();
}
```

**File: `/frontend/src/App.tsx`** (modify)

Add the hook call in the root App component:
```typescript
import { usePreventOverscroll } from './lib/preventOverscroll';

export default function App(props: ParentProps) {
  usePreventOverscroll();
  // ... rest unchanged
}
```

### Edge Cases to Handle

1. **Input fields**: Allow scroll inside focused inputs/textareas
2. **Horizontal scroll**: Only block vertical overscroll, allow horizontal
3. **Scrolled to bounds**: When a scrollable container is at its scroll limits, still allow internal scroll but prevent body scroll escape

### Files to Modify
1. `frontend/src/lib/preventOverscroll.ts` - Create new
2. `frontend/src/App.tsx` - Import and call hook

### Verification
Test on iOS PWA:
- Empty chat view should not rubber-band
- Dashboard with few sessions should not show scrollbar/bounce
- Scrollable content (many messages, many sessions) should still scroll normally
- Terminal view should continue working (has its own touch handler)
