# Plan: Session Page UI Enhancements

## Summary
Improve the session page UI with three targeted changes:
1. Enhanced connection banner with full height and frosted glass blur
2. Fix conditional display logic for empty states
3. Update info dialog styling to match dashboard (including outline buttons)

## Files to Modify
- `/frontend/src/components/ui/ConnectionStatus.tsx` - Banner improvements
- `/frontend/src/pages/Session.tsx` - Display logic and styling

## Changes

### 1. ConnectionStatus.tsx - Enhanced Banner with Frosted Glass
**Current**: Small banner with padding `8px 16px`, no blur effect

**Changes**:
- Increase vertical padding to fill status bar height (`16px` vertical)
- Add `backdrop-filter: blur(12px)` for frosted glass effect
- Keep semi-transparent backgrounds so blurred content shows through

```tsx
// Update base styles in bannerStyle()
const base = {
  // ... existing
  padding: '16px 16px',
  'backdrop-filter': 'blur(12px)',
  '-webkit-backdrop-filter': 'blur(12px)',
};

// Keep backgrounds semi-transparent for frosted effect
case 'connecting':
  background: 'rgba(212, 166, 68, 0.25)',  // Slightly more opaque than current 0.15
```

### 2. Session.tsx - Fix Conditional Display Logic
**Current Problem**: Both "Session ended" AND "No messages yet" cards show simultaneously when session is stopped with no messages.

**Logic Change**:
```tsx
// Current: "No messages yet" shows when:
messages().length === 0 && !streamingContent()

// Fixed: "No messages yet" shows when:
messages().length === 0 && !streamingContent() && !isSessionStopped()
```

This ensures:
- Session stopped → Only show "Session ended" card
- Session active + no messages → Only show "No messages yet" card
- Session active + has messages → Show messages

### 3. Session.tsx - Restyle Info Dialogs to Match Dashboard

**Target Style** (from dashboard "No sessions yet"):
- No card border/shadow (transparent background)
- Simple centered text
- Title: mono font, primary color
- Subtitle: serif font, tertiary color
- Button with accent border (outline style)

**Apply to "Session ended" card (lines 740-775)**:
- Remove card-bordered class
- Remove background styling
- Use transparent container with just centered content
- Title: mono font, `15px`, `600` weight
- Subtitle: serif font, `14px`, tertiary color
- Resume button: outline style with accent border (transparent bg, accent border/text)

```tsx
// Button styling to match dashboard
style={{
  display: 'inline-flex',
  alignItems: 'center',
  gap: '8px',
  padding: '10px 18px',
  borderRadius: '6px',
  border: '1.5px solid var(--color-accent)',
  background: 'transparent',
  color: 'var(--color-accent)',
  fontFamily: 'var(--font-mono)',
  fontSize: '13px',
  fontWeight: '600',
  cursor: 'pointer',
}}
```

**Apply to "No messages yet" card (lines 782-818)**:
- Remove retro card styling (background, border, box-shadow)
- Match the clean centered text style from dashboard

## Implementation Order
1. Fix the conditional logic first (simplest change)
2. Update ConnectionStatus banner styling
3. Restyle the two info dialogs to match dashboard
4. Test in browser with dev-browser/Playwright

## Expected Result
- Connection banner: Full-height, blurred, obscures content
- Stopped session with no messages: Only shows "Session ended"
- Active session with no messages: Only shows clean "No messages yet"
- Both info dialogs: Clean minimal style like dashboard
