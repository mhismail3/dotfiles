# Mini Blog Posts Feature

## Summary
Add a second class of blog posts ("mini posts") for short commentary that expands inline rather than navigating to a separate page.

## User Decisions
- Post type field: `type: mini` vs `type: long` (long is default)
- No copy link functionality for mini posts
- No auto-scroll when expanded

## Implementation Steps

### 1. Update Post Data Schema
**File:** `/src/data/posts.js`

- Parse `type` field from frontmatter (default: `'long'`)
- Make `title` optional when `type: 'mini'`
- Ensure backwards compatibility (existing posts default to long)

```javascript
// After parsing frontmatter, around line 397:
type: data.type || 'long',
title: data.title || (data.type === 'mini' ? null : slug),
```

### 2. Modify PostCard Component
**File:** `/src/components/features/PostCard.jsx`

Add expand/collapse state and conditional rendering:

1. **New state:**
   ```javascript
   const [isExpanded, setIsExpanded] = useState(false);
   const contentRef = useRef(null);
   const isMini = post.type === 'mini';
   ```

2. **Modify click handler** - expand inline for mini, navigate for long

3. **Conditional button** - chevron expand button for mini, copy link for long

4. **Conditional title** - smaller non-link title for mini (or hidden if no title)

5. **Add expandable content section** with CSS max-height transition

6. **Class modifiers:** `post-card--mini`, `no-title`, `expanded`

### 3. Create MiniPostContent Component
**File:** `/src/components/features/MiniPostContent.jsx` (new)

Lightweight content renderer for expanded mini posts:
- Reuse `post.content` (already parsed HTML)
- Render code blocks via `CodeBlock` component
- Render images via `PostImage` component
- Simpler than full PostContent (no lightbox/footnote popup management)

### 4. Add CSS Styles
**File:** `/src/styles/components/post-card.css`

Add mini post variant styles (~80 lines):
- `.post-card--mini` - card modifier
- Smaller title: `font-size: var(--text-lg)` instead of `var(--text-2xl)`
- `.no-title` variant for title-less posts
- `.mini-post-content` - expandable container with max-height transition
- Chevron rotation animation on expand
- Reduced motion support

### 5. Update Component Index
**File:** `/src/components/features/index.js`

Export the new MiniPostContent component.

## Files to Modify/Create

| File | Action |
|------|--------|
| `/src/data/posts.js` | Modify - add type field parsing |
| `/src/components/features/PostCard.jsx` | Modify - add expand/collapse logic |
| `/src/components/features/MiniPostContent.jsx` | Create - inline content renderer |
| `/src/components/features/index.js` | Modify - export new component |
| `/src/styles/components/post-card.css` | Modify - add mini post styles |

## Sample Mini Post Format

```yaml
---
date: "2025-12-29T10:00:00-08:00"
type: mini
tags:
  - commentary
---

Short commentary content here. Supports **markdown** formatting.
```

Or with a title:
```yaml
---
title: "Quick Thought"
date: "2025-12-29T10:00:00-08:00"
type: mini
tags:
  - thoughts
---

Content here...
```
