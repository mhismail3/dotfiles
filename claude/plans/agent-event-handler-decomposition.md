# AgentEventHandler Decomposition Plan

## Status: DRAFT

## Goal

Decompose the 1,044-line `AgentEventHandler` class into focused handler modules, each responsible for a specific category of events. This improves maintainability, testability, and makes the event flow easier to understand.

---

## Current State

**File:** `packages/agent/src/orchestrator/turn/agent-event-handler.ts`
**Lines:** 1,044
**Event Types Handled:** 15

### Current Event Handler Methods

| Method | Lines | Event Type | Category |
|--------|-------|------------|----------|
| `handleTurnStart` | 24 | `turn_start` | Turn |
| `handleTurnEnd` | 178 | `turn_end` | Turn |
| `handleResponseComplete` | 51 | `response_complete` | Turn |
| `handleMessageUpdate` | 28 | `message_update` | Streaming |
| `handleToolCallDelta` | 20 | `toolcall_delta` | Streaming |
| `handleToolUseBatch` | 25 | `tool_use_batch` | Tool |
| `handleToolExecutionStart` | 109 | `tool_execution_start` | Tool |
| `handleToolExecutionEnd` | 96 | `tool_execution_end` | Tool |
| `handleThinkingStart` | 12 | `thinking_start` | Thinking |
| `handleThinkingDelta` | 24 | `thinking_delta` | Thinking |
| `handleThinkingEnd` | 28 | `thinking_end` | Thinking |
| `handleAgentStart` | 18 | `agent_start` | Lifecycle |
| `handleAgentEnd` | 14 | `agent_end` | Lifecycle |
| `handleAgentInterrupted` | 17 | `agent_interrupted` | Lifecycle |
| `handleApiRetry` | 11 | `api_retry` | Lifecycle |
| `handleCompactionComplete` | 49 | `compaction_complete` | Compaction |
| `forwardToParent` | 94 | (subagent routing) | Subagent |

### Key Problems

1. **Large methods**: `handleTurnEnd` is 178 lines with complex token/message logic
2. **Mixed concerns**: Turn management, message creation, cost calculation, event persistence all interleaved
3. **Difficult to test**: Testing one event type requires mocking the entire handler
4. **Hard to navigate**: 15 event types in one switch statement

---

## Proposed Decomposition

### Target Structure

```
orchestrator/turn/
├── agent-event-handler.ts        # Slim coordinator (~150 lines)
├── handlers/
│   ├── turn-event-handler.ts     # turn_start, turn_end, response_complete (~280 lines)
│   ├── tool-event-handler.ts     # tool_use_batch, tool_execution_* (~250 lines)
│   ├── streaming-event-handler.ts # message_update, toolcall_delta, thinking_* (~120 lines)
│   ├── lifecycle-event-handler.ts # agent_start/end, interrupted, api_retry (~80 lines)
│   ├── compaction-event-handler.ts # compaction_complete (~60 lines)
│   ├── subagent-forwarder.ts     # forwardToParent logic (~110 lines)
│   └── index.ts                  # Re-exports
├── turn-manager.ts
├── turn-content-tracker.ts
├── token-usage-tracker.ts
├── content-block-builder.ts
└── index.ts
```

### Handler Responsibilities

| Handler | Events | Key Operations |
|---------|--------|----------------|
| **TurnEventHandler** | `turn_start`, `turn_end`, `response_complete` | Turn lifecycle, message.assistant creation, token tracking, cost calculation |
| **ToolEventHandler** | `tool_use_batch`, `tool_execution_start/end` | Tool registration, linear event ordering, tool.call/result persistence |
| **StreamingEventHandler** | `message_update`, `toolcall_delta`, `thinking_*` | Text/thinking delta accumulation, WebSocket emission |
| **LifecycleEventHandler** | `agent_start/end`, `agent_interrupted`, `api_retry` | Agent lifecycle management, cleanup |
| **CompactionEventHandler** | `compaction_complete` | Compaction event persistence, WebSocket emission |
| **SubagentForwarder** | (internal routing) | Forward events from subagent to parent session |

### Shared Dependencies (Handler Context)

All handlers will receive a shared context via dependency injection:

