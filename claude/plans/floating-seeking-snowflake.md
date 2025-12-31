# Fix Terminal Width When Switching From Chat Mode

## Problem
When chat mode is the default tab, the terminal output displays at ~40 columns instead of using the full screen width. This happens because:

1. **Terminal mounts while hidden**: The terminal container uses `display: none` (CSS visibility toggle) while Chat/History views use `<Show>` (conditional rendering that unmounts)
2. **Zero dimensions during init**: When `display: none`, `clientWidth` returns 0, causing `calculateDimensions()` to fall back to iPhone defaults (40 cols)
3. **Existing fix is incomplete**: The `createEffect` at Session.tsx:577-584 only calls `requestResync()` which sends the already-wrong cached dimensions to the server - it doesn't trigger recalculation

## Root Cause Chain
```
Page loads with currentView='chat'
  → Terminal container has display:none
  → TerminalView.onMount() runs immediately
  → containerRef.clientWidth = 0
  → calculateDimensions() falls through to defaults (40 cols iPhone)
  → terminal.resize(40, 20) stores wrong dimensions
  → User switches to terminal tab
  → Container becomes visible but terminal still has 40 cols
  → ResizeObserver may fire but timing is unreliable
```

## Fix Strategy

### Option A: Add visibility prop (Recommended)
Add `isVisible` prop to TerminalView and trigger `doFitAndResize()` when visibility changes to true.

**Pros**: Clean, explicit, reliable timing
**Cons**: Requires prop threading

### Option B: Use `<Show>` for terminal
Change terminal from `display:none` to `<Show when={currentView() === 'terminal'}>`.

**Pros**: Terminal only mounts when visible, so dimensions are always correct
**Cons**: Loses terminal state (scroll position) when switching tabs, more expensive to remount

## Implementation Plan (Option A)

### Step 1: Update TerminalView props
**File**: `frontend/src/components/terminal/TerminalView.tsx`

Add `isVisible?: boolean` to `TerminalViewProps` interface (around line 9).

### Step 2: Add visibility effect in TerminalView
**File**: `frontend/src/components/terminal/TerminalView.tsx`

Add a new `createEffect` near lines 660-666 that watches `props.isVisible` and triggers `doFitAndResize()` when it becomes true:

```typescript
// Re-fit when terminal becomes visible (e.g., switching from chat tab)
createEffect(() => {
  if (props.isVisible) {
    // Use double RAF to ensure layout is fully computed after display:none → flex
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        doFitAndResize();
      });
    });
  }
});
```

### Step 3: Pass visibility prop from Session.tsx
**File**: `frontend/src/pages/Session.tsx`

Update the TerminalView usage (around line 858) to include:
```typescript
<TerminalView
  ...existing props...
  isVisible={currentView() === 'terminal'}
/>
```

### Step 4: Remove incomplete fix
**File**: `frontend/src/pages/Session.tsx`

The `createEffect` at lines 575-584 that calls `requestResync()` can be simplified or removed since the new visibility effect handles resize properly. The resync is handled by `doFitAndResize()` calling `props.onResize()`.

## Files to Modify
1. `frontend/src/components/terminal/TerminalView.tsx` - Add prop + effect
2. `frontend/src/pages/Session.tsx` - Pass visibility prop

## Verification
1. Start a new session (chat mode is default)
2. Switch to terminal tab
3. Verify Claude Code welcome box and output use full screen width
4. Switch back to chat, then to terminal again - width should remain correct
