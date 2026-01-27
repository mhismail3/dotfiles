# Fix: Context Progress Bar Inconsistency

## Problem
The context progress bar shows different "tokens remaining" than the Context Manager sheet, even for a brand new session. Both should show the same value representing space left in the context window.

## Root Cause (Fundamental Mismatch)

Two **different token counting mechanisms**:

1. **Progress Bar** uses `contextWindowTokens` from API response (`normalizedUsage.contextWindowTokens`)
   - Source: Real token count from model API (actual tokenizer)
   - For Anthropic: `inputTokens + cacheRead + cacheCreate`
   - This is the **ground truth** - what the model actually counts

2. **Context Sheet** uses `ContextManager.getCurrentTokens()`
   - Source: **Estimated** tokens using `chars / 4` heuristic
   - Sums up system prompt, tools, rules, messages estimates
   - This is an **approximation** that drifts from reality

## Example Divergence
From database, turn 1 shows `contextWindowTokens: 17834` (API-reported)

But ContextManager might estimate differently:
- System prompt: ~4000 chars / 4 = ~1000 tokens (estimate)
- Tools: varies
- Messages: varies
- Total estimate ≠ 17834 (API actual)

## Solution
Unify both displays to use the **API-reported token count** since it's the ground truth.

### Approach: Store API tokens in ContextManager

When `stream.turn_end` fires with `normalizedUsage.contextWindowTokens`, propagate this to the ContextManager so both:
- Progress bar reads it from `contextState.contextWindowTokens` (iOS client-side)
- Context sheet RPC reads it from `ContextManager` (server-side via RPC)

## Files to Modify

### 1. Server: `packages/agent/src/context/context-manager.ts`

Add tracked API token count:
```typescript
private lastApiContextTokens: number = 0;

// After turn completes, store actual API count
setApiContextTokens(tokens: number): void {
  this.lastApiContextTokens = tokens;
}

// Use API tokens if available, else fall back to estimate
getCurrentTokens(): number {
  if (this.lastApiContextTokens > 0) {
    return this.lastApiContextTokens;
  }
  // Fall back to estimate when no API data yet
  return this.estimateCurrentTokens();
}

// Rename existing getCurrentTokens to estimateCurrentTokens (private)
private estimateCurrentTokens(): number {
  let total = this.estimateSystemPromptTokens();
  // ... existing logic ...
}
```

### 2. Server: `packages/agent/src/orchestrator/agent-event-handler.ts`

After turn_end, update ContextManager with API tokens:
```typescript
// In handleTurnEnd or wherever normalizedUsage is processed
const cm = session.agent.getContextManager();
cm.setApiContextTokens(normalizedUsage.contextWindowTokens);
```

### 3. Server: `packages/agent/src/orchestrator/turn-content-tracker.ts`

Expose the last context size for ContextManager sync:
```typescript
// Already has: getLastNormalizedUsage() which returns contextWindowTokens
// This is already being used for stream events
```

### 4. Server: `packages/agent/src/orchestrator/agent-event-handler.ts`

In `handleTurnEnd()` around line 240-370:
- `turnResult.normalizedUsage.contextWindowTokens` is already available
- Add sync to ContextManager after line 244 where `turnResult` is obtained:

```typescript
// Sync API token count to ContextManager for consistent RPC responses
if (turnResult?.normalizedUsage?.contextWindowTokens) {
  active.agent.getContextManager().setApiContextTokens(
    turnResult.normalizedUsage.contextWindowTokens
  );
}
```

## Implementation Steps

1. **Add API token storage to ContextManager**
   - Add `lastApiContextTokens` field
   - Add `setApiContextTokens()` method
   - Modify `getCurrentTokens()` to prefer API tokens

2. **Sync API tokens after each turn**
   - Find where `stream.turn_end` event is processed
   - Extract `contextWindowTokens` from normalizedUsage
   - Call `contextManager.setApiContextTokens()`

3. **Handle session restore**
   - When resuming a session, may need to restore from last turn's token data
   - Or accept that first snapshot after resume uses estimate until turn completes

4. **Reset on context mutations**
   - When context is cleared/compacted, reset `lastApiContextTokens = 0`
   - Next turn will re-establish actual count

## Verification

1. Start new session in iOS app
2. Send a message, wait for response
3. Compare progress bar "X left" with Context Manager sheet's remaining tokens
4. They should now match

5. Test context mutations:
   - Delete a message → both should update (via background reload + API sync)
   - Compact context → both should match after compaction completes
   - Clear context → both should show near-full capacity

## Files Summary

| File | Change |
|------|--------|
| `packages/agent/src/context/context-manager.ts` | Add `lastApiContextTokens` field, `setApiContextTokens()` method, modify `getCurrentTokens()` |
| `packages/agent/src/orchestrator/agent-event-handler.ts` | Call `setApiContextTokens()` in `handleTurnEnd()` (~line 245) |
| `packages/agent/src/orchestrator/context-ops.ts` | Call `setApiContextTokens(0)` in `clearContext()` and after `executeCompaction()` |

## Detailed Changes

### context-manager.ts

```typescript
// Add field (around line 203)
private lastApiContextTokens: number = 0;

// Add method (after line 405)
/**
 * Set the API-reported context token count.
 * Called after each turn with actual tokenizer count from model API.
 * This value is preferred over estimates when available.
 */
setApiContextTokens(tokens: number): void {
  this.lastApiContextTokens = tokens;
}

// Modify getCurrentTokens() (line 383-391)
getCurrentTokens(): number {
  // Prefer API-reported tokens (ground truth from actual tokenizer)
  if (this.lastApiContextTokens > 0) {
    return this.lastApiContextTokens;
  }
  // Fall back to estimate when no API data yet (new session before first turn)
  return this.estimateCurrentTokens();
}

// Rename existing body to private helper
private estimateCurrentTokens(): number {
  let total = this.estimateSystemPromptTokens();
  total += this.estimateToolsTokens();
  total += this.estimateRulesTokens();
  for (const msg of this.messages) {
    total += this.tokenCache.get(msg) ?? this.estimateMessageTokens(msg);
  }
  return total;
}

// Modify clearMessages() (line 285-288)
clearMessages(): void {
  this.messages = [];
  this.lastApiContextTokens = 0; // Reset so estimate is used until next turn
}
```

### agent-event-handler.ts

```typescript
// In handleTurnEnd(), after line 244 where turnResult is obtained:
turnResult = active.sessionContext!.endTurn();

// ADD: Sync API token count to ContextManager for consistent RPC responses
if (turnResult?.normalizedUsage?.contextWindowTokens !== undefined) {
  active.agent.getContextManager().setApiContextTokens(
    turnResult.normalizedUsage.contextWindowTokens
  );
}
```

### context-ops.ts

```typescript
// In clearContext() after line 297 (after cm.clearMessages())
cm.clearMessages();
// API tokens reset happens in clearMessages() now, no extra call needed

// In confirmCompaction() - no change needed
// executeCompaction() clears messages internally, which resets API tokens
```

## Testing
```bash
cd packages/agent && bun run build && bun run test
```

## Edge Cases Handled

1. **New session before first turn**: `lastApiContextTokens = 0`, falls back to estimate
2. **After context clear**: `lastApiContextTokens = 0`, falls back to estimate
3. **After compaction**: Messages rebuilt internally, API tokens reset, falls back to estimate until next turn
4. **Session resume**: First turn after resume will populate API tokens
5. **Model switch**: No special handling needed - API tokens come from next turn's response
