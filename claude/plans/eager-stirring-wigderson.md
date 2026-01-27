# Agent Package Architectural Analysis & Remediation Plan

## Architectural Score: 76/100

### Scoring Breakdown

| Category | Score | Notes |
|----------|-------|-------|
| **Module Organization** | 18/20 | Excellent 25-module domain separation with clear index.ts exports |
| **Design Patterns** | 14/15 | Good factory patterns, event-sourcing, provider abstraction |
| **Code Quality** | 12/15 | Recent refactoring visible; some god objects remain |
| **Type Safety** | 10/15 | 245 `any`/`unknown` instances (0.29% of 83K lines) |
| **Testability** | 10/15 | 196 test files; some global state hinders isolation |
| **Maintainability** | 12/20 | Deep imports, massive type files need attention |

### What's Working Well

1. **Clear domain separation** - 25 well-defined modules (types, logging, auth, providers, tools, hooks, agent, context, skills, events, orchestrator, etc.)
2. **Good extraction patterns** - Recent refactoring extracted AgentEventEmitter, AgentToolExecutor, AgentStreamProcessor, AgentCompactionHandler, AgentTurnRunner from TronAgent
3. **Factory functions everywhere** - `createLogger()`, `createProvider()`, `createSessionManager()`, etc.
4. **Event-driven architecture** - EventStore with SQLite persistence, event reconstruction
5. **Provider abstraction** - Unified API for Anthropic, OpenAI, Google

---

## Identified Anti-Patterns (Priority Order)

### HIGH Priority

#### 1. Incomplete Logging Coverage + Global State
**Current state:** 635 log statements across 100 files, but major gaps exist:
- File operations have no success logging
- Compaction/memory management is silent
- Tool execution success not confirmed
- Error context often incomplete
- No standardized error categorization

**Global state issue:** `logger.ts:52,378` has mutable module-level variables.

#### 2. Massive Type Definition Files
- `packages/agent/src/rpc/types.ts` - **1,928 lines**
- `packages/agent/src/events/types.ts` - **1,306 lines**

**Impact:** IDE performance, cognitive load, hard to navigate, rebuild cascades.

### MEDIUM Priority

#### 3. Deep Import Paths
45 instances of `../../../` imports throughout orchestrator subdirectories.

#### 4. Provider Code Duplication
4 provider files duplicate common patterns (~400 lines).

---

## Remediation Plan

### Phase 1: Comprehensive System-Wide Logging Framework
**Risk:** LOW-MEDIUM | **Files:** ~40 | **Est. Test Impact:** Minimal (adding logs, not changing behavior)

This phase establishes a robust, efficient, and comprehensive logging framework that makes full use of all log levels and provides thorough observability for both success paths and all error conditions. All logs persist to the central SQLite database for historical analysis.

---

#### 1.1 Log Level Conventions

| Level | Purpose | When to Use | Example |
|-------|---------|-------------|---------|
| **TRACE** | Detailed debugging | Loop iterations, internal state changes, method entry/exit for complex flows | `logger.trace('Processing content block', { index, type })` |
| **DEBUG** | Development diagnostics | Intermediate values, decision branches, non-critical state | `logger.debug('Tool schema converted', { toolCount })` |
| **INFO** | Operational milestones | User-visible operations complete, key state transitions | `logger.info('Session created', { sessionId, model })` |
| **WARN** | Recoverable issues | Degraded operation, fallbacks triggered, unusual conditions | `logger.warn('Retrying API call', { attempt, maxRetries })` |
| **ERROR** | Failures requiring attention | Operation failures, API errors, exceptions caught | `logger.error('Tool execution failed', { toolName, error })` |
| **FATAL** | System-critical failures | Unrecoverable state, shutdown required | `logger.fatal('Database corruption detected', { path })` |

---

#### 1.2 LoggerRegistry Pattern (Eliminate Global State)

**Files to Create/Modify:**
| File | Action |
|------|--------|
| `logging/__tests__/logger-registry.test.ts` | Create - Test independent registry instances |
| `logging/logger-registry.ts` | Create - LoggerRegistry class |
| `logging/logger.ts` | Modify - Remove globals, delegate to registry |
| `logging/index.ts` | Modify - Re-export registry |

**Implementation:**
```typescript
// logger-registry.ts
export class LoggerRegistry {
  private transport: SQLiteTransport | null = null;
  private rootLogger: TronLogger | null = null;

  initialize(db: Database.Database, options?: TransportOptions): void { ... }
  createLogger(component: string, context?: LogContext): TronLogger { ... }
  close(): void { ... }
}

// Backward-compatible convenience functions
let defaultRegistry: LoggerRegistry | null = null;
export function getDefaultRegistry(): LoggerRegistry { ... }
export function createLogger(component: string): TronLogger {
  return getDefaultRegistry().createLogger(component);
}
```

