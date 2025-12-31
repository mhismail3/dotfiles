# Frontend Layout Refactor Plan

## Goal
Rebuild the layout foundation to be robust, consistent, and work correctly across iPhone PWA, desktop browsers, and all screen sizes. Eliminate spurious scrollbars and accumulated complexity.

## Root Cause of Current Issues
1. **Spurious scrollbar**: Magic number `sessions().length > 3` conditionally enables scrolling - doesn't account for screen height
2. **Accumulated complexity**: Multiple defensive `overflow: hidden` at every layer (html, body, #root, App, pages)
3. **Inconsistent patterns**: Mix of inline styles and Tailwind classes for the same purpose
4. **Over-engineering**: ~270 lines of custom terminal touch scrolling physics

---

## Phase 1: CSS Foundation (`index.css`)

### 1.1 Simplify Root Viewport (lines 76-126)

**Current** (problematic):
- `body { position: fixed }` - can cause iOS virtual keyboard issues
- `#root { position: absolute }` - unnecessary complexity
- Multiple `overflow: hidden` at every level

**New approach**:
```css
html {
  height: 100%;
  overflow: hidden;
  background-color: var(--color-bg-base);
  -webkit-tap-highlight-color: transparent;
  -webkit-text-size-adjust: 100%;
}

body {
  height: 100%;
  margin: 0;
  overflow: hidden;
  background-color: var(--color-bg-base);
  overscroll-behavior: none;
  -webkit-user-select: none;
}

#root {
  height: 100%;
  display: flex;
  flex-direction: column;
}
```

### 1.2 Add Layout Utility Classes

```css
/* Page container - use on root of each page */
.page-layout {
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
}

/* Scrollable content - the ONLY place that scrolls on a page */
.scroll-area {
  flex: 1 1 0%;
  min-height: 0;
  overflow-y: auto;
  overflow-x: hidden;
  -webkit-overflow-scrolling: touch;
  overscroll-behavior-y: contain;
  scrollbar-width: none;
  -ms-overflow-style: none;
}
.scroll-area::-webkit-scrollbar { display: none; }

/* Fixed header/footer - doesn't scroll */
.layout-fixed { flex: none; }
```

### 1.3 Simplify Safe Area Utilities

```css
.pt-safe { padding-top: env(safe-area-inset-top, 0px); }
.pb-safe { padding-bottom: env(safe-area-inset-bottom, 0px); }
.pt-safe-header { padding-top: max(env(safe-area-inset-top, 0px), 14px); }
```

---

## Phase 2: Terminal Scrolling Simplification (`TerminalView.tsx`)

### 2.1 Remove Custom Touch Scroller (~265 lines)

Delete:
- Lines 14-28: Physics constants
- Lines 25-41: Type definitions
- Lines 43-309: `createTouchScroller()` function
- Lines 457-470: Touch event listener setup
- Related cleanup code

### 2.2 Update Terminal CSS (index.css lines 532-562)

```css
.xterm {
  height: 100%;
  width: 100%;
  overflow: hidden;
  /* Remove touch-action: none - allow native scrolling */
}

.xterm-viewport {
  overflow-y: auto;
  overflow-x: hidden;
  -webkit-overflow-scrolling: touch;
  overscroll-behavior: contain;
  touch-action: pan-y;  /* Was: none. Allow vertical touch scroll */
  scrollbar-width: none;
}
```

### 2.3 Add Smooth Scroll Option

```typescript
terminal = new Terminal({
  // ... existing options ...
  smoothScrollDuration: 100,  // Add this
});
```

---

## Phase 3: Component Updates

### 3.1 App.tsx

```tsx
// Before
<div class="h-full flex flex-col bg-bg-base text-text-primary" style={{ overflow: 'hidden' }}>

// After
<div class="page-layout bg-bg-base text-text-primary">
```

### 3.2 Sessions.tsx (Dashboard) - Main Fix

```tsx
// Before - magic number, inline styles
<main
  class="flex-1"
  style={{
    "overflow-y": sessions().length > 3 ? 'auto' : 'hidden',  // PROBLEM!
    ...7 more inline styles...
  }}
>
  <div style={{ padding: '16px', "padding-bottom": sessions().length > 3 ? '100px' : '16px' }}>

// After - clean, always works
<main class="scroll-area">
  <div class="p-4 pb-24">
```

### 3.3 Session.tsx

```tsx
// Before
<div class="flex flex-col h-full bg-bg-base"
     style={{ width: "100%", "max-width": "100%", "min-width": "0", overflow: "hidden" }}>

// After
<div class="page-layout bg-bg-base">
```

### 3.4 InputBar.tsx

```tsx
// Before
<form class="flex-none ... pb-5">

// After - proper safe area
<form class="layout-fixed ... pb-safe">
```

---

## Implementation Order

| Step | File | Changes |
|------|------|---------|
| 1 | `index.css` | Simplify root viewport styles (lines 76-126) |
| 2 | `index.css` | Add `.page-layout`, `.scroll-area`, `.layout-fixed` utilities |
| 3 | `index.css` | Update terminal CSS (lines 532-562) - change touch-action |
| 4 | `App.tsx` | Use `page-layout` class, remove inline overflow |
| 5 | `Sessions.tsx` | Remove magic number logic, use `scroll-area` class |
| 6 | `Session.tsx` | Use `page-layout`, remove redundant sizing styles |
| 7 | `TerminalView.tsx` | Delete custom touch scroller (~265 lines) |
| 8 | `InputBar.tsx` | Use `pb-safe` instead of `pb-5` |

---

## Files to Modify

- `/frontend/src/index.css` - Core layout foundation
- `/frontend/src/App.tsx` - Root wrapper
- `/frontend/src/pages/Sessions.tsx` - Dashboard (scrollbar fix)
- `/frontend/src/pages/Session.tsx` - Detail page
- `/frontend/src/components/terminal/TerminalView.tsx` - Remove ~265 lines
- `/frontend/src/components/chat/InputBar.tsx` - Safe area padding

---

## Key Principles

1. **Viewport lock at html/body only** - not at every layer
2. **Single scroll container per page** - one `.scroll-area`, content determines scrollability
3. **No magic numbers** - remove `sessions().length > 3`
4. **Tailwind-first** - inline styles only for truly dynamic values
5. **Native scrolling** - let the browser handle it

---

## Testing Checklist

- [ ] iPhone PWA: no spurious scrollbars on dashboard
- [ ] iPhone PWA: momentum scrolling works in all scroll areas
- [ ] iPhone PWA: safe areas respected (notch, home indicator)
- [ ] Desktop Chrome: wheel scrolling works everywhere
- [ ] Desktop Firefox: scrolling works, no visible scrollbars
- [ ] Terminal: streaming output scrolls smoothly
- [ ] Terminal: manual scroll during output stays in place
- [ ] Session chat: messages scroll correctly
- [ ] FAB positioning: correct on all screen sizes
