# Agent Package Architectural Cleanup - Phase 2

## Goal: Achieve 20/20 on Module Organization and Maintainability

**Current Score:** 84/100
**Target Score:** 92/100

---

## Anti-Pattern 1: Circular Dependencies (33 cycles → 0)

### Analysis

| Category | Count | Cycles | Root Cause |
|----------|-------|--------|------------|
| RPC handler registration | 22 | handler.ts ↔ handlers/*.ts | Handlers import handler for types |
| Logger self-reference | 1 | logger-registry.ts ↔ logger.ts | Mutual dependency |
| Gateway barrel imports | 6 | gateway/index.ts chains | Barrel re-exports through adapters |
| Root index barrel | 4 | index.ts ↔ server.ts/services | Everything exports through index |

### Solution Strategy

#### 1.1 RPC Handler Cycles (22 cycles)

**Problem:** `rpc/handler.ts` imports from `rpc/handlers/*.ts`, and handlers import types from `handler.ts`.

**Solution:** Extract shared types to dedicated file.

**Files to create:**
```
rpc/
  types/
    handler-types.ts    (NEW - RpcHandlerFn, HandlerContext, etc.)
```

**Files to modify:**
| File | Change |
|------|--------|
| `rpc/handler.ts` | Import types from `types/handler-types.ts` |
| `rpc/handlers/*.ts` (18 files) | Import types from `types/handler-types.ts` instead of `handler.ts` |
| `rpc/types/index.ts` | Re-export handler types |

**Implementation:**
```typescript
// rpc/types/handler-types.ts (NEW)
import type { RpcRequest, RpcResponse } from './base.js';

export interface HandlerContext {
  orchestrator: unknown; // Will be properly typed via generics
  skillRegistry: unknown;
  // ... other context fields
}

export type RpcHandlerFn = (
  request: RpcRequest,
  context: HandlerContext
) => Promise<RpcResponse>;

export interface RpcHandlerRegistration {
  method: string;
  handler: RpcHandlerFn;
  schema?: unknown;
}
```

---

#### 1.2 Logger Cycle (1 cycle)

**Problem:** `logger-registry.ts` imports from `logger.ts` for TronLogger type, `logger.ts` imports from `logger-registry.ts` for getDefaultRegistry.

**Solution:** Extract shared types to dedicated file, use lazy initialization.

**Files to create:**
```
logging/
  types.ts    (NEW - move TronLogger interface, LogLevel, etc.)
```

**Files to modify:**
| File | Change |
|------|--------|
| `logging/types.ts` | Create with TronLogger, LogLevel, TransportOptions |
| `logging/logger.ts` | Import types from `types.ts`, lazy-load registry |
| `logging/logger-registry.ts` | Import types from `types.ts` |
| `logging/index.ts` | Re-export from `types.ts` |

**Implementation:**
```typescript
// logging/types.ts (NEW)
export enum LogLevel {
  TRACE = 10,
  DEBUG = 20,
  INFO = 30,
  WARN = 40,
  ERROR = 50,
  FATAL = 60,
}

export interface TronLogger {
  trace(message: string, context?: Record<string, unknown>): void;
  debug(message: string, context?: Record<string, unknown>): void;
  info(message: string, context?: Record<string, unknown>): void;
  warn(message: string, context?: Record<string, unknown>): void;
  error(message: string, context?: Record<string, unknown>): void;
  fatal(message: string, context?: Record<string, unknown>): void;
  child(context: Record<string, unknown>): TronLogger;
}

export interface TransportOptions {
  minLevel?: LogLevel;
  sessionId?: string;
}
```

```typescript
// logging/logger.ts (modified)
import type { TronLogger, LogLevel } from './types.js';

// Lazy registry access to break cycle
let _registry: LoggerRegistry | null = null;
function getRegistry(): LoggerRegistry {
  if (!_registry) {
    // Dynamic import or lazy require
    _registry = require('./logger-registry.js').getDefaultRegistry();
  }
  return _registry;
}
```

---

#### 1.3 Gateway/Index Barrel Cycles (6 cycles)

**Problem:** `gateway/index.ts` → `gateway/rpc/index.ts` → `context-factory.ts` → `adapters/agent.adapter.ts` → `gateway/rpc/types.ts` → `index.ts`

**Solution:** Stop re-exporting through adapter chain. Create explicit exports.

**Files to modify:**
| File | Change |
|------|--------|
| `gateway/index.ts` | Don't re-export from `rpc/index.ts` internals |
| `gateway/rpc/index.ts` | Export only public API, not internal adapters |
| `gateway/rpc/types.ts` | Don't import from root `index.ts` |

**Before:**
```typescript
// gateway/index.ts
export * from './rpc/index.js';  // Pulls in everything
```

**After:**
```typescript
// gateway/index.ts
export { TronWebSocketServer } from './websocket.js';
export { createRpcContext } from './rpc/context-factory.js';
export type { RpcContext } from './rpc/types.js';
// Explicit exports only
```

---

#### 1.4 Root Index Barrel Cycles (4 cycles)

**Problem:** `index.ts` exports everything including `server.ts`, which imports from `index.ts`.

**Solution:** Create separate entry points for different use cases.

**Files to create:**
```
index.ts           (public API - types, factories)
server.ts          (server entry point - imports from modules directly)
internal.ts        (internal utilities - not re-exported)
```

**Files to modify:**
| File | Change |
|------|--------|
| `index.ts` | Remove server.ts export, export only public API |
| `server.ts` | Import from specific modules, not index.ts |
| `services/index.ts` | Don't re-export through root index |

---

### Verification

```bash
# After each change
npx madge --circular packages/agent/src/index.ts

# Target: 0 circular dependencies
```

---

## Anti-Pattern 2: Deep Import Paths (49 → 0)

### Analysis

```bash
# Current deep imports
grep -r "\.\./\.\./\.\." --include="*.ts" | grep -v test | grep -v ".d.ts"
```

**Locations:**
| Directory | Count | Pattern |
|-----------|-------|---------|
| `orchestrator/turn/handlers/` | 18 | `../../../logging/` |
| `orchestrator/controllers/` | 12 | `../../../events/` |
| `orchestrator/operations/` | 8 | `../../../tools/` |
| `orchestrator/session/` | 6 | `../../../providers/` |
| `gateway/rpc/adapters/` | 5 | `../../../orchestrator/` |

### Solution Strategy

#### 2.1 Ensure All Modules Export via index.ts

**Audit checklist:**
| Module | Has index.ts | Exports Complete |
|--------|--------------|------------------|
| `logging/` | ✅ | Verify all exports |
| `events/` | ✅ | Verify all exports |
| `providers/` | ✅ | Verify all exports |
| `tools/` | ✅ | Verify all exports |
| `types/` | ✅ | Verify all exports |
| `orchestrator/` | ✅ | Verify all exports |

#### 2.2 Update Deep Imports to Module Imports

**Transformation pattern:**
```typescript
// Before
import { createLogger } from '../../../logging/logger.js';
import type { SessionId } from '../../../events/types.js';
import { categorizeError } from '../../../logging/error-categorization.js';

// After
import { createLogger, categorizeError } from '../../../logging/index.js';
import type { SessionId } from '../../../events/index.js';
```

**Files to update (by directory):**

##### orchestrator/turn/handlers/ (18 files)
```
compaction-event-handler.ts
lifecycle-event-handler.ts
streaming-event-handler.ts
subagent-forwarder.ts
tool-event-handler.ts
turn-event-handler.ts
```

##### orchestrator/controllers/ (12 files)
```
agent-controller.ts
browser-controller.ts
event-controller.ts
model-controller.ts
notification-controller.ts
plan-mode-controller.ts
todo-controller.ts
worktree-controller.ts
```

##### orchestrator/operations/ (8 files)
```
context-ops.ts
skill-loader.ts
worktree-ops.ts
subagent-ops/*.ts
```

##### orchestrator/session/ (6 files)
```
auth-provider.ts
session-context.ts
session-manager.ts
session-reconstructor.ts
```

##### gateway/rpc/adapters/ (5 files)
```
agent.adapter.ts
event-store.adapter.ts
session.adapter.ts
skill.adapter.ts
worktree.adapter.ts
```

#### 2.3 Add Missing Exports to Module Index Files

Before updating imports, ensure each module's `index.ts` exports everything needed.

**Example additions:**
```typescript
// logging/index.ts - ensure these are exported
export { createLogger } from './logger.js';
export { categorizeError, LogErrorCategory, LogErrorCodes } from './error-categorization.js';
export { LoggerRegistry, getDefaultRegistry } from './logger-registry.js';
export type { TronLogger, LogLevel, TransportOptions } from './types.js';
```

### Implementation Order

1. **Audit** - List all deep imports and their targets
2. **Update index.ts files** - Add any missing exports
3. **Update imports** - One directory at a time, test after each
4. **Verify** - `grep -r "\.\./\.\./\.\." --include="*.ts" | grep -v test` should return 0

---

## Anti-Pattern 3: Large Files (6 files > 700 lines)

### Analysis

| File | Lines | Complexity | Split Strategy |
|------|-------|------------|----------------|
| `providers/google.ts` | 1,200 | HIGH | Extract streaming, content building |
| `providers/anthropic.ts` | 1,090 | HIGH | Extract streaming, content building |
| `session/worktree-coordinator.ts` | 1,001 | MEDIUM | Extract operations |
| `providers/openai-codex.ts` | 970 | HIGH | Extract streaming, response handling |
| `auth/google-oauth.ts` | 866 | MEDIUM | Extract token management |
| `orchestrator/session/session-manager.ts` | 787 | MEDIUM | Extract reconstructor logic |

### Solution Strategy

#### 3.1 Provider Files (google.ts, anthropic.ts, openai-codex.ts, openai.ts)

**Common patterns to extract:**

##### A. Stream Processing (~200 lines each)
```
providers/
  base/
    stream-processor.ts  (NEW)
```

**Content:**
```typescript
// stream-processor.ts
export interface StreamChunk {
  type: 'content' | 'tool_use' | 'thinking' | 'usage';
  data: unknown;
}

export interface StreamProcessor<TEvent> {
  processEvent(event: TEvent): StreamChunk | null;
  finalize(): StreamChunk[];
}

export abstract class BaseStreamProcessor<TEvent> implements StreamProcessor<TEvent> {
  protected buffer: StreamChunk[] = [];

  abstract processEvent(event: TEvent): StreamChunk | null;

  finalize(): StreamChunk[] {
    return this.buffer;
  }
}
```

##### B. Content Block Building (~150 lines each)
```
providers/
  base/
    content-builder.ts  (NEW)
```

**Content:**
```typescript
// content-builder.ts
export interface ContentBlockBuilder {
  addText(text: string): void;
  addToolUse(id: string, name: string, input: unknown): void;
  addThinking(text: string): void;
  build(): ContentBlock[];
}

export class StandardContentBuilder implements ContentBlockBuilder {
  private blocks: ContentBlock[] = [];
  // ... implementation
}
```

##### C. Tool Schema Conversion (~100 lines each)
```
providers/
  base/
    tool-schema.ts  (NEW)
```

**Content:**
```typescript
// tool-schema.ts
export function toAnthropicTool(tool: TronTool): AnthropicTool { ... }
export function toOpenAITool(tool: TronTool): OpenAITool { ... }
export function toGoogleTool(tool: TronTool): GoogleTool { ... }
```

##### D. Provider-Specific Stream Handlers
```
providers/
  anthropic/
    index.ts              (re-exports)
    provider.ts           (main class, ~400 lines)
    stream-handler.ts     (streaming logic, ~300 lines)
    types.ts              (Anthropic-specific types)
  google/
    index.ts
    provider.ts
    stream-handler.ts
    safety-handler.ts     (safety rating logic)
    types.ts
  openai/
    index.ts
    provider.ts
    stream-handler.ts
    types.ts
  openai-codex/
    index.ts
    provider.ts
    stream-handler.ts
    response-handler.ts   (Responses API specifics)
    types.ts
```

**Target:** Each file < 500 lines

---

#### 3.2 worktree-coordinator.ts (1,001 lines)

**Extract into:**
```
session/
  worktree/
    index.ts                    (re-exports)
    coordinator.ts              (main class, ~300 lines)
    branch-manager.ts           (branch operations, ~250 lines)
    merge-handler.ts            (merge logic, ~200 lines)
    cleanup-handler.ts          (cleanup operations, ~150 lines)
    types.ts                    (worktree types)
```

---

#### 3.3 google-oauth.ts (866 lines)

**Extract into:**
```
auth/
  google/
    index.ts                    (re-exports)
    oauth-client.ts             (main class, ~300 lines)
    token-manager.ts            (token refresh, storage, ~250 lines)
    auth-flow.ts                (OAuth flow handlers, ~200 lines)
    types.ts                    (Google auth types)
```

---

#### 3.4 session-manager.ts (787 lines)

**Extract into:**
```
orchestrator/session/
  index.ts                      (re-exports)
  session-manager.ts            (main class, ~350 lines)
  session-factory.ts            (creation logic, ~150 lines)
  session-lifecycle.ts          (start/stop/pause, ~150 lines)
  types.ts                      (session types, already exists)
```

---

### Implementation Order

#### Phase 3A: Extract Shared Provider Utilities (LOW risk)
1. Create `providers/base/stream-processor.ts`
2. Create `providers/base/content-builder.ts`
3. Create `providers/base/tool-schema.ts`
4. Update `providers/base/index.ts`
5. Test: `bun run build && bun run test`

#### Phase 3B: Split Provider Files (MEDIUM risk)
1. Start with `openai.ts` (smallest provider, 641 lines)
2. Extract to `providers/openai/` structure
3. Verify tests pass
4. Repeat for `anthropic.ts`, `google.ts`, `openai-codex.ts`

#### Phase 3C: Split Supporting Files (LOW risk)
1. Split `worktree-coordinator.ts`
2. Split `google-oauth.ts`
3. Split `session-manager.ts`

---

## Implementation Schedule

### Day 1: Circular Dependencies (Anti-Pattern 1)

| Task | Files | Risk |
|------|-------|------|
| 1.1 Extract RPC handler types | 1 new, 19 modify | LOW |
| 1.2 Extract logger types | 1 new, 3 modify | LOW |
| 1.3 Fix gateway barrel exports | 3 modify | MEDIUM |
| 1.4 Fix root index exports | 3 modify | MEDIUM |

**Checkpoint:** `npx madge --circular` returns 0 cycles

### Day 2: Deep Imports (Anti-Pattern 2)

| Task | Files | Risk |
|------|-------|------|
| 2.1 Audit module index exports | 6 modify | LOW |
| 2.2 Update orchestrator/turn/handlers | 6 modify | LOW |
| 2.3 Update orchestrator/controllers | 8 modify | LOW |
| 2.4 Update orchestrator/operations | 8 modify | LOW |
| 2.5 Update orchestrator/session | 4 modify | LOW |
| 2.6 Update gateway/rpc/adapters | 5 modify | LOW |

**Checkpoint:** `grep -r "\.\./\.\./\.\."` returns 0 matches

### Day 3: Large Files - Shared Utilities (Anti-Pattern 3A)

| Task | Files | Risk |
|------|-------|------|
| 3.1 Create stream-processor.ts | 1 new | LOW |
| 3.2 Create content-builder.ts | 1 new | LOW |
| 3.3 Create tool-schema.ts | 1 new | LOW |

**Checkpoint:** Build passes, all provider tests pass

### Day 4-5: Large Files - Provider Split (Anti-Pattern 3B)

| Task | Files | Risk |
|------|-------|------|
| 3.4 Split openai.ts | 4 new, 1 delete | MEDIUM |
| 3.5 Split anthropic.ts | 4 new, 1 delete | MEDIUM |
| 3.6 Split google.ts | 5 new, 1 delete | MEDIUM |
| 3.7 Split openai-codex.ts | 5 new, 1 delete | MEDIUM |

**Checkpoint:** All provider tests pass

### Day 6: Large Files - Supporting Files (Anti-Pattern 3C)

| Task | Files | Risk |
|------|-------|------|
| 3.8 Split worktree-coordinator.ts | 5 new, 1 delete | MEDIUM |
| 3.9 Split google-oauth.ts | 4 new, 1 delete | MEDIUM |
| 3.10 Split session-manager.ts | 3 new, 1 modify | MEDIUM |

**Checkpoint:** Full test suite passes

---

## Verification Commands

```bash
# After each phase
bun run build && bun run test

# Circular dependencies (target: 0)
npx madge --circular packages/agent/src/index.ts

# Deep imports (target: 0)
grep -r "\.\./\.\./\.\." packages/agent/src --include="*.ts" | grep -v test | grep -v ".d.ts" | wc -l

# Large files (target: 0 files > 700 lines)
find packages/agent/src -name "*.ts" -not -path "*test*" -exec wc -l {} \; | awk '$1 > 700 {print}'

# File count by size
find packages/agent/src -name "*.ts" -not -path "*test*" -exec wc -l {} \; | sort -rn | head -20
```

---

## Success Metrics

| Metric | Before | After | Target |
|--------|--------|-------|--------|
| Circular dependencies | 33 | 0 | 0 |
| Deep imports (`../../../`) | 49 | 0 | 0 |
| Files > 700 lines | 6 | 0 | 0 |
| Max file size | 1,200 lines | <500 lines | <500 |
| Module Organization score | 18/20 | 20/20 | 20/20 |
| Maintainability score | 12/20 | 20/20 | 20/20 |
| **Total score** | **84/100** | **92/100** | **92/100** |

---

## Rollback Strategy

Each phase is independently revertable:

```bash
# If a phase introduces issues
git revert HEAD~N  # N = number of commits in phase

# Or reset to checkpoint
git reset --hard <checkpoint-commit>
```

**Checkpoints to tag:**
- `arch-cleanup-phase1-complete` (after circular deps fixed)
- `arch-cleanup-phase2-complete` (after deep imports fixed)
- `arch-cleanup-phase3a-complete` (after shared utilities)
- `arch-cleanup-phase3b-complete` (after provider split)
- `arch-cleanup-phase3c-complete` (after supporting files split)