---

#### 1.3 Error Categorization System

**New File:** `logging/error-codes.ts`

```typescript
export enum ErrorCategory {
  // Infrastructure
  DATABASE = 'DB',
  FILESYSTEM = 'FS',
  NETWORK = 'NET',

  // Provider/API
  PROVIDER_AUTH = 'PAUTH',
  PROVIDER_RATE_LIMIT = 'PRATE',
  PROVIDER_API = 'PAPI',
  PROVIDER_STREAM = 'PSTRM',

  // Agent/Tool
  TOOL_EXECUTION = 'TOOL',
  TOOL_VALIDATION = 'TVAL',
  GUARDRAIL = 'GUARD',

  // Session
  SESSION_STATE = 'SESS',
  EVENT_PERSIST = 'EVNT',

  // Context/Memory
  COMPACTION = 'COMP',
  TOKEN_LIMIT = 'TLIM',
}

export interface StructuredError {
  category: ErrorCategory;
  code: string;           // e.g., 'FS_NOT_FOUND', 'PRATE_429'
  message: string;
  context: Record<string, unknown>;
  recoverable: boolean;
  retryable: boolean;
}

export function categorizeError(error: Error, context?: Record<string, unknown>): StructuredError { ... }
```

---

#### 1.4 Required Logging Points by Domain

##### **File System Tools** (`tools/fs/`)
| Operation | Entry (TRACE) | Success (INFO) | Error (ERROR) |
|-----------|---------------|----------------|---------------|
| Read | File path, encoding | Bytes read, duration | Category, path, permissions |
| Write | File path, size | Bytes written, duration | Category, disk space |
| Edit | File path, changes count | Lines modified, duration | Conflict details |
| Grep | Pattern, paths | Matches found, files scanned, duration | Invalid regex |
| Find | Pattern, root | Files found, dirs scanned, duration | Access denied paths |

**Files to update:**
- `tools/fs/read.ts` - Add success logging with size/duration
- `tools/fs/write.ts` - Add success logging with bytes written
- `tools/fs/edit.ts` - Add success logging with change count
- `tools/fs/grep.ts` - Add success logging with match statistics
- `tools/fs/find.ts` - Add success logging with search statistics

##### **Provider API Calls** (`providers/`)
| Operation | Entry (DEBUG) | Success (INFO) | Error (ERROR) |
|-----------|---------------|----------------|---------------|
| Stream start | Model, tools count | - | Auth, rate limit, API error |
| Stream chunk | - (too noisy) | - | Stream interruption with partial |
| Stream complete | - | Tokens in/out, cache stats, duration | - |
| Retry | Attempt number, backoff | Recovered | Max retries exceeded |

**Files to update:**
- `providers/anthropic.ts` - Enrich error context, add retry logging
- `providers/google.ts` - Enrich error context, add retry logging
- `providers/openai.ts` - Enrich error context, add retry logging
- `providers/openai-codex.ts` - Enrich error context, add retry logging

##### **Session Lifecycle** (`orchestrator/session/`)
| Operation | Entry (DEBUG) | Success (INFO) | Error (ERROR) |
|-----------|---------------|----------------|---------------|
| Create | Options | Session ID, model, worktree | Max sessions |
| Resume | Session ID | Messages restored, trackers rebuilt | Not found |
| End | Session ID, options | Worktree merged/released | Merge conflict |
| Fork | Source ID, event ID | New session ID, worktree | Fork failed |
| Plan mode enter | Session ID, skill | Blocked tools set | - |
| Plan mode exit | Session ID | Approval status | - |

**Files to update:**
- `orchestrator/session/session-manager.ts` - Add plan mode transition logging
- `orchestrator/handlers/plan-mode-handler.ts` - Add state change logging

##### **Compaction & Memory** (`context/`, `agent/`)
| Operation | Entry (DEBUG) | Success (INFO) | Error (ERROR) |
|-----------|---------------|----------------|---------------|
| Compaction start | Tokens before, threshold | - | - |
| Compaction complete | - | Tokens before/after, ratio, duration | Summarization failed |
| Token estimation | - | - (TRACE only) | Overflow |
| Context clear | Session ID, reason | Messages cleared | - |

**Files to update:**
- `agent/compaction-handler.ts` - Add before/after token stats
- `context/compaction-engine.ts` - Add detailed statistics logging
- `context/context-manager.ts` - Add clear/snapshot logging