```typescript
interface HandlerContext {
  // Configuration
  defaultProvider: string;

  // Session access
  getActiveSession: (sessionId: string) => ActiveSession | undefined;

  // Event operations
  appendEventLinearized: (
    sessionId: SessionId,
    type: EventType,
    payload: Record<string, unknown>,
    onCreated?: (event: TronSessionEvent) => void
  ) => void;

  // WebSocket emission
  emit: (event: string, data: unknown) => void;

  // UI handler (shared instance)
  uiRenderHandler: UIRenderHandler;
}
```

---

## Implementation Phases

### Phase 1: Extract TurnEventHandler (Highest Complexity)

**Rationale:** `handleTurnEnd` is the largest method (178 lines) with the most complex logic. Extracting it first addresses the biggest pain point.

**Step 1.1: Create handler file**
```bash
touch packages/agent/src/orchestrator/turn/handlers/turn-event-handler.ts
```

**Step 1.2: Define interface and implement**
```typescript
// turn-event-handler.ts
export interface TurnEventHandlerDeps {
  getActiveSession: (sessionId: string) => ActiveSession | undefined;
  appendEventLinearized: (...) => void;
  emit: (event: string, data: unknown) => void;
}

export class TurnEventHandler {
  constructor(private deps: TurnEventHandlerDeps) {}

  handleTurnStart(sessionId: SessionId, event: TronEvent, timestamp: string): void
  handleTurnEnd(sessionId: SessionId, event: TronEvent, timestamp: string): void
  handleResponseComplete(sessionId: SessionId, event: TronEvent): void
}
```

**Step 1.3: Move methods from AgentEventHandler**
- Move `handleTurnStart`, `handleTurnEnd`, `handleResponseComplete`
- Update imports (add one `../` level)
- Keep all internal logic unchanged

**Step 1.4: Update AgentEventHandler to delegate**
```typescript
// agent-event-handler.ts
case 'turn_start':
  this.turnHandler.handleTurnStart(sessionId, event, timestamp);
  break;
```

**Step 1.5: Create tests**
```bash
touch packages/agent/src/orchestrator/turn/handlers/__tests__/turn-event-handler.test.ts
```

**Step 1.6: Verify**
```bash
bun run build && bun run test
```

**Checkpoint:** All tests pass before proceeding.

---

### Phase 2: Extract ToolEventHandler

**Step 2.1: Create handler file**
```bash
touch packages/agent/src/orchestrator/turn/handlers/tool-event-handler.ts
```

**Step 2.2: Define interface and implement**
```typescript
export class ToolEventHandler {
  constructor(private deps: ToolEventHandlerDeps) {}

  handleToolUseBatch(sessionId: SessionId, event: TronEvent): void
  handleToolExecutionStart(sessionId: SessionId, event: TronEvent, timestamp: string): void
  handleToolExecutionEnd(sessionId: SessionId, event: TronEvent, timestamp: string): void
}
```

**Step 2.3: Move methods from AgentEventHandler**
- Move `handleToolUseBatch`, `handleToolExecutionStart`, `handleToolExecutionEnd`
- UIRenderHandler delegation stays (already extracted)

**Step 2.4: Update AgentEventHandler to delegate**

**Step 2.5: Create tests**

**Step 2.6: Verify**
```bash
bun run build && bun run test
```

**Checkpoint:** All tests pass before proceeding.

---

### Phase 3: Extract StreamingEventHandler

**Step 3.1: Create handler file**
```bash
touch packages/agent/src/orchestrator/turn/handlers/streaming-event-handler.ts
```

**Step 3.2: Define interface and implement**
```typescript
export class StreamingEventHandler {
  constructor(private deps: StreamingEventHandlerDeps) {}

  handleMessageUpdate(sessionId: SessionId, event: TronEvent, timestamp: string): void
  handleToolCallDelta(sessionId: SessionId, event: TronEvent, timestamp: string): void
  handleThinkingStart(sessionId: SessionId, timestamp: string): void
  handleThinkingDelta(sessionId: SessionId, event: TronEvent, timestamp: string): void
  handleThinkingEnd(sessionId: SessionId, event: TronEvent, timestamp: string): void
}
```

**Step 3.3: Move methods from AgentEventHandler**

