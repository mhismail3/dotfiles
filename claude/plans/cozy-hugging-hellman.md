# Plan: Add Unique Canvas ID Generation for RenderAppUI

## Problem
When canvas JSON files are saved to `~/.tron/artifacts/canvases/`, if the agent reuses the same `canvasId`, the file gets overwritten. The user wants each canvas to have a unique name by default with a random suffix.

## Current Behavior
- `canvasId` is a **required** parameter in RenderAppUI
- Filename is directly `${canvasId}.json` with no uniqueness guarantee
- If same canvasId is used, file is overwritten

## Solution
Make `canvasId` optional and auto-generate a descriptive unique ID when not provided.

**Generated format:** `<word1>-<word2>-<word3>-<8-char-random>`

Examples:
- Title "Settings Panel" → `settings-panel-a7f3x9k2`
- Title "User Registration Form" → `user-registration-form-b2d4e6f8`
- No title, root is VStack → `canvas-vstack-c3e5g7i9`

### Files to Modify

1. **`packages/core/src/tools/render-app-ui.ts`** (lines 77-98, 108-116)
   - Remove `canvasId` from `required` array (line 97)
   - Add `generateCanvasId()` helper function
   - At start of `execute()`, auto-generate canvasId if not provided
   - Update tool description to mention auto-generation

2. **`packages/core/src/ui/components.ts`** (line 372)
   - Change `canvasId: string` to `canvasId?: string` in `RenderAppUIParams` interface

3. **`packages/core/src/ui/validators.ts`** (lines 236-239)
   - Remove the check that requires canvasId
   - Keep validation that if canvasId IS provided, it must be a string

### Implementation Details

```typescript
// In render-app-ui.ts - add import at top:
import { randomUUID } from 'crypto';

// Helper function to generate descriptive canvas ID:
function generateCanvasId(title?: string, ui?: { $tag?: string }): string {
  const suffix = randomUUID().replace(/-/g, '').slice(0, 8);

  // Extract words from title if available
  if (title) {
    const words = title
      .toLowerCase()
      .replace(/[^a-z0-9\s]/g, '')
      .split(/\s+/)
      .filter(w => w.length > 0)
      .slice(0, 3);
    if (words.length > 0) {
      return `${words.join('-')}-${suffix}`;
    }
  }

  // Fall back to root component type
  const rootTag = ui?.$tag?.toLowerCase() || 'canvas';
  return `canvas-${rootTag}-${suffix}`;
}

// In execute() - generate canvasId if not provided:
if (!params.canvasId) {
  params.canvasId = generateCanvasId(params.title, params.ui as { $tag?: string });
}
```

### Parameter Schema Change

```typescript
// Before:
required: ['canvasId', 'ui'] as string[],

// After:
required: ['ui'] as string[],
```

### Description Update
Update the tool description to indicate canvasId is auto-generated if not provided.

## Verification
1. Run `bun run build` - ensure no type errors
2. Run `bun run test` - ensure tests pass
3. Manual test: Call RenderAppUI without canvasId, verify unique file is created

## Alternatives Considered
- **Always append suffix**: Would break updating existing canvases
- **Suffix on file save only**: Would create mismatch between canvasId and filename
- **UUID**: Too long, harder to read in logs/debugging
