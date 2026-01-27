# SubagentOperations Decomposition Plan

## Status: COMPLETED

## Overview

**Target file**: `packages/agent/src/orchestrator/operations/subagent-ops.ts` (717 lines)

**Goal**: Decompose into focused handlers while maintaining API compatibility. The file handles multiple responsibilities that can be cleanly separated.

---

## Current State Analysis

### Responsibilities (4 distinct domains)

| Domain | Methods | Lines | Description |
|--------|---------|-------|-------------|
| **Spawning** | `spawnSubsession`, `spawnTmuxAgent`, `runSubagentAsync` | ~365 | Creating and executing sub-agents |
| **Querying** | `querySubagent`, `summarizeEvent` | ~135 | Querying sub-agent status/events/logs/output |
| **Results** | `buildSubagentResultsContext` | ~45 | Formatting completed results for context injection |
| **Types/Config** | Types, constructor | ~110 | Shared types and configuration |

### Method Breakdown

```
SubagentOperations (717 lines)
├── Types (lines 1-108)
│   ├── SubagentOperationsConfig
│   ├── SpawnSubagentResult
│   ├── SpawnTmuxAgentResult
│   ├── QuerySubagentResult
│   └── WaitForSubagentsResult
│
├── spawnSubsession (lines 133-232) - 100 lines
│   └── Create in-process sub-agent session
│
├── spawnTmuxAgent (lines 238-325) - 88 lines
│   └── Create out-of-process sub-agent in tmux
│
├── querySubagent (lines 330-445) - 116 lines
│   ├── status: Get running/completed/failed status
│   ├── events: Get recent events
│   ├── logs: Get session logs
│   └── output: Get last assistant message
│
├── buildSubagentResultsContext (lines 455-497) - 43 lines
│   └── Format pending results into context string
│
├── runSubagentAsync (lines 506-680) - 175 lines
│   ├── Execute sub-agent with task
│   ├── Handle completion (events, tracker update, hooks)
│   └── Handle failure (events, tracker update, hooks)
│
└── summarizeEvent (lines 685-703) - 19 lines
    └── Helper for event display
```

### Dependencies

```typescript
// Shared dependencies
- createLogger from '../../logging/logger.js'
- EventStore from '../../events/event-store.js'
- SessionId, EventType, SessionEvent from '../../events/types.js'
- ActiveSession, AgentRunOptions, SessionInfo, CreateSessionOptions from '../types.js'

// Spawn-specific
- SpawnSubagentParams from '../../tools/subagent/spawn-subagent.js'
- SpawnTmuxAgentParams from '../../tools/subagent/spawn-tmux-agent.js'

// Query-specific
- SubagentQueryType, SubagentStatusInfo, SubagentEventInfo, SubagentLogInfo from '../../tools/subagent/query-subagent.js'
- SubagentResult from '../../tools/subagent/subagent-tracker.js'
```

---

## Proposed Structure

```
orchestrator/operations/subagent-ops/
├── types.ts              # Shared types and interfaces
├── spawn-handler.ts      # Spawning logic (subsession + tmux)
├── query-handler.ts      # Query operations
├── results-builder.ts    # Results context formatting
├── subagent-ops.ts       # Facade coordinating handlers
└── index.ts              # Barrel exports
```

### File Responsibilities

| File | Purpose | Est. Lines |
|------|---------|------------|
| `types.ts` | Config, result types, shared interfaces | ~80 |
| `spawn-handler.ts` | `spawnSubsession`, `spawnTmuxAgent`, `runSubagentAsync` | ~380 |
| `query-handler.ts` | `querySubagent`, `summarizeEvent` | ~150 |
| `results-builder.ts` | `buildSubagentResultsContext` | ~60 |
| `subagent-ops.ts` | Facade delegating to handlers | ~80 |
| `index.ts` | Re-exports | ~20 |

### Handler Interfaces

