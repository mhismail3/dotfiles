# Fix iOS PWA Safe Area Bottom Bar Regression

## Problem
On iPhone PWA, the iOS system background color shows in the home indicator area instead of the app's dark background (#0d0d0d). This appears on all screens.

## Root Cause
`position: fixed; bottom: 0` on iOS Safari/PWA does NOT extend to the absolute screen bottom - it stops at the safe area boundary. The area behind the home indicator is painted by iOS using whatever color is "behind" your fixed-positioned elements.

## Fix

### File: `src/index.css`

**1. Update the `html` rule:**

```css
html {
  -webkit-tap-highlight-color: transparent;
  -webkit-touch-callout: none;
  /* CRITICAL: Force background to extend past safe area */
  min-height: calc(100% + env(safe-area-inset-bottom, 0px));
  width: 100%;
  overflow: hidden;
  background-color: var(--color-bg-base);
}
```

The `min-height: calc(100% + env(safe-area-inset-bottom))` trick forces the html element to be taller than 100%, which pushes its background color into the bottom safe area region.

**2. Simplify the `body` rule:**

```css
body {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  margin: 0;
  padding: 0;
  width: 100%;
  height: 100%;
  overflow: hidden;
  background-color: var(--color-bg-base);
  color: var(--color-text-primary);
  font-family: var(--font-sans);
  font-size: 16px;
  line-height: 1.5;
  letter-spacing: -0.01em;
  overscroll-behavior: none;
  -webkit-user-select: none;
  user-select: none;
}
```

**3. Keep `#root` as-is** (already correct with absolute positioning)

## Why This Works
1. `min-height: calc(100% + env(safe-area-inset-bottom))` on `html` forces the document to extend past the safe area boundaries
2. The `background-color` on `html` then paints into that extended area
3. iOS uses this color to fill the home indicator region

## Verification
1. Build: `npm run build`
2. On iPhone, remove PWA from home screen and re-add it
3. Check all screens show #0d0d0d behind home indicator
