# Chat UI/UX Overhaul - Match Dashboard Retro Theme

## Problem
The chat interface uses basic Tailwind styling that doesn't match the distinctive "retro" design language used throughout the rest of the app (dashboard, modals, cards). Key missing elements:
- No offset shadows on message bubbles
- Plain tool call blocks (no card styling)
- Basic input/button styling without retro treatment
- Missing monospace font consistency
- No colored accent borders like SessionCard

## Design Language to Match (from Dashboard)

### Retro Card Pattern
- Border: `1.5px solid var(--color-bg-overlay)`
- Shadow: `3px 3px 0px rgba(0, 0, 0, 0.4)` (large) or `2px 2px 0px rgba(0, 0, 0, 0.3)` (small)
- Border-radius: 14px for cards, 10px for inputs
- Background: `var(--color-bg-surface)` or `var(--color-bg-elevated)`

### Button Pattern (from Button.tsx)
- Monospace font, 600 weight
- Retro shadow on primary variant
- 10px border-radius
- Press feedback: scale(0.97), opacity 0.8

### Typography
- Monospace (JetBrains Mono) for: titles, labels, code, metadata
- Sans (Inter) for: body text, descriptions

### Colors
- User actions: `var(--color-accent)` (#c45b37)
- Claude responses: `var(--color-bg-elevated)` (#1f1d1b)
- Borders: `var(--color-bg-overlay)` (#2a2725)
- Code: `var(--color-code-bg)` (#171615)

---

## Implementation Plan

### 1. MessageBubble.tsx Overhaul

**User Message Bubbles:**
- Keep: right-aligned, accent background, white text
- Add: Small retro shadow `2px 2px 0px rgba(0,0,0,0.3)`
- Add: Border `1px solid var(--color-accent-active)` for depth
- Change: border-radius from `rounded-2xl` to `14px` (matches cards)

**Assistant Message Bubbles:**
- Keep: left-aligned, elevated background
- Add: Border `1.5px solid var(--color-bg-overlay)`
- Add: Small retro shadow `2px 2px 0px rgba(0,0,0,0.3)`
- Change: border-radius to `14px`

**Tool Call Blocks (inside messages):**
- Complete restyle to match card pattern
- Add: Retro border + subtle shadow
- Header: Monospace font, icon + tool name + truncated summary
- Expand/collapse: Chevron icon (not arrow text)
- Input/Output sections: Code blocks with proper styling
- Consider: Colored left border by tool type (like SessionCard status)

**Code Blocks:**
- Add: Border `1px solid var(--color-code-border)`
- Add: Subtle shadow `1px 1px 0px rgba(0,0,0,0.2)`
- Ensure: Proper padding and border-radius (10px)

**Thinking Indicator:**
- Keep: Bouncing dots animation
- Consider: Style within a subtle bubble shape

### 2. InputBar.tsx Overhaul

**Container:**
- Add: Glass effect like header (`background: rgba(23, 22, 21, 0.85)`, `backdrop-filter: blur(20px)`)
- Or: Solid elevated background with top border
- Safe area handling: Keep existing iOS keyboard logic

**Textarea:**
- Match NewSessionModal input styling:
  - Border: `1.5px solid var(--color-bg-overlay)`
  - Border-radius: 12px
  - Background: `var(--color-bg-base)`
  - Font: Monospace
  - Focus: `border-color: var(--color-accent)`, `box-shadow: 0 0 0 2px var(--color-accent-muted)`
- Consider: Slight retro shadow `1px 1px 0px rgba(0,0,0,0.2)`

**Send Button:**
- Change to icon-only (arrow/send icon) for cleaner look
- Use Button component with `variant="primary"` (retro shadow)
- Square aspect ratio (42x42px to match input height)
- SVG arrow icon pointing right or up-right

### 3. Session.tsx Chat Container

**Empty State Card:**
- Already uses `.card-bordered` - verify it has retro styling
- Icon: Larger, possibly with accent glow
- Text: Monospace for "No messages yet"

**Scroll Area:**
- Background: Keep `var(--color-bg-base)`
- Padding: 16px (current p-4 is fine)
- Add subtle top gradient fade under header (optional polish)

### 4. Optional Enhancements

**Message Timestamps (if added later):**
- Style: `.text-caption` (13px, tertiary color)
- Position: Below bubble, aligned with bubble edge

**Message Actions (copy, etc. if added):**
- Appear on hover/tap
- Ghost button style
- Icon-only, small size

---

## Files to Modify

| File | Changes |
|------|---------|
| `frontend/src/components/chat/MessageBubble.tsx` | Restyle bubbles, tool calls, code blocks |
| `frontend/src/components/chat/InputBar.tsx` | Restyle input and container |
| `frontend/src/pages/Session.tsx` | Minor: empty state, possibly chat container |
| `frontend/src/index.css` | Add any new utility classes if needed |

---

## Visual Reference

### Before (Current)
```
┌─────────────────────────────┐
│  Basic rounded bubble       │  <- No shadow, basic border
│  with Tailwind classes      │
└─────────────────────────────┘
```

### After (Target)
```
┌─────────────────────────────┐
│  Retro styled bubble        │  <- 1.5px border
│  with offset shadow         │
└─────────────────────────────┘ ▄  <- 2px offset shadow
                               ▀
```

### Tool Call Block (Target)
```
┌─────────────────────────────────┐
│ 💻 Bash  ls -la /Users/...  ▼  │  <- Header with icon, monospace
├─────────────────────────────────┤
│ Input:                          │
│ ┌─────────────────────────────┐ │
│ │ ls -la /Users/moose         │ │  <- Code block, dark bg
│ └─────────────────────────────┘ │
│ Output:                         │
│ ┌─────────────────────────────┐ │
│ │ total 48                    │ │
│ │ drwxr-xr-x  15 moose ...    │ │
│ └─────────────────────────────┘ │
└─────────────────────────────────┘ ▄
                                    ▀
```

---

## Testing Checklist
- [ ] User messages have retro shadow and border
- [ ] Assistant messages have retro shadow and border
- [ ] Tool call blocks match card styling
- [ ] Code blocks have proper styling
- [ ] Input bar matches app theme
- [ ] Send button has retro shadow
- [ ] Focus states work correctly
- [ ] iOS PWA safe areas still work
- [ ] Keyboard handling unaffected
- [ ] Scrolling behavior preserved
- [ ] Dark theme colors consistent