```typescript
// spawn-handler.ts
export interface SpawnHandlerDeps {
  eventStore: EventStore;
  getActiveSession: (sessionId: string) => ActiveSession | undefined;
  createSession: (options: CreateSessionOptions) => Promise<SessionInfo>;
  runAgent: (options: AgentRunOptions) => Promise<unknown>;
  appendEventLinearized: (sessionId: SessionId, type: EventType, payload: Record<string, unknown>) => void;
  emit: (event: string, data: unknown) => void;
}

export function createSpawnHandler(deps: SpawnHandlerDeps): SpawnHandler;

// query-handler.ts
export interface QueryHandlerDeps {
  eventStore: EventStore;
  getActiveSession: (sessionId: string) => ActiveSession | undefined;
}

export function createQueryHandler(deps: QueryHandlerDeps): QueryHandler;

// results-builder.ts (stateless, no deps)
export function buildSubagentResultsContext(active: ActiveSession): string | undefined;
```

---

## Implementation Phases

### Phase 1: Extract Types

**Step 1.1**: Create `subagent-ops/` directory
```bash
mkdir -p packages/agent/src/orchestrator/operations/subagent-ops
```

**Step 1.2**: Create `types.ts` with shared types

Extract from current file:
- `SubagentOperationsConfig`
- `SpawnSubagentResult`
- `SpawnTmuxAgentResult`
- `QuerySubagentResult`
- `WaitForSubagentsResult`

**Step 1.3**: Verify build
```bash
bun run build
```

---

### Phase 2: Extract Results Builder (Simplest - No Dependencies)

**Step 2.1**: Create `results-builder.ts`

Extract `buildSubagentResultsContext` method - it's stateless and only depends on `ActiveSession`.

```typescript
// results-builder.ts
import type { ActiveSession } from '../../types.js';

export function buildSubagentResultsContext(active: ActiveSession): string | undefined {
  // ... existing implementation
}
```

**Step 2.2**: Update main file to import from `results-builder.ts`

**Step 2.3**: Verify tests pass
```bash
bun run build && bun run test
```

---

### Phase 3: Extract Query Handler

**Step 3.1**: Create `query-handler.ts`

Extract:
- `querySubagent` method
- `summarizeEvent` helper

```typescript
// query-handler.ts
export interface QueryHandlerDeps {
  eventStore: EventStore;
  getActiveSession: (sessionId: string) => ActiveSession | undefined;
}

export class QueryHandler {
  constructor(private deps: QueryHandlerDeps) {}

  async querySubagent(sessionId: string, queryType: SubagentQueryType, limit?: number): Promise<QuerySubagentResult> {
    // ... existing implementation
  }

  private summarizeEvent(event: TronSessionEvent): string {
    // ... existing implementation
  }
}

export function createQueryHandler(deps: QueryHandlerDeps): QueryHandler {
  return new QueryHandler(deps);
}
```

**Step 3.2**: Update main file to delegate to `QueryHandler`

**Step 3.3**: Verify tests pass
```bash
bun run build && bun run test
```

---

### Phase 4: Extract Spawn Handler (Most Complex)

**Step 4.1**: Create `spawn-handler.ts`

Extract:
- `spawnSubsession` method
- `spawnTmuxAgent` method
- `runSubagentAsync` private method

```typescript
// spawn-handler.ts
export interface SpawnHandlerDeps {
  eventStore: EventStore;
  getActiveSession: (sessionId: string) => ActiveSession | undefined;
  createSession: (options: CreateSessionOptions) => Promise<SessionInfo>;
  runAgent: (options: AgentRunOptions) => Promise<unknown>;
  appendEventLinearized: (sessionId: SessionId, type: EventType, payload: Record<string, unknown>) => void;
  emit: (event: string, data: unknown) => void;
}

export class SpawnHandler {
  constructor(private deps: SpawnHandlerDeps) {}

  async spawnSubsession(parentSessionId: string, params: SpawnSubagentParams, toolCallId?: string): Promise<SpawnSubagentResult> {
    // ... existing implementation
  }

  async spawnTmuxAgent(parentSessionId: string, params: SpawnTmuxAgentParams): Promise<SpawnTmuxAgentResult> {
    // ... existing implementation
  }

  private async runSubagentAsync(sessionId: string, parentSessionId: string, task: string, maxTurns: number): Promise<void> {
    // ... existing implementation
  }
}

export function createSpawnHandler(deps: SpawnHandlerDeps): SpawnHandler {
  return new SpawnHandler(deps);
}
```

**Step 4.2**: Update main file to delegate to `SpawnHandler`