**Step 3.4: Update AgentEventHandler to delegate**

**Step 3.5: Create tests**

**Step 3.6: Verify**
```bash
bun run build && bun run test
```

**Checkpoint:** All tests pass before proceeding.

---

### Phase 4: Extract LifecycleEventHandler

**Step 4.1: Create handler file**
```bash
touch packages/agent/src/orchestrator/turn/handlers/lifecycle-event-handler.ts
```

**Step 4.2: Define interface and implement**
```typescript
export class LifecycleEventHandler {
  constructor(private deps: LifecycleEventHandlerDeps) {}

  handleAgentStart(sessionId: SessionId, timestamp: string): void
  handleAgentEnd(): void
  handleAgentInterrupted(sessionId: SessionId, event: TronEvent, timestamp: string): void
  handleApiRetry(sessionId: SessionId, event: TronEvent): void
}
```

**Step 4.3: Move methods from AgentEventHandler**

**Step 4.4: Update AgentEventHandler to delegate**

**Step 4.5: Create tests**

**Step 4.6: Verify**
```bash
bun run build && bun run test
```

**Checkpoint:** All tests pass before proceeding.

---

### Phase 5: Extract CompactionEventHandler

**Step 5.1: Create handler file**
```bash
touch packages/agent/src/orchestrator/turn/handlers/compaction-event-handler.ts
```

**Step 5.2: Define interface and implement**
```typescript
export class CompactionEventHandler {
  constructor(private deps: CompactionEventHandlerDeps) {}

  handleCompactionComplete(sessionId: SessionId, event: TronEvent, timestamp: string): void
}
```

**Step 5.3: Move method from AgentEventHandler**

**Step 5.4: Update AgentEventHandler to delegate**

**Step 5.5: Create tests**

**Step 5.6: Verify**
```bash
bun run build && bun run test
```

**Checkpoint:** All tests pass before proceeding.

---

### Phase 6: Extract SubagentForwarder

**Step 6.1: Create forwarder file**
```bash
touch packages/agent/src/orchestrator/turn/handlers/subagent-forwarder.ts
```

**Step 6.2: Define interface and implement**
```typescript
export class SubagentForwarder {
  constructor(private deps: SubagentForwarderDeps) {}

  forwardToParent(
    subagentSessionId: SessionId,
    parentSessionId: SessionId,
    event: TronEvent,
    timestamp: string
  ): void
}
```

**Step 6.3: Move method from AgentEventHandler**

**Step 6.4: Update AgentEventHandler to use forwarder**

**Step 6.5: Create tests**

**Step 6.6: Verify**
```bash
bun run build && bun run test
```

**Checkpoint:** All tests pass before proceeding.

---

### Phase 7: Create handlers/index.ts and Final Cleanup

**Step 7.1: Create index file**
```typescript
// handlers/index.ts
export { TurnEventHandler, type TurnEventHandlerDeps } from './turn-event-handler.js';
export { ToolEventHandler, type ToolEventHandlerDeps } from './tool-event-handler.js';
export { StreamingEventHandler, type StreamingEventHandlerDeps } from './streaming-event-handler.js';
export { LifecycleEventHandler, type LifecycleEventHandlerDeps } from './lifecycle-event-handler.js';
export { CompactionEventHandler, type CompactionEventHandlerDeps } from './compaction-event-handler.js';
export { SubagentForwarder, type SubagentForwarderDeps } from './subagent-forwarder.js';
```

**Step 7.2: Update turn/index.ts**
Add re-exports for new handlers if needed for external consumption.

**Step 7.3: Verify final AgentEventHandler**
Should now be ~150 lines:
- Constructor creates handler instances
- `forwardEvent` dispatches to appropriate handler
- No complex logic, just routing

**Step 7.4: Final verification**
```bash
bun run build && bun run test
```

