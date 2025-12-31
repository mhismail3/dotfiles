# Plan: Fix Chat Input Height, Terminal Width, and Loading Indicator

## Issue 1: Text Field Height Bug (Grows by 1 line per character)

### Root Cause
In `InputBar.tsx`, the height calculation uses:
- `LINE_HEIGHT = 20` (based on 14px font × 1.4 line-height)
- But `index.css` line 417 has: `textarea { font-size: 16px !important; }`

The global CSS override forces 16px font, making actual line-height ~22.4px (16 × 1.4). The calculation divides scrollHeight by 20 instead of ~22, causing the row count to increment incorrectly on each keystroke.

### Fix
**File:** `frontend/src/components/chat/InputBar.tsx`

1. Change `LINE_HEIGHT` from 20 to 23 (16px × 1.4 ≈ 22.4, rounded up)
2. Update the padding subtraction in contentHeight calculation to match actual vertical padding
3. Add `min-height` to prevent the textarea from starting at 2 lines

```tsx
const LINE_HEIGHT = 23; // 16px font (iOS override) * 1.4 line-height
```

---

## Issue 2: Terminal Width Not Full Container in Chat Mode

### Root Cause
When the terminal tab is initially hidden (`display: none`), the PTY dimensions are calculated based on a zero-width container. When the user switches to terminal view, the content was already formatted for narrow width.

Looking at `Session.tsx` lines 835-855, the terminal container uses `display: none` when not active. The terminal initialization happens via `onReady` callback, but if resize happens while hidden, dimensions will be wrong.

### Fix
**File:** `frontend/src/pages/Session.tsx`

1. When switching to terminal view (`setCurrentView('terminal')`), trigger a resize event to recalculate dimensions
2. Alternatively, ensure terminal resize is called when the view becomes visible

Add a createEffect that watches `currentView()` and triggers resize when switching to terminal:

```tsx
createEffect(() => {
  if (currentView() === 'terminal' && terminalDimensions) {
    // Slight delay to ensure DOM is visible before measuring
    requestAnimationFrame(() => {
      handleTerminalResize(terminalDimensions.cols, terminalDimensions.rows);
    });
  }
});
```

---

## Issue 3: Replace Orange Cursor with Cycling "Thinking" Text

### Current Behavior
- `MessageBubble.tsx` lines 101-113: Shows a 2px orange blinking cursor when `isStreaming && hasContent()`

### Desired Behavior
- Show on **separate line below content** (not inline)
- Layout: `[cycling dot] [phrase]...`
- Phrases: Thinking, Evaluating, Noodling, Considering, Processing, Pondering
- Animated dot that cycles through 4 styles: `●`, `○`, `◐`, `◑`

### Fix
**File:** `frontend/src/components/chat/MessageBubble.tsx`

1. Create a `StreamingIndicator` component with:
   - Array of status phrases
   - Array of dot characters that cycle
   - `setInterval` to rotate through them every ~300ms
   - Cleanup on unmount

2. Replace the streaming cursor block with the new component, rendered as a **block element** (separate line)

```tsx
const THINKING_PHRASES = [
  'Thinking',
  'Evaluating',
  'Noodling',
  'Considering',
  'Processing',
  'Pondering',
];

const DOT_CYCLE = ['●', '○', '◐', '◑'];

function StreamingIndicator() {
  const [phraseIndex, setPhraseIndex] = createSignal(0);
  const [dotIndex, setDotIndex] = createSignal(0);

  const interval = setInterval(() => {
    setDotIndex((i) => (i + 1) % DOT_CYCLE.length);
    // Change phrase every full dot cycle
    if (dotIndex() === DOT_CYCLE.length - 1) {
      setPhraseIndex((i) => (i + 1) % THINKING_PHRASES.length);
    }
  }, 300);

  onCleanup(() => clearInterval(interval));

  return (
    <div style={{
      display: 'flex',
      alignItems: 'center',
      gap: '8px',
      marginTop: '8px',
      color: 'var(--color-text-muted)',
    }}>
      <span style={{ color: 'var(--color-accent)', fontSize: '12px' }}>
        {DOT_CYCLE[dotIndex()]}
      </span>
      <span class="text-mono" style={{ fontSize: '13px' }}>
        {THINKING_PHRASES[phraseIndex()]}...
      </span>
    </div>
  );
}
```

3. Add `@keyframes bounce` to `index.css` since it's referenced but not defined

---

## Files to Modify

1. `frontend/src/components/chat/InputBar.tsx` - Fix LINE_HEIGHT constant
2. `frontend/src/components/chat/MessageBubble.tsx` - Add cycling indicator component
3. `frontend/src/pages/Session.tsx` - Trigger terminal resize on view switch
4. `frontend/src/index.css` - Add missing `bounce` keyframe animation

---

## Verification Steps

1. **Text field bug:** Type characters one at a time - height should stay at 1 line until content wraps
2. **Terminal width:** Start in chat mode, switch to terminal - output should be full width
3. **Loading indicator:** Send a message, watch the assistant response - should show cycling text instead of cursor