**Step 4.3**: Verify tests pass
```bash
bun run build && bun run test
```

---

### Phase 5: Create Facade and Index

**Step 5.1**: Refactor `subagent-ops.ts` as facade

```typescript
// subagent-ops.ts
import { createSpawnHandler, type SpawnHandler } from './spawn-handler.js';
import { createQueryHandler, type QueryHandler } from './query-handler.js';
import { buildSubagentResultsContext } from './results-builder.js';
import type { SubagentOperationsConfig, SpawnSubagentResult, /* ... */ } from './types.js';

export class SubagentOperations {
  private spawnHandler: SpawnHandler;
  private queryHandler: QueryHandler;

  constructor(config: SubagentOperationsConfig) {
    this.spawnHandler = createSpawnHandler(config);
    this.queryHandler = createQueryHandler({
      eventStore: config.eventStore,
      getActiveSession: config.getActiveSession,
    });
  }

  // Delegate to handlers
  spawnSubsession = (...args) => this.spawnHandler.spawnSubsession(...args);
  spawnTmuxAgent = (...args) => this.spawnHandler.spawnTmuxAgent(...args);
  querySubagent = (...args) => this.queryHandler.querySubagent(...args);
  buildSubagentResultsContext = buildSubagentResultsContext;
}
```

**Step 5.2**: Create `index.ts` barrel export

```typescript
// index.ts
export * from './types.js';
export * from './spawn-handler.js';
export * from './query-handler.js';
export * from './results-builder.js';
export { SubagentOperations, createSubagentOperations } from './subagent-ops.js';
```

**Step 5.3**: Update parent `operations/index.ts` to re-export from folder

**Step 5.4**: Verify full test suite
```bash
bun run build && bun run test
```

---

### Phase 6: Move Tests

**Step 6.1**: Create test directory
```bash
mkdir -p packages/agent/src/orchestrator/operations/subagent-ops/__tests__
```

**Step 6.2**: Move any existing tests
```bash
git mv packages/agent/src/orchestrator/operations/__tests__/subagent-ops*.test.ts \
       packages/agent/src/orchestrator/operations/subagent-ops/__tests__/
```

**Step 6.3**: Update test imports if needed

**Step 6.4**: Final verification
```bash
bun run build && bun run test
```

---

## Final Structure

```
orchestrator/operations/
├── subagent-ops/
│   ├── __tests__/
│   │   └── *.test.ts
│   ├── types.ts              # ~80 lines
│   ├── spawn-handler.ts      # ~380 lines
│   ├── query-handler.ts      # ~150 lines
│   ├── results-builder.ts    # ~60 lines
│   ├── subagent-ops.ts       # ~80 lines (facade)
│   └── index.ts              # ~20 lines
├── context-ops.ts
├── skill-loader.ts
├── worktree-ops.ts
└── index.ts                  # Updated to re-export from subagent-ops/
```

---

## API Compatibility

**No breaking changes** - The facade pattern preserves the existing API:

```typescript
// External consumers continue to use:
import { SubagentOperations, createSubagentOperations } from './orchestrator/operations/index.js';

// All methods remain available:
const ops = createSubagentOperations(config);
await ops.spawnSubsession(parentId, params);
await ops.spawnTmuxAgent(parentId, params);
await ops.querySubagent(sessionId, 'status');
ops.buildSubagentResultsContext(active);
```

---

## Risk Assessment

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Circular imports | Low | Types in separate file, careful import ordering |
| Test failures | Low | Run tests after each phase |
| Broken external imports | Low | Barrel exports maintain compatibility |
| Async execution bugs | Medium | Careful extraction of `runSubagentAsync` with its callbacks |

---

## Success Criteria

- [ ] All 5 phases complete with passing builds
- [ ] No external import changes required
- [ ] All existing tests pass
- [ ] Each handler is independently testable
- [ ] Clear separation of concerns:
  - Spawning logic isolated
  - Query logic isolated
  - Results formatting isolated

---

## Verification Commands

```bash
# After each phase
bun run build && bun run test

# Check for broken imports
grep -r "from '.*subagent-ops'" packages/agent/src/ --include="*.ts" | grep -v "subagent-ops/"

# Verify test count unchanged
bun test --reporter=summary 2>&1 | grep "tests"
```