##### **Tool Execution** (`agent/tool-executor.ts`)
| Operation | Entry (DEBUG) | Success (INFO) | Error (ERROR) |
|-----------|---------------|----------------|---------------|
| Tool invoke | Tool name, call ID | Duration, result size | Failure with category |
| Guardrail check | Tool name | - | Block reason, rules triggered |
| Result truncation | Original size | Final size, truncation ratio | - |

##### **Subagent Lifecycle** (`tools/subagent/`)
| Operation | Entry (DEBUG) | Success (INFO) | Error (ERROR) |
|-----------|---------------|----------------|---------------|
| Spawn | Parent ID, type, prompt preview | Subagent ID, model | Spawn failed |
| Query | Subagent ID | Status, pending results | Not found |
| Complete | Subagent ID | Duration, tokens used | Error propagation |
| Result handoff | Parent ID, subagent ID | Results injected | - |

**Files to update:**
- `tools/subagent/spawn-subagent.ts` - Add lifecycle logging
- `tools/subagent/spawn-tmux-agent.ts` - Add lifecycle logging
- `tools/subagent/query-subagent.ts` - Add status logging
- `tools/subagent/subagent-tracker.ts` - Add result handoff logging

##### **Event Persistence** (`events/`, `orchestrator/persistence/`)
| Operation | Entry (TRACE) | Success (DEBUG) | Error (ERROR) |
|-----------|---------------|-----------------|---------------|
| Append | Event type, session ID | Event ID, parent ID | Persistence failure |
| Batch flush | Count | Duration, events written | Partial failure |
| Query | Session ID, criteria | Results count, duration | Query timeout |
| Reconstruct | Session ID | Messages rebuilt, duration | Corruption |

**Files to update:**
- `events/event-store.ts` - Add query/reconstruct logging
- `events/sqlite/facade.ts` - Add operation logging
- `orchestrator/persistence/event-persister.ts` - Enhance batch logging

##### **Skill Loading** (`skills/`, `orchestrator/operations/`)
| Operation | Entry (DEBUG) | Success (INFO) | Error (ERROR) |
|-----------|---------------|----------------|---------------|
| Scan | Directories | Skills found, duration | Directory access |
| Load | Skill name | Content size, injected | Parse error |
| Remove | Skill name | Removed successfully | Not found |

**Files to update:**
- `skills/loader.ts` - Add scan statistics
- `skills/skill-tracker.ts` - Add tracking logging
- `orchestrator/operations/skill-loader.ts` - Add injection logging

##### **Hook Execution** (`hooks/`)
| Operation | Entry (DEBUG) | Success (DEBUG) | Error (WARN) |
|-----------|---------------|-----------------|---------------|
| Discover | Paths | Hooks found | Access error |
| Execute | Hook name, event | Duration, modification | Timeout, exception |

**Files to update:**
- `hooks/engine.ts` - Add execution timing
- `hooks/discovery.ts` - Add discovery logging

---

#### 1.5 Structured Logging Standards

**Always include these fields when relevant:**
```typescript
// Session context (automatic via child logger)
{ sessionId, workspaceId }

// Tool operations
{ toolName, toolCallId, duration }

// Provider operations
{ model, provider, inputTokens, outputTokens, cacheReadTokens }

// File operations
{ path, sizeBytes, duration }

// Errors (always structured)
{
  error: error.message,
  code: 'FS_NOT_FOUND',
  category: ErrorCategory.FILESYSTEM,
  stack: error.stack,  // Only at ERROR level
  context: { ... }
}
```

---

#### 1.6 Implementation Order

1. **Create infrastructure** (logging-registry, error-codes)
2. **Update tool executor** (central point for all tool logging)
3. **Update providers** (error enrichment, retry logging)
4. **Update file system tools** (success path logging)
5. **Update session manager** (state transition logging)
6. **Update compaction** (statistics logging)
7. **Update event store** (operation logging)
8. **Update subagent tools** (lifecycle logging)
9. **Update skill/hook systems** (discovery/execution logging)

---

#### 1.7 Verification

```bash
# After each file update
bun run build && bun run test

# Verify logging works end-to-end
LOG_LEVEL=debug bun run test -- packages/agent/src/logging

# Verify no console.log slipped in
grep -r "console.log" packages/agent/src --include="*.ts" | grep -v test | grep -v ".d.ts"
```

---

### Phase 2: Split RPC Types File
**Risk:** LOW | **Files:** ~15 | **Est. Test Impact:** None (types only)

