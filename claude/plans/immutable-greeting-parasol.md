# Fix Invalid Request Error on Session Resume with Truncated Tool Inputs

## Root Cause

When resuming session `sess_936feb8588f8`, the API rejects the request because **truncated tool_use inputs** are being sent to the Anthropic API.

### Evidence from Database

The `message.assistant` event (seq 25) contains a RenderAppUI tool_use with truncated input:
```json
{
  "type": "tool_use",
  "id": "toolu_016LWPYkLowHmGyjPD7Ne8dp",
  "name": "RenderAppUI",
  "input": {
    "_truncated": true,
    "_originalSize": 5768,
    "_preview": "..."
  }
}
```

The Anthropic API expects valid tool arguments, not this truncation metadata object.

### Data Flow

1. **Storage**: `content-normalizer.ts:87-94` truncates tool_use inputs exceeding 5KB:
   ```typescript
   if (inputStr.length > MAX_TOOL_INPUT_SIZE) {
     input = { _truncated: true, _originalSize, _preview };
   }
   ```

2. **Reconstruction**: `event-store.ts:704` copies content directly without restoring truncated inputs:
   ```typescript
   messages.push({ role: 'assistant', content: payload.content });
   ```

3. **API Submission**: `anthropic.ts:914` passes the truncated object through:
   ```typescript
   const input = c.arguments ?? (c as any).input ?? {};  // Gets truncated object!
   ```

### Key Insight

The **full arguments ARE available** in `tool.call` events (seq 26):
```json
{"toolCallId":"toolu_016LWPYkLowHmGyjPD7Ne8dp","name":"RenderAppUI","arguments":{...full 5KB+ object...}}
```

## Solution

Modify `event-store.ts` `getStateAt()` to restore truncated tool_use inputs from corresponding `tool.call` events.

### Implementation

**File**: `packages/core/src/events/event-store.ts`

1. **First pass**: Build a map of tool call arguments before processing messages
   ```typescript
   // Build toolCallId -> full arguments map from tool.call events
   const toolCallArgsMap = new Map<string, Record<string, unknown>>();
   for (const evt of ancestors) {
     if (evt.type === 'tool.call') {
       const payload = evt.payload as { toolCallId: string; arguments: Record<string, unknown> };
       toolCallArgsMap.set(payload.toolCallId, payload.arguments);
     }
   }
   ```

2. **Restore truncated inputs**: When processing `message.assistant` events, check for and restore truncated inputs
   ```typescript
   // In the message.assistant handling (around line 675):
   const contentArray = Array.isArray(payload.content) ? payload.content : [];

   // Restore truncated tool_use inputs from tool.call events
   const restoredContent = contentArray.map((block) => {
     if (block.type === 'tool_use' && block.input?._truncated) {
       const fullArgs = toolCallArgsMap.get(block.id);
       if (fullArgs) {
         return { ...block, input: fullArgs };
       }
     }
     return block;
   });
   ```

3. **Use restored content** when pushing messages

## Files to Modify

| File | Changes |
|------|---------|
| `packages/core/src/events/event-store.ts` | Add tool.call argument collection and truncated input restoration in `getStateAt()` |

## Verification

1. **Manual Test**:
   - Resume session `sess_936feb8588f8`
   - Send a message - should succeed without invalid request error
   - Verify the RenderAppUI tool_use is reconstructed with full arguments

2. **Unit Tests**:
   - Add test in event-store test file for truncated input restoration
   - Create a session with large tool input, verify reconstruction

3. **Run Test Suite**:
   ```bash
   bun run test
   ```
