# UI/UX Improvements Plan

## Overview
Address 7 UI bugs/improvements across the dashboard, new session modal, and chat tab.

---

## 1. Dashboard Logo & Title Position
**File:** `frontend/src/pages/Sessions.tsx` (line 132)

**Current:** Header has `padding-inline: 16px`, `padding-bottom: 14px`, no padding-top
**Change:** Add `padding-top: 6px` to move logo/title down slightly

```tsx
// Line 132: Update header style
style={{ "padding-inline": '16px', "padding-top": '6px', "padding-bottom": '14px' }}
```

---

## 2. Search & Analytics Buttons - Add Hover/Click Animations
**File:** `frontend/src/pages/Sessions.tsx` (lines 170-214) + `frontend/src/index.css`

**Current:** Buttons use `.pressable` class which only scales on active (no hover effect)

**Changes:**
1. Add new CSS class `.icon-btn` for interactive icon buttons
2. Apply to both search button (line 172) and analytics link (line 196)

**Add to `index.css`:**
```css
.icon-btn {
  transition: all 0.15s ease;
}
.icon-btn:hover {
  background: var(--color-bg-elevated);
  border-color: var(--color-text-tertiary);
  transform: translateY(-1px);
  box-shadow: 2px 2px 0px rgba(0, 0, 0, 0.2);
}
.icon-btn:active {
  transform: scale(0.95) translateY(0);
  box-shadow: none;
}
```

**Update buttons:** Replace `class="pressable"` with `class="icon-btn"`

---

## 3. Empty Dashboard State ("No sessions yet")
**File:** `frontend/src/pages/Sessions.tsx` (lines 285-309)

**Current:**
- 64x64px circle icon container with `>_` terminal symbol
- Text uses `color-text-secondary`, no monospace class on heading
- No card background/shadow styling

**Changes:**
- Add card styling (background, border, retro shadow) to container
- Change icon container from circle to rounded square (14px radius)
- Add accent background to icon container (matching chat empty state)
- Use `text-mono` class and primary color for heading
- Add descriptive secondary text

**Updated implementation (lines 286-308):**
```tsx
<div style={{
  "text-align": 'center',
  padding: '48px 24px',
  background: 'var(--color-bg-surface)',
  "border-radius": '14px',
  border: '1.5px solid var(--color-bg-overlay)',
  "box-shadow": '3px 3px 0px rgba(0, 0, 0, 0.3)',
  "max-width": '320px',
  margin: '0 auto'
}}>
  <div style={{
    width: '56px', height: '56px',
    margin: '0 auto 20px',
    "border-radius": '14px',
    background: 'var(--color-accent-muted)',
    border: '1px solid var(--color-accent)',
    display: 'flex', "align-items": 'center', "justify-content": 'center',
    "box-shadow": '2px 2px 0px rgba(0, 0, 0, 0.2)',
  }}>
    <span class="text-mono" style={{ color: 'var(--color-accent)', "font-size": '22px', "font-weight": '600' }}>&gt;_</span>
  </div>
  <p class="text-mono" style={{ color: 'var(--color-text-primary)', "font-size": '15px', "font-weight": '600', "margin-bottom": '6px' }}>
    No sessions yet
  </p>
  <p style={{ color: 'var(--color-text-tertiary)', "font-size": '13px', "margin-bottom": '20px' }}>
    Start your first Claude Code session
  </p>
  <Button onClick={() => setShowNewSession(true)}>Create session</Button>
</div>
```

---

## 4. New Session Modal - Fix Model Dropdown Close Behavior
**File:** `frontend/src/components/chat/NewSessionModal.tsx`

**Bug:** Model dropdown stays open when clicking project text field or elsewhere
**Root Cause:**
- Project input (line 338-339): `onFocus` opens dropdown but doesn't close model dropdown
- Model button (line 419-420): `onBlur` with 150ms delay doesn't reliably close

**Solution:** Coordinate dropdown states - when one opens, close the other

**Changes:**

1. **Update project input `onFocus` (line 338):**
```tsx
onFocus={() => {
  setShowModelDropdown(false);  // Close model dropdown first
  setShowProjectDropdown(true);
}}
```

2. **Update model button `onClick` (line 419):**
```tsx
onClick={() => {
  setShowProjectDropdown(false);  // Close project dropdown first
  setShowModelDropdown(!showModelDropdown());
}}
```

3. **Add `onFocus` to prompt textarea to close both dropdowns** (find the textarea after model dropdown)

---

## 5. Chat Tab - Empty State ("No messages yet")
**File:** `frontend/src/pages/Session.tsx` (lines 781-817)

**Current:** Already has good styling with:
- Card background, border, retro shadow ✓
- 56x56px icon with accent styling ✓
- `text-mono` on heading, proper colors ✓

**Assessment:** This is already consistent with site styling. **No changes needed** - the chat empty state matches the pattern we're applying to the dashboard empty state.

---

## 6. Chat Tab - Reduce Input Field Size
**SKIPPED** - User requested no changes to input field size.

---

## 7. Chat Tab - Reduce Tab Size
**File:** `frontend/src/pages/Session.tsx` (lines 687, 696-697)

**Current:**
- Container padding: 3px (line 687)
- Tab padding: 6px 12px (line 696)
- Font size: 11px (line 697)

**Changes:**
```tsx
// Line 687: Reduce container padding
padding: '2px',  // Was 3px

// Line 696: Reduce tab padding
padding: '5px 10px',  // Was 6px 12px

// Line 697: Slightly smaller font
"font-size": '10px',  // Was 11px
```

---

## Files Summary

| File | Changes |
|------|---------|
| `frontend/src/pages/Sessions.tsx` | Logo padding, button class, empty state styling |
| `frontend/src/components/chat/NewSessionModal.tsx` | Dropdown close coordination |
| `frontend/src/pages/Session.tsx` | Tab sizing only (empty state already good) |
| `frontend/src/index.css` | Add `.icon-btn` class for hover/active effects |

---

## Testing Plan
1. Dashboard: Logo/title slightly lower
2. Dashboard: Search/analytics buttons have hover lift + active press
3. Dashboard: Empty state has card styling with accent icon
4. New Session Modal: Model dropdown closes when clicking project field
5. Chat Tab: Tab buttons slightly smaller padding
