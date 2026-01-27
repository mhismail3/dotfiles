# Fix Duplicated Thinking Block Display for GPT 5.2 Codex

## Problem

When using GPT 5.2 Codex in the iOS app, thinking block content is displayed twice (duplicated) during streaming. This doesn't happen with Anthropic or Gemini models.

## Root Cause

In `packages/agent/src/providers/openai-codex.ts`, the OpenAI Responses API sends thinking content through multiple event types:

1. **`response.reasoning_summary_text.delta`** (lines 664-675): Streaming deltas like `"Step 1: "`, `"Analyze"`, `" input"`
2. **`response.output_item.done`** (lines 639-654): Contains the COMPLETE assembled text like `"Step 1: Analyze input"`

The current deduplication logic at line 647 uses a Set to track seen chunks:
```typescript
if (summaryPart.type === 'summary_text' && summaryPart.text && !seenThinkingTexts.has(summaryPart.text))
```

**The bug**: The Set contains individual streaming chunks, but `output_item.done` contains the assembled text. Since `"Step 1: Analyze input"` (assembled) was never added to the Set (only the individual chunks were), the check passes and the full text is emitted again as a `thinking_delta`.

The iOS app accumulates all deltas without deduplication (`ThinkingState.handleThinkingDelta`), so both the streaming chunks AND the complete text get displayed.

## Solution

Fix the `response.output_item.done` handler at line 641-653 to check if we already have accumulated thinking content before emitting. This mirrors the correct approach already used in `response.completed` at line 736: `!accumulatedThinking`.

## Files to Modify

| File | Change |
|------|--------|
| `packages/agent/src/providers/openai-codex.ts` | Fix deduplication logic in `response.output_item.done` handler |

## Implementation

In `openai-codex.ts`, change the `response.output_item.done` handler (lines 639-654) from:

```typescript
case 'response.output_item.done':
  // Handle completed reasoning items - summary may be in item.summary
  if (event.item?.type === 'reasoning' && event.item.summary) {
    if (!thinkingStarted) {
      thinkingStarted = true;
      yield { type: 'thinking_start' };
    }
    for (const summaryPart of event.item.summary) {
      if (summaryPart.type === 'summary_text' && summaryPart.text && !seenThinkingTexts.has(summaryPart.text)) {
        seenThinkingTexts.add(summaryPart.text);
        accumulatedThinking += summaryPart.text;
        yield { type: 'thinking_delta', delta: summaryPart.text };
      }
    }
  }
  break;
```

To:

```typescript
case 'response.output_item.done':
  // Handle completed reasoning items - summary may be in item.summary
  // Only process if we didn't already get content via streaming deltas
  if (event.item?.type === 'reasoning' && event.item.summary && !accumulatedThinking) {
    if (!thinkingStarted) {
      thinkingStarted = true;
      yield { type: 'thinking_start' };
    }
    for (const summaryPart of event.item.summary) {
      if (summaryPart.type === 'summary_text' && summaryPart.text) {
        accumulatedThinking += summaryPart.text;
        yield { type: 'thinking_delta', delta: summaryPart.text };
      }
    }
  }
  break;
```

The key change is adding `&& !accumulatedThinking` to the condition. This means:
- If streaming deltas already accumulated thinking content, skip the `output_item.done` summary
- If no streaming deltas came (fallback path), use the `output_item.done` summary

This is consistent with how `response.completed` already handles deduplication at line 736.

## Verification

1. **Build & Test**: Run `bun run build && bun run test`
2. **Manual Test in iOS App**:
   - Send a prompt to GPT 5.2 Codex that triggers thinking
   - Verify thinking content appears only once
   - Verify thinking content is complete (not truncated)
3. **Regression Test**:
   - Test Anthropic models still work correctly
   - Test Gemini models still work correctly
   - Test GPT Codex without streaming deltas (if possible) to verify fallback path
