# Terminal Flickering Fix - Command Picker Scroll

## Problem
When navigating the slash command picker (typing "/" then pressing down arrow), the terminal flickers and redraws the Claude Code welcome box once the menu itself needs to scroll to reveal additional options.

## Root Cause Analysis
The issue is **NOT** about WebSocket sync requests - the `initialSyncDone` flag correctly prevents post-initial syncs in `setTerminalDimensions()`.

The actual cause is `scrollIntoView({ behavior: 'smooth' })` in CommandPicker.tsx:
- When `behavior: 'smooth'` is used, the browser schedules ~300ms of continuous animation frames
- The CommandPicker is positioned with `position: fixed` and `z-index: 100` over the terminal
- The continuous repaints during the smooth scroll animation interfere with xterm's compositor layer
- This causes xterm's viewport to momentarily scroll to the top of its scrollback buffer, showing the welcome box

**Evidence:**
- Flickering only occurs when the menu needs to scroll (smooth animation triggers)
- No flickering when navigating items already visible (no scroll animation)
- The welcome box is at the TOP of xterm's scrollback - it becomes visible when viewport scrolls to top
- `initialSyncDone` flag is working correctly (verified in code analysis)

## Solution

### Fix 1: Remove smooth scroll animation (Primary)
Change `scrollIntoView` to use instant scrolling instead of smooth:

**File:** `frontend/src/components/commands/CommandPicker.tsx`
**Line:** 54

```typescript
// Before
selectedEl.scrollIntoView({ block: 'nearest', behavior: 'smooth' });

// After
selectedEl.scrollIntoView({ block: 'nearest' });
```

This eliminates the continuous animation frames that interfere with xterm rendering.

### Fix 2: Add CSS containment (Defensive)
Add CSS `contain` property to isolate CommandPicker's layout/paint from affecting the terminal:

**File:** `frontend/src/components/commands/CommandPicker.tsx`
**Lines:** 70-83 (outer div style)

Add to the existing style object:
```typescript
contain: 'layout paint',
```

### Fix 3: Alternative - Manual scroll calculation (Optional)
If instant scrolling feels too jarring, replace `scrollIntoView` with manual scroll calculation:

```typescript
createEffect(() => {
  if (!props.isOpen || !listRef) return;
  const selectedIdx = commandsStore.selectedIndex;
  const selectedEl = listRef.querySelector(`[data-index="${selectedIdx}"]`) as HTMLElement | null;
  if (selectedEl) {
    const elTop = selectedEl.offsetTop;
    const elBottom = elTop + selectedEl.offsetHeight;
    const listTop = listRef.scrollTop;
    const listBottom = listTop + listRef.clientHeight;

    if (elTop < listTop) {
      listRef.scrollTop = elTop - 8; // 8px padding
    } else if (elBottom > listBottom) {
      listRef.scrollTop = elBottom - listRef.clientHeight + 8;
    }
  }
});
```

## Files to Modify
1. `frontend/src/components/commands/CommandPicker.tsx` - Remove smooth scroll behavior

## Testing
1. Type "/" to open command picker
2. Press down arrow repeatedly until menu scrolls to reveal /export
3. Verify no flickering/welcome box redraw
4. Press up arrow to scroll back up
5. Verify no flickering in either direction
6. Verify smooth navigation feel (even with instant scrolling, `block: 'nearest'` only scrolls when needed)

## Impact
- Minimal UX change: Menu will still scroll to keep selection visible, just without smooth animation
- Major stability improvement: Eliminates terminal flickering during command picker navigation