#### Problem
`rpc/types.ts` at 1,928 lines is unwieldy for navigation and maintenance.

#### Solution: Domain-Based Splitting
Split into logical domain files while maintaining re-exports for backward compatibility.

#### New Structure
```
packages/agent/src/rpc/types/
  index.ts            (re-exports all - backward compatible)
  base.ts             (RpcRequest, RpcResponse, RpcError)
  session.ts          (Session* types)
  agent.ts            (Agent* types)
  model.ts            (Model* types)
  events.ts           (Event* types)
  memory.ts           (Memory* types)
  skill.ts            (Skill* types)
  context.ts          (Context* types)
  browser.ts          (Browser* types)
  filesystem.ts       (Filesystem* types)
  worktree.ts         (Worktree* types)
  system.ts           (System* types)
  streaming.ts        (Streaming event types)
```

#### Migration Steps
1. Create `rpc/types/` directory
2. Split types into domain files (one commit per domain)
3. Create `rpc/types/index.ts` re-exporting all
4. Update `rpc/types.ts` to re-export from `types/index.ts`
5. Run full test suite

---

### Phase 3: Split Events Types File
**Risk:** LOW | **Files:** ~12 | **Est. Test Impact:** None (types only)

#### Problem
`events/types.ts` at 1,306 lines contains all event definitions.

#### Solution: Event Category Splitting
```
packages/agent/src/events/types/
  index.ts            (re-exports all)
  branded.ts          (EventId, SessionId, WorkspaceId, BranchId)
  base.ts             (BaseEvent, SessionEvent union)
  session.ts          (Session lifecycle events)
  message.ts          (Message events)
  tool.ts             (Tool events)
  stream.ts           (Streaming events)
  config.ts           (Config events)
  compact.ts          (Compaction events)
  skill.ts            (Skill events)
  plan.ts             (Plan mode events)
  subagent.ts         (Subagent events)
  type-guards.ts      (isToolCallEvent, etc.)
```

---

### Phase 4: Fix Deep Import Paths
**Risk:** LOW | **Files:** ~20 | **Est. Test Impact:** None

#### Problem
45 instances of `../../../` imports indicate missing module boundary exports.

#### Solution
Update each module's `index.ts` to export commonly-needed symbols, then update imports.

#### Examples
```typescript
// Before (in orchestrator/turn/handlers/*.ts):
import { createLogger } from '../../../logging/logger.js';
import type { SessionId } from '../../../events/types.js';

// After:
import { createLogger } from '../../../logging/index.js';
import type { SessionId } from '../../../events/index.js';
```

#### Process
1. Audit all `../../../` imports, group by target module
2. Update each module's `index.ts` to export needed symbols
3. Update imports incrementally with test verification after each module

---

### Phase 5: Consolidate Provider Utilities
**Risk:** MEDIUM | **Files:** 8 | **Est. Test Impact:** Provider tests

#### Problem
4 provider files duplicate common patterns: tool schema conversion, token usage normalization, error handling.

#### Solution: Composable Utilities (Not Inheritance)
Extend existing `providers/base/` with shared utilities.

#### New Structure
```
packages/agent/src/providers/base/
  types.ts           (exists)
  stream-retry.ts    (exists)
  tool-schema.ts     (NEW - tool conversion utilities)
  token-usage.ts     (NEW - usage normalization helpers)
  stop-reason.ts     (NEW - stop reason mapping)
  content-blocks.ts  (NEW - content transformation)
  index.ts           (updated exports)
```

#### Implementation Approach
1. Write tests for each utility FIRST
2. Extract common logic from `anthropic.ts` into utilities
3. Refactor `anthropic.ts` to use utilities, verify tests pass
4. Repeat for `google.ts`, `openai.ts`, `openai-codex.ts`

---

## Implementation Order & Dependencies

```
Phase 1 (Comprehensive Logging Framework) ─────────────────┐
  ├── 1.1 LoggerRegistry + error-codes (infrastructure)    │
  ├── 1.2 Tool executor logging                            │
  ├── 1.3 Provider error enrichment                        │
  ├── 1.4 File system tool success logging                 │
  ├── 1.5 Session/compaction/event logging                 │
  └── 1.6 Subagent/skill/hook logging                      │
                                                           │
Phase 2 (RPC Types Split)     [Can start after 1.1] ───────┤
                                                           │
Phase 3 (Event Types Split)   [Can start after 1.1] ───────┤
                                                           │
Phase 4 (Deep Import Paths)   [After Phases 2-3] ──────────┤
                                                           │
Phase 5 (Provider Utilities)  [After Phase 1.3] ───────────┘
```

