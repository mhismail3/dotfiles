# Fix Thinking Block Streaming for GPT 5.2 Codex and Gemini 3

## Summary

Database investigation revealed:
- **Anthropic thinking works**: `hasThinking: 1`, content includes thinking blocks
- **GPT Codex thinking NOT working**: `hasThinking: 0`, no thinking blocks ever
- **Gemini thinking NOT working**: `hasThinking: 0`, no thinking blocks ever

## Root Cause Analysis

### Issue 1: OpenAI Codex - Missing `summary` Parameter (CRITICAL BUG)

The Codex provider sends:
```javascript
body.reasoning = { effort: reasoningEffort };  // CURRENT - MISSING SUMMARY
```

But according to [OpenAI's Responses API](https://platform.openai.com/docs/api-reference/responses), it should send:
```javascript
body.reasoning = {
  effort: reasoningEffort,
  summary: "concise"  // or "detailed" - REQUIRED FOR SUMMARIES
};
```

Without the `summary` parameter, the API doesn't return reasoning summaries - it just uses reasoning internally without exposing it.

**File:** `packages/agent/src/providers/openai-codex.ts` lines 502-504

### Issue 2: Google/Gemini - Missing ThinkingContent in Final Message (CRITICAL BUG)

**File:** `packages/agent/src/providers/google.ts` lines 960-974

The Gemini provider emits streaming events correctly but doesn't include ThinkingContent in the final message:
```typescript
// Current buggy code (line 961):
const content: (TextContent | ToolCall)[] = [];  // Missing ThinkingContent!
```

### Issue 3: Configuration Flow Missing Gemini Options
- `TurnConfig` lacks `thinkingLevel` and `geminiThinkingBudget`
- Turn runner doesn't pass these to the provider

## Implementation Plan

### Phase 1: Fix OpenAI Codex - Add `summary` Parameter (Critical)

**File:** `packages/agent/src/providers/openai-codex.ts`

Update lines 502-504 to include reasoning summary:
```typescript
if (reasoningEffort) {
  body.reasoning = {
    effort: reasoningEffort,
    summary: 'concise'  // ADD THIS - required for reasoning summaries
  };
}
```

Also consider adding a `reasoningSummary` config option to allow users to choose `concise | detailed | auto | none`.

### Phase 2: Fix Google Provider - Add ThinkingContent to Final Message

**File:** `packages/agent/src/providers/google.ts`

1. Add `ThinkingContent` to the import at line ~18
2. Update final message building at lines 960-974:
   - Change type to `(TextContent | ThinkingContent | ToolCall)[]`
   - Add ThinkingContent block before TextContent if `accumulatedThinking` exists

### Phase 3: Update Type Definitions for Gemini Config

**File:** `packages/agent/src/agent/types.ts`

Add to `AgentConfig`:
```typescript
thinkingLevel?: 'minimal' | 'low' | 'medium' | 'high';
geminiThinkingBudget?: number;
```

**File:** `packages/agent/src/agent/internal-types.ts`

Add same fields to `TurnConfig`

### Phase 4: Update Turn Runner for Gemini

**File:** `packages/agent/src/agent/turn-runner.ts`

Pass Gemini-specific options to provider.stream():
```typescript
thinkingLevel: this.config.thinkingLevel,
geminiThinkingBudget: this.config.geminiThinkingBudget,
```

## Files to Modify

| File | Change |
|------|--------|
| `packages/agent/src/providers/openai-codex.ts` | **Add `summary: 'concise'` to reasoning parameter** |
| `packages/agent/src/providers/google.ts` | Add ThinkingContent to final message |
| `packages/agent/src/agent/types.ts` | Add thinkingLevel, geminiThinkingBudget to AgentConfig |
| `packages/agent/src/agent/internal-types.ts` | Add same fields to TurnConfig |
| `packages/agent/src/agent/turn-runner.ts` | Pass Gemini options to provider |
| `packages/agent/src/providers/__tests__/openai-codex.test.ts` | Add test for reasoning summary |
| `packages/agent/src/providers/__tests__/google.test.ts` | Add test for ThinkingContent in final message |

## Verification

1. Run build: `bun run build`
2. Run tests: `bun run test`
3. **Manual testing for Codex** (priority - fix confirmed):
   - Use GPT 5.2 Codex with xhigh reasoning
   - Prompt: "What are the pros and cons of React?"
   - Verify `response.reasoning_summary_text.delta` events appear in logs
   - Verify thinking blocks appear in iOS app with `hasThinking: true`
   - Check database: `SELECT hasThinking, content FROM events WHERE type='message.assistant' ORDER BY timestamp DESC LIMIT 1`
4. **Manual testing for Gemini**:
   - Use Gemini 3 model with a prompt
   - Verify thinking blocks appear in iOS app
5. Enable debug logging:
   ```bash
   LOG_LEVEL=debug bun run start
   ```

## Notes

- All changes are backwards compatible (new optional fields)
- iOS app ThinkingState is provider-agnostic - no changes needed there
- No SDK updates required - both providers use native fetch, not external SDKs
- The Codex fix is critical - without `summary: 'concise'`, the API never returns reasoning content

## Sources

- [OpenAI Responses API Reference](https://platform.openai.com/docs/api-reference/responses)
- [OpenAI Reasoning Cookbook](https://cookbook.openai.com/examples/responses_api/reasoning_items)
- [OpenAI Codex Config Reference](https://developers.openai.com/codex/config-reference/)
