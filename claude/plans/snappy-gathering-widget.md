# Token Usage Architecture Redesign

## Problem Statement

Token display is inconsistent between live streaming and session resume. The root cause is an architectural gap where `normalizedUsage` (the computed display values) is stored in `stream.turn_end` events but NOT in `message.assistant` events. iOS has to correlate by turn number and has multiple fallback paths that compute wrong values.

## First Principles

### What Anthropic API Returns (Per Turn)
```
input_tokens: 502                    # Non-cached input ONLY (billing)
output_tokens: 53                    # Output tokens
cache_read_input_tokens: 17332       # Cached tokens used
cache_creation_input_tokens: 0       # Tokens cached this turn
```

### What We Need for Display
```
contextWindowTokens = 502 + 17332 + 0 = 17834   # For progress bar
newInputTokens = 17834 - previousContext        # For stats line (delta)
```

### What Server Computes (token-normalizer.ts)
```typescript
normalizedUsage: {
  newInputTokens: 17834,        // Delta for stats line ✓
  outputTokens: 53,
  contextWindowTokens: 17834,   // Full context ✓
  rawInputTokens: 502,          // For billing
  cacheReadTokens: 17332,
  cacheCreationTokens: 0
}
```

**This is correct and complete.** The problem is where it's stored.

---

## Current Architecture Gap

### What's Stored Where

| Event | `tokenUsage` (raw) | `normalizedUsage` (display) |
|-------|--------------------|-----------------------------|
| `stream.turn_end` | ✓ | ✓ |
| `message.assistant` | ✓ | ❌ **MISSING** |

### Why This Causes Problems

**iOS Reconstruction Flow:**
1. Load `message.assistant` events → has `tokenUsage` only
2. Try to correlate with `stream.turn_end` by turn number → fragile
3. Fall back to local computation → **WRONG for Anthropic**

**The fallback computation:**
```swift
let incrementalInput = max(0, usage.inputTokens - previousInputTokens)
// 502 - 0 = 502 ← WRONG (should be 17834)
```

---

## Redesigned Architecture

### Principle: Store Complete Data at Source

**Every piece of data needed for display should be stored when the event is created, not computed later.**

### Server-Side Changes

#### 1. Add `normalizedUsage` to `message.assistant` Events

**File**: `packages/agent/src/orchestrator/agent-event-handler.ts`

Currently `message.assistant` is created with only `tokenUsage`:
```typescript
// Current
{
  type: 'message.assistant',
  payload: {
    content: [...],
    tokenUsage: { inputTokens, outputTokens, ... },  // Raw only
    turn: number,
    model: string,
    ...
  }
}
```

**Change to include normalizedUsage:**
```typescript
// New
{
  type: 'message.assistant',
  payload: {
    content: [...],
    tokenUsage: { inputTokens, outputTokens, ... },      // Raw (for billing)
    normalizedUsage: { newInputTokens, contextWindowTokens, ... },  // For display
    turn: number,
    model: string,
    ...
  }
}
```

**Implementation:**
- `normalizedUsage` is already computed before emitting `stream.turn_end`
- Pass it to `message.assistant` creation as well
- Both events now have complete token data

#### 2. Add API Message ID for Traceability

**File**: `packages/agent/src/orchestrator/agent-event-handler.ts`

```typescript
{
  type: 'message.assistant',
  payload: {
    apiMessageId: message.id,  // From Anthropic response
    ...
  }
}
```

**Why**: Currently lost. Needed for debugging, audit trails, API correlation.

#### 3. Store Provider Semantics Flag

```typescript
{
  type: 'message.assistant',
  payload: {
    providerSemantics: 'anthropic' | 'openai',  // How to interpret tokens
    ...
  }
}
```

**Why**: Different providers have different token semantics. Store this so iOS knows how to interpret values if provider changes mid-session.

### iOS-Side Changes

#### 1. Simplify Message Reconstruction

**File**: `packages/ios-app/Sources/Models/UnifiedEventTransformer.swift`

**Current (complex):**
```swift
// PASS 1: Collect normalizedUsage from stream.turn_end events by turn
var turnIncrementalTokens: [Int: TokenUsage] = [:]
for event in events where event.type == "stream.turn_end" {
    turnIncrementalTokens[event.turn] = ...
}

// PASS 2: Create messages, correlate by turn number
for event in events where event.type == "message.assistant" {
    let incremental = turnIncrementalTokens[event.turn]  // Correlation!
    message.incrementalTokens = incremental
}
```

**New (simple):**
```swift
// SINGLE PASS: Just read what's stored
for event in events where event.type == "message.assistant" {
    let payload = AssistantMessagePayload(from: event.payload)

    // normalizedUsage is now directly on the event
    message.incrementalTokens = TokenUsage(
        inputTokens: payload.normalizedUsage?.newInputTokens ?? 0,
        outputTokens: payload.normalizedUsage?.outputTokens ?? 0,
        ...
    )
}
```

**No correlation needed. No fallback needed.**

#### 2. Delete Fallback Calculations

**File**: `packages/ios-app/Sources/ViewModels/ChatViewModel+Pagination.swift`

**DELETE `restoreTokenStateFromMessages()` entirely** (lines 280-325)

This function exists because reconstruction didn't have `normalizedUsage`. With the new architecture, it's unnecessary.

**File**: `packages/ios-app/Sources/ViewModels/ChatViewModel+Events.swift`