**Step 7.5: Commit**
```bash
git add -A
git commit -m "Decompose AgentEventHandler into focused event handlers

Extract 6 focused handlers from AgentEventHandler (1044 → ~150 lines):

- TurnEventHandler: turn_start, turn_end, response_complete
- ToolEventHandler: tool_use_batch, tool_execution_start/end
- StreamingEventHandler: message_update, toolcall_delta, thinking_*
- LifecycleEventHandler: agent_start/end, interrupted, api_retry
- CompactionEventHandler: compaction_complete
- SubagentForwarder: parent session event forwarding

AgentEventHandler now acts as a slim coordinator that delegates
to focused handlers. Each handler has its own tests.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Files to Create

| File | Purpose | Est. Lines |
|------|---------|------------|
| `handlers/turn-event-handler.ts` | Turn lifecycle events | ~280 |
| `handlers/tool-event-handler.ts` | Tool execution events | ~250 |
| `handlers/streaming-event-handler.ts` | Streaming/thinking events | ~120 |
| `handlers/lifecycle-event-handler.ts` | Agent lifecycle events | ~80 |
| `handlers/compaction-event-handler.ts` | Compaction events | ~60 |
| `handlers/subagent-forwarder.ts` | Subagent event routing | ~110 |
| `handlers/index.ts` | Re-exports | ~20 |
| `handlers/__tests__/turn-event-handler.test.ts` | Tests | ~300 |
| `handlers/__tests__/tool-event-handler.test.ts` | Tests | ~250 |
| `handlers/__tests__/streaming-event-handler.test.ts` | Tests | ~150 |
| `handlers/__tests__/lifecycle-event-handler.test.ts` | Tests | ~100 |
| `handlers/__tests__/compaction-event-handler.test.ts` | Tests | ~80 |
| `handlers/__tests__/subagent-forwarder.test.ts` | Tests | ~100 |

## Files to Modify

| File | Change |
|------|--------|
| `turn/agent-event-handler.ts` | Reduce to coordinator (~150 lines) |
| `turn/index.ts` | Add handlers re-export |

---

## Key Design Decisions

### 1. Dependency Injection over Inheritance

Each handler receives its dependencies via constructor injection rather than extending a base class. This:
- Makes dependencies explicit
- Enables easy mocking in tests
- Avoids diamond inheritance problems

### 2. Shared UIRenderHandler Instance

The `UIRenderHandler` is already extracted and will be shared across handlers that need it (Tool, Streaming). It's passed via the handler context.

### 3. Handler Context Pattern

All handlers receive a similar context object with common operations:
- `getActiveSession` - Session lookup
- `appendEventLinearized` - Event persistence
- `emit` - WebSocket emission

This consistency makes it easy to test handlers in isolation.

### 4. No Public API Changes

`AgentEventHandler` remains the public interface. External code continues to call `forwardEvent()` without knowing about the internal decomposition.

---

## Success Criteria

**Per-Phase Checkpoints:**
- [ ] Phase 1 (TurnEventHandler): Build passes, all tests pass
- [ ] Phase 2 (ToolEventHandler): Build passes, all tests pass
- [ ] Phase 3 (StreamingEventHandler): Build passes, all tests pass
- [ ] Phase 4 (LifecycleEventHandler): Build passes, all tests pass
- [ ] Phase 5 (CompactionEventHandler): Build passes, all tests pass
- [ ] Phase 6 (SubagentForwarder): Build passes, all tests pass
- [ ] Phase 7 (Final cleanup): Build passes, all tests pass

**Final Verification:**
- [ ] AgentEventHandler reduced to ~150 lines (coordinator only)
- [ ] 6 focused handlers created with ~920 combined lines
- [ ] Each handler has dedicated test file
- [ ] All 3425+ tests pass
- [ ] Build succeeds with zero errors
- [ ] No public API changes (AgentEventHandler.forwardEvent unchanged)

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Circular imports | Use dependency injection, avoid importing from parent |
| Missing event handling | Keep switch statement in coordinator, delegate only |
| Test coverage gaps | Write handler tests before removing code from original |
| Performance regression | Handlers are stateless, no added overhead |

---

## Rollback Plan

If any phase fails:
1. `git checkout -- .` to discard uncommitted changes
2. Or `git reset --hard HEAD` if committed
3. Investigate the specific failure before retrying

Each phase is independently revertible since we move code incrementally.

---

## Out of Scope

1. Changing the event type system
2. Modifying event persistence logic
3. Changing WebSocket emission format
4. Refactoring SessionContext or TurnContentTracker
5. Adding new event types