**Recommended execution:**
1. Phase 1.1-1.2 first (logging infrastructure)
2. Phases 1.3-1.6, 2, 3 can parallelize
3. Phase 4 after type splitting complete
4. Phase 5 last (benefits from Phase 1.3 error patterns)

---

## Phase 1 Files Summary (All Logging Updates)

| Category | Files to Update |
|----------|-----------------|
| **Infrastructure (Create)** | `logging/logger-registry.ts`, `logging/error-codes.ts`, `logging/__tests__/logger-registry.test.ts` |
| **Infrastructure (Modify)** | `logging/logger.ts`, `logging/index.ts` |
| **File System Tools** | `tools/fs/read.ts`, `tools/fs/write.ts`, `tools/fs/edit.ts`, `tools/fs/grep.ts`, `tools/fs/find.ts` |
| **Providers** | `providers/anthropic.ts`, `providers/google.ts`, `providers/openai.ts`, `providers/openai-codex.ts` |
| **Session/Orchestrator** | `orchestrator/session/session-manager.ts`, `orchestrator/handlers/plan-mode-handler.ts` |
| **Compaction/Context** | `agent/compaction-handler.ts`, `context/compaction-engine.ts`, `context/context-manager.ts` |
| **Tool Execution** | `agent/tool-executor.ts` |
| **Subagent** | `tools/subagent/spawn-subagent.ts`, `tools/subagent/spawn-tmux-agent.ts`, `tools/subagent/query-subagent.ts`, `tools/subagent/subagent-tracker.ts` |
| **Events** | `events/event-store.ts`, `events/sqlite/facade.ts`, `orchestrator/persistence/event-persister.ts` |
| **Skills** | `skills/loader.ts`, `skills/skill-tracker.ts`, `orchestrator/operations/skill-loader.ts` |
| **Hooks** | `hooks/engine.ts`, `hooks/discovery.ts` |

**Total: ~35 files** (mostly adding 3-10 lines of logging per file)

---

## Test-Driven Development Protocol

For each phase:

1. **Create branch:**
   ```bash
   git checkout -b refactor/phase-N-description
   bun run build && bun run test  # Baseline
   ```

2. **Write tests FIRST** for new modules

3. **Implement changes** with incremental commits

4. **Verify after each file:**
   ```bash
   bun run build && bun run test
   ```

5. **Commit format:**
   ```
   refactor(logging): extract LoggerRegistry from global state
   ```

---

## Success Metrics

| Metric | Before | After |
|--------|--------|-------|
| **Logging Coverage** | | |
| Total log statements | 635 | ~900+ |
| Files with logging | 100 | ~135 |
| Error logs with category codes | 0 | 100% |
| Success path logging (tools) | Minimal | All operations |
| **Architecture** | | |
| Max type file size | 1,928 lines | <400 lines |
| Global mutable state locations | 2 | 0 |
| Deep imports (`../../../`) | 45 | <10 |
| Provider LOC duplication | ~400 lines | <100 lines |
| Test coverage | Baseline | No decrease |

---

## Verification Steps

After all phases complete:
```bash
# Full build and test
bun run build && bun run test

# Verify no new circular dependencies
npx madge --circular packages/agent/src/index.ts

# Verify type exports work
npx tsc --noEmit
```

### Logging Framework Verification

```bash
# Count log statements by level
grep -r "logger\.\(trace\|debug\|info\|warn\|error\|fatal\)" packages/agent/src --include="*.ts" | grep -v test | wc -l

# Verify error categorization usage
grep -r "ErrorCategory\." packages/agent/src --include="*.ts" | grep -v test | wc -l

# Test logging at different levels
LOG_LEVEL=trace bun run test -- packages/agent/src/tools/fs
LOG_LEVEL=info bun run test -- packages/agent/src/orchestrator

# Query historical logs from SQLite (via @tron-db skill)
# SELECT * FROM logs WHERE level >= 40 ORDER BY timestamp DESC LIMIT 50;
```

### Manual Verification Checklist

- [ ] File read operation logs: entry (trace), success (info) with size/duration
- [ ] File write operation logs: success (info) with bytes written
- [ ] Tool execution logs: start (debug), success (info) with duration
- [ ] Provider errors include: model, error category, retry count
- [ ] Session create/resume logs: session ID, model, worktree info
- [ ] Compaction logs: tokens before/after, ratio, duration
- [ ] Event persistence logs: event ID, parent ID, duration
- [ ] All ERROR logs include structured error with category code