**Remove or simplify the fallback at line 504:**
```swift
// OLD: Compute locally if normalizedUsage missing
let incrementalInput = max(0, usage.inputTokens - previous)

// NEW: Just use normalizedUsage, fail gracefully if missing
message.incrementalTokens = normalizedUsage != nil
    ? TokenUsage(inputTokens: normalizedUsage.newInputTokens, ...)
    : nil  // Show nothing, not wrong data
```

#### 3. Update Payload Parsing

**File**: `packages/ios-app/Sources/Models/Payloads/StreamingPayloads.swift`

Add `AssistantMessagePayload.normalizedUsage` parsing:
```swift
struct AssistantMessagePayload {
    let content: [ContentBlock]
    let tokenUsage: TokenUsage?
    let normalizedUsage: NormalizedTokenUsage?  // NEW
    let turn: Int
    let model: String?
    ...
}
```

---

## Complete Data Flow (After Redesign)

### Agent Turn Execution
```
1. Provider returns API response
   └─ { input_tokens: 502, output_tokens: 53, cache_read: 17332, ... }

2. token-normalizer.ts computes normalizedUsage
   └─ { newInputTokens: 17834, contextWindowTokens: 17834, ... }

3. agent-event-handler.ts creates message.assistant event
   └─ payload: {
        tokenUsage: { inputTokens: 502, ... },           // Raw
        normalizedUsage: { newInputTokens: 17834, ... }, // Display ← NEW
        content: [...],
        turn: 1
      }

4. agent-event-handler.ts creates stream.turn_end event
   └─ payload: {
        tokenUsage: { ... },
        normalizedUsage: { ... },  // Same values
        cost: 0.11
      }

5. Both events persisted to SQLite
```

### iOS Session Resume
```
1. Load events from database
   └─ SELECT * FROM events WHERE session_id = ? ORDER BY sequence

2. UnifiedEventTransformer processes message.assistant events
   └─ FOR EACH event:
        payload.normalizedUsage.newInputTokens → message.incrementalTokens.inputTokens

   └─ NO correlation with stream.turn_end needed
   └─ NO local computation needed

3. Messages displayed with correct values
   └─ Stats line shows 17834 (from normalizedUsage.newInputTokens)
```

---

## Files to Modify

### Server (packages/agent/)

| File | Change |
|------|--------|
| `src/orchestrator/agent-event-handler.ts` | Add `normalizedUsage` to `message.assistant` event payload |
| `src/events/types.ts` | Update `AssistantMessageEvent` interface to include `normalizedUsage` |
| `src/types/events.ts` | Update TypeScript types |

### iOS (packages/ios-app/)

| File | Change |
|------|--------|
| `Sources/Models/Payloads/StreamingPayloads.swift` | Add `normalizedUsage` parsing to `AssistantMessagePayload` |
| `Sources/Models/UnifiedEventTransformer.swift` | Simplify reconstruction - read `normalizedUsage` directly |
| `Sources/ViewModels/ChatViewModel+Pagination.swift` | Delete `restoreTokenStateFromMessages()` |
| `Sources/ViewModels/ChatViewModel+Events.swift` | Remove/simplify fallback computation |

---

## Migration Strategy

### Backward Compatibility

Old sessions won't have `normalizedUsage` on `message.assistant` events. Handle gracefully:

```swift
// During reconstruction
if let normalized = payload.normalizedUsage {
    // New path: use stored values
    message.incrementalTokens = TokenUsage(
        inputTokens: normalized.newInputTokens,
        ...
    )
} else {
    // Old sessions: fall back to turn correlation (existing code)
    message.incrementalTokens = turnIncrementalTokens[payload.turn]
}
```

This preserves backward compatibility while new sessions get the clean path.

### Rollout

1. **Phase 1**: Server change - add `normalizedUsage` to `message.assistant`
2. **Phase 2**: iOS change - use `normalizedUsage` from `message.assistant`, keep fallback
3. **Phase 3**: After all sessions are new format, remove fallback code

---

## Testing Checklist

### Server Tests
- [ ] `message.assistant` event includes `normalizedUsage`
- [ ] Values match those in `stream.turn_end` for same turn
- [ ] `apiMessageId` is captured (if implemented)
- [ ] Existing tests still pass

### iOS Tests
- [ ] New session: stats line shows correct values (17.8k)
- [ ] Navigate away and back: still shows 17.8k
- [ ] Force quit and reopen: still shows 17.8k
- [ ] Multi-turn session: each turn shows correct delta
- [ ] Old session (no normalizedUsage): falls back gracefully
- [ ] Model switch mid-session: values still correct

### Database Verification
```sql
-- Verify normalizedUsage is on message.assistant events
SELECT
  session_id,
  type,
  json_extract(payload, '$.turn') as turn,
  json_extract(payload, '$.tokenUsage.inputTokens') as raw_input,
  json_extract(payload, '$.normalizedUsage.newInputTokens') as new_input
FROM events
WHERE type = 'message.assistant'
ORDER BY session_id, sequence DESC
LIMIT 10;
```

---

## Summary

### Before (Fragile)
```
message.assistant → has tokenUsage only
    ↓
iOS correlates by turn number with stream.turn_end
    ↓
Multiple fallback paths compute locally
    ↓
Wrong values for Anthropic (ignores cache)
```

### After (Robust)
```
message.assistant → has tokenUsage AND normalizedUsage
    ↓
iOS reads normalizedUsage directly
    ↓
No correlation, no computation
    ↓
Always correct values
```

**The core change**: Store `normalizedUsage` on `message.assistant` events so iOS reconstruction is trivial.
