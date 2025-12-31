# Plan: Update "No Sessions Yet" Empty State

## Goal
Modernize the empty state on the Sessions dashboard to be centered, use better typography, and have a refined button design.

## Changes Required

### File: `frontend/src/pages/Sessions.tsx` (lines 285-322)

#### 1. Center the empty state vertically
- Wrap the empty state in a flex container that takes full available height
- Use `align-items: center` and `justify-content: center` to center both vertically and horizontally

#### 2. Remove the icon box container
- Delete the entire icon `<div>` block (lines ~293-306) that contains the boxed `>_` icon

#### 3. Update "Start your first Claude Code session" text
- Change font-family from default (sans-serif) to `var(--font-serif)` (Source Serif 4)
- This matches the serif font used in chat message content

#### 4. Redesign the "Create session" button (outline/ghost style)
- Move the `>_` icon into the button, positioned on the left of the text
- Reduce border-radius to ~6px (less rounded than current 10px)
- Transparent background with `var(--color-accent)` border and text
- No filled background - clean outline style

## Implementation Details

```tsx
// New structure (simplified):
<Show when={!loading() && sessions().length === 0 && !error()}>
  <div style={{
    display: 'flex',
    "align-items": 'center',
    "justify-content": 'center',
    flex: '1',
    "min-height": '400px',
  }}>
    <div style={{ "text-align": 'center', padding: '48px 24px' }}>
      <p class="text-mono" style={{ ... }}>No sessions yet</p>
      <p style={{
        "font-family": 'var(--font-serif)',  // Serif font
        ...
      }}>
        Start your first Claude Code session
      </p>
      <button style={{
        display: 'inline-flex',
        "align-items": 'center',
        gap: '8px',
        "border-radius": '6px',           // Less rounded
        border: '1.5px solid var(--color-accent)',
        background: 'transparent',         // Outline style
        color: 'var(--color-accent)',
        ...
      }}>
        <span>>_</span>                    // Icon in button
        Create session
      </button>
    </div>
  </div>
</Show>
```

## Files to Modify
- `frontend/src/pages/Sessions.tsx` - lines 285-322 (empty state block)

## Verification
- Navigate to Sessions page with no sessions
- Confirm empty state is vertically and horizontally centered
- Confirm "Start your first Claude Code session" uses serif font
- Confirm button has icon on left, less rounded corners, visible border
- Confirm no standalone icon box above text
