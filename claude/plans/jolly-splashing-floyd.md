# Agent Package Architectural Analysis & Refactoring Plan

## Executive Summary

After comprehensive analysis of `packages/agent/src`, we identified **6 critical/high-priority issues** that weren't addressed in recent refactoring. Recent commits fixed circular dependencies, module consolidation, and message format handling - but several architectural smells remain.

---

## Issues NOT YET Addressed (Prioritized)

### CRITICAL SEVERITY

#### 1. Duplicated Processing State (Race Condition Risk)
**Files:** `event-store-orchestrator.ts`, `session-context.ts`

`isProcessing` is stored in TWO places and manually synchronized:
```typescript
// event-store-orchestrator.ts:572-574
active.isProcessing = true;              // In ActiveSession
active.sessionContext.setProcessing(true);  // Also in SessionContext
```

**Risk:** Race condition where one thread checks `active.isProcessing` while another checks `sessionContext.isProcessing()`. If either update is forgotten, views diverge.

**Fix:** Single source of truth in `SessionContext`. Remove `isProcessing` from `ActiveSession`.

---

#### 2. Session State Scattered Across 5+ Objects
**Files:** `orchestrator/types.ts`, `session-context.ts`, `turn-manager.ts`, `turn-content-tracker.ts`

State is split without clear ownership:
- `ActiveSession`: agent, sessionContext, isProcessing, lastActivity, wasInterrupted, trackers
- `SessionContext`: processing (duplicate!), lastActivity (duplicate!), messageEventIds, reasoningLevel
- `TurnManager`: turn-specific content, token usage
- `TurnContentTracker`: accumulated text/thinking/toolCalls

**Fix:** Consolidate into `SessionContext` with clear access patterns. Define which object owns which state.

---

#### 3. Giant Type Files Need Splitting
**File:** `types/messages.ts` (9,781 lines)

This is the largest file in the codebase. Contains:
- User message types
- Assistant message types
- Tool result types
- Content block types
- Normalization utilities
- API format converters

**Fix:** Split into `types/messages/` directory:
- `types/messages/user.ts`
- `types/messages/assistant.ts`
- `types/messages/tool-result.ts`
- `types/messages/content.ts`
- `types/messages/normalizers.ts`
- `types/messages/index.ts` (barrel)

---

### HIGH SEVERITY

#### 4. Inconsistent Error Handling
**Files:** Throughout codebase

Multiple problems:
- Ad-hoc `throw new Error('message')` without domain-specific error classes
- Error swallowing in nested try-catch blocks
- Fire-and-forget operations that silently fail
- `event-persister.ts` silently returns when errors occur

**Example of swallowed error:**
```typescript
// event-store-orchestrator.ts:905-921
catch (error) {
  try {
    await active.sessionContext!.appendEvent('error.agent', {...});
  } catch (storeErr) {
    logger.error('Failed to store error.agent event', { storeErr });
    // storeErr is LOST - caller never knows storage failed
  }
  throw error;
}
```

**Fix:** Create error class hierarchy (`SessionError`, `PersistenceError`, `ProviderError`). Never swallow errors silently.

---

#### 5. RPC Handler Boilerplate (25 Files)
**Files:** `rpc/handlers/*.ts` (28 files)

Every handler repeats identical patterns:
```typescript
export async function handleXxx(request, context): Promise<RpcResponse> {
  if (!context.xxx) {
    return MethodRegistry.errorResponse(request.id, 'NOT_SUPPORTED', '...');
  }
  const params = request.params as XxxParams | undefined;
  if (!params?.requiredField) {
    return MethodRegistry.errorResponse(request.id, 'INVALID_PARAMS', '...');
  }
  try {
    const result = await context.xxx.doThing(params);
    return MethodRegistry.successResponse(request.id, result);
  } catch (error) {
    return MethodRegistry.errorResponse(request.id, 'XXX_ERROR', error.message);
  }
}
```

**Also:** `handleSearchContent` and `handleSearchEvents` are 100% identical code.

**Fix:** Create handler factory that generates this boilerplate. Merge duplicate search handlers.

---

#### 6. Provider Retry Logic Duplicated
**Files:** `utils/retry.ts`, `providers/base/stream-retry.ts`

~150 lines of similar exponential backoff logic:
- Same abort signal handling
- Same backoff calculation
- Same retry-after extraction
- Same attempt tracking

**Fix:** Consolidate into single `utils/retry.ts` with stream-aware variant.

---

### MEDIUM SEVERITY

#### 7. Tools Directory Needs Organization
**Directory:** `tools/` (21 flat files)

All tools in one flat directory. Large tools include:
- `subagent-tracker.ts` (697 lines)
- `ast-grep.ts` (617 lines)
- `agent-web-browser.ts` (498 lines)

**Fix:** Organize by domain:
```
tools/
├── fs/          (read, write, edit, find, grep, ls)
├── subagent/    (spawn, query, wait, tracker)
├── browser/     (open-browser, agent-web-browser)
├── system/      (bash, ast-grep)
└── ui/          (ask-user-question, todo-write, notify-app)
```

---

#### 8. Orchestrator Directory Needs Subdirectories
**Directory:** `orchestrator/` (16 flat files)

Large files at top level:
- `event-store-orchestrator.ts` (1,884 lines)
- `agent-event-handler.ts` (1,104 lines)

**Fix:** Organize by responsibility:
```
orchestrator/
├── core/        (event-store-orchestrator, session-manager)
├── events/      (agent-event-handler, turn-content-tracker, event-persister)
├── subagents/   (subagent-ops)
└── handlers/    (existing)
```

---

#### 9. Legacy Code to Remove
**Files:** Various

- `SQLiteBackend` alias in `events/sqlite/facade.ts:469` - deprecated
- `MemoryStore` adapter in `gateway/rpc/adapters/memory.adapter.ts` - returns empty
- `OAuthTokensV1`, `CodexOAuthV1` in `auth/types.ts` - deprecated type aliases

**Fix:** Remove deprecated code or add deprecation timeline.

---

#### 10. Type Safety Bypasses
**Files:** `event-store-orchestrator.ts`, providers

Multiple `as any` and `as unknown` casts:
- Line 288: `action as any`
- Line 857, 900: `as unknown as TurnResult[]`
- Line 1036: `newAuth as any`

Also: Test hooks exposed via `@ts-expect-error` in production code.

**Fix:** Fix underlying type mismatches. Use dependency injection for test hooks.

---

## What Was Already Refactored (Recent Commits)

| Commit | Change |
|--------|--------|
| 6a17287 | Remove legacy tool_result format, add Gemini 3 thoughtSignature |
| 4dd6075 | Message reconstructor outputs proper toolResult messages |
| b58ff45 | Providers handle tool_result content in user messages |
| 49ffd69 | Fix orchestrator circular dependencies |
| ebf5fdc | Fix 8 more circular dependencies |
| 53530cb | Fix circular dependencies via direct imports |
| 3a57408 | Fix circular dependency in types module |
| 2f76412 | Unify content processing constants |
| ec9935b | Extract message-reconstructor from event-store |
| 50ce596 | Fix circular import in types and utils |
| d90dab7 | Move subagents/tracker to tools/ |
| af3b311 | Move tmux/manager to session/ |
| 0e762d0 | Move features/index to settings/feature-flags |
| 5f35b19 | Standardize tests into __tests__/ directories |

---

## Recommended Refactoring Order (Safest First)

The order below minimizes regression risk - each phase is independent and testable.

### Phase A: Code Deduplication (Safest - Pure Cleanup)
**Risk: LOW** - Removing duplicate code, no behavior change

1. **Merge duplicate search handlers** (`rpc/handlers/search.handler.ts`)
   - `handleSearchContent` and `handleSearchEvents` are identical
   - Merge into single function or have one call the other

2. **Consolidate retry logic** (`utils/retry.ts` + `providers/base/stream-retry.ts`)
   - Extract shared backoff calculation
   - Keep stream-specific wrapper in providers/base/

3. **Create RPC handler factory** (optional, large scope)
   - Extract common validation/error patterns
   - Reduce 25 handler files' boilerplate

### Phase B: Directory Organization (Safe - File Moves Only)
**Risk: LOW** - Moving files, updating imports, no logic change

1. **Organize tools/ by domain**
   ```
   tools/fs/       → read, write, edit, find, grep, ls
   tools/subagent/ → spawn, query, wait, tracker
   tools/browser/  → open-browser, agent-web-browser
   tools/system/   → bash, ast-grep
   tools/ui/       → ask-user-question, todo-write, notify-app
   ```

2. **Organize orchestrator/ by responsibility**
   ```
   orchestrator/core/   → event-store-orchestrator, session-manager
   orchestrator/events/ → agent-event-handler, turn-content-tracker
   ```

### Phase C: Type System Cleanup (Safe - Structural)
**Risk: LOW-MEDIUM** - File splits and deprecation removal

1. **Split `types/messages.ts` (9,781 lines)**
   - Create `types/messages/` directory
   - Split by message type (user, assistant, tool-result, content)
   - Keep normalizers together

2. **Remove deprecated type aliases**
   - `OAuthTokensV1`, `CodexOAuthV1` in auth/types.ts
   - `SQLiteBackend` alias in events/sqlite/facade.ts
   - `MemoryStore` adapter (if unused)

3. **Fix `as any` casts** (where feasible)
   - Fix underlying type mismatches
   - Add proper generics where needed

### Phase D: Comprehensive Error & Logging System (Medium Risk)
**Risk: MEDIUM** - Surfacing previously hidden errors
**Goal: Robust, auditable error handling with structured, queryable logs**

#### D1. Error Class Hierarchy (Foundation)
Create a comprehensive error system with rich context:

```typescript
// Base error with structured metadata
class TronError extends Error {
  readonly code: string;           // Machine-readable: 'SESSION_NOT_FOUND'
  readonly category: ErrorCategory; // 'auth' | 'persistence' | 'provider' | 'tool' | 'network'
  readonly severity: ErrorSeverity; // 'fatal' | 'error' | 'warning' | 'transient'
  readonly timestamp: Date;
  readonly context: Record<string, unknown>; // Structured context for debugging
  readonly cause?: Error;          // Original error chain

  toStructuredLog(): StructuredErrorLog; // For DB persistence
}

// Domain-specific errors with required context
class SessionError extends TronError {
  readonly sessionId: string;
  readonly operation: 'create' | 'resume' | 'fork' | 'run' | 'interrupt';
}

class PersistenceError extends TronError {
  readonly table: string;
  readonly operation: 'read' | 'write' | 'delete';
  readonly query?: string;  // Sanitized query for debugging
}

class ProviderError extends TronError {
  readonly provider: 'anthropic' | 'openai' | 'google' | 'openai-codex';
  readonly model: string;
  readonly statusCode?: number;
  readonly retryable: boolean;
  readonly rateLimitInfo?: { retryAfter: number; limit: number };
}

class ToolError extends TronError {
  readonly toolName: string;
  readonly toolCallId: string;
  readonly input?: Record<string, unknown>; // Truncated for large inputs
}
```

#### D2. Structured Logging System
Enhance logging with structured, tagged, DB-persisted logs:

```typescript
interface StructuredLog {
  // Identity
  id: string;              // UUID
  timestamp: Date;

  // Context
  sessionId?: string;
  turnNumber?: number;
  toolCallId?: string;
  requestId?: string;      // For tracing across async operations

  // Classification
  level: 'debug' | 'info' | 'warn' | 'error' | 'fatal';
  category: string;        // 'provider', 'tool', 'session', 'persistence', etc.
  tags: string[];          // ['retry', 'auth', 'streaming', etc.]

  // Content
  message: string;
  data?: Record<string, unknown>;  // Structured payload

  // Error-specific (if applicable)
  error?: {
    code: string;
    message: string;
    stack?: string;
    cause?: string;        // Serialized cause chain
  };

  // Performance
  durationMs?: number;

  // Audit trail
  component: string;       // 'EventStoreOrchestrator', 'AnthropicProvider', etc.
  operation: string;       // 'runAgent', 'streamResponse', 'appendEvent'
}
```

#### D3. Log Persistence & Queryability
Ensure all logs are persisted to SQLite for investigation:

**Schema additions to `logs` table:**
```sql
-- Enhanced logs table (if not already present)
ALTER TABLE logs ADD COLUMN request_id TEXT;
ALTER TABLE logs ADD COLUMN tags TEXT;  -- JSON array
ALTER TABLE logs ADD COLUMN duration_ms INTEGER;
ALTER TABLE logs ADD COLUMN operation TEXT;

-- Indexes for common queries
CREATE INDEX idx_logs_session_level ON logs(session_id, level_num);
CREATE INDEX idx_logs_request_id ON logs(request_id);
CREATE INDEX idx_logs_tags ON logs(tags);  -- For JSON contains queries
```

**Query patterns for investigation:**
```sql
-- Find all errors in a session
SELECT * FROM logs WHERE session_id = ? AND level_num >= 50 ORDER BY timestamp;

-- Trace a request across async operations
SELECT * FROM logs WHERE request_id = ? ORDER BY timestamp;

-- Find all rate limit events
SELECT * FROM logs WHERE tags LIKE '%"rate_limit"%' ORDER BY timestamp DESC;

-- Find slow operations
SELECT * FROM logs WHERE duration_ms > 5000 ORDER BY duration_ms DESC;
```

#### D4. Error Propagation Rules
Fix swallowed errors with clear propagation:

1. **Never swallow errors silently** - Always log AND propagate
   ```typescript
   // BEFORE (bad)
   catch (storeErr) {
     logger.error('Failed to store', { storeErr });
     // Error lost!
   }

   // AFTER (good)
   catch (storeErr) {
     const wrappedError = new PersistenceError('Failed to store error event', {
       cause: storeErr,
       context: { sessionId, originalError: error.message }
     });
     logger.error(wrappedError.toStructuredLog());
     // Decide: throw wrappedError OR emit to error channel
   }
   ```

2. **Error aggregation for fire-and-forget**
   ```typescript
   class ErrorCollector {
     private errors: TronError[] = [];

     collect(error: TronError): void {
       this.errors.push(error);
       logger.error(error.toStructuredLog());
     }

     hasErrors(): boolean { return this.errors.length > 0; }
     getErrors(): TronError[] { return [...this.errors]; }
     flush(): TronError[] { /* return and clear */ }
   }
   ```

3. **Async error boundaries**
   ```typescript
   // Wrap fire-and-forget with error reporting
   function fireAndForgetWithLogging<T>(
     promise: Promise<T>,
     context: { operation: string; sessionId?: string }
   ): void {
     promise.catch(error => {
       const tronError = TronError.from(error, context);
       logger.error(tronError.toStructuredLog());
       // Optionally emit to error event bus
     });
   }
   ```

#### D5. Audit Trail for Critical Operations
Add audit logging for operations that need investigation:

```typescript
// Critical operations that MUST be logged
const AUDITED_OPERATIONS = [
  'session.create', 'session.fork', 'session.resume', 'session.end',
  'provider.switch', 'provider.auth_refresh',
  'tool.execute', 'tool.error',
  'agent.start', 'agent.interrupt', 'agent.error',
  'event.append', 'event.compact',
];

// Audit logger with guaranteed persistence
class AuditLogger {
  async log(operation: string, data: Record<string, unknown>): Promise<void> {
    const log: StructuredLog = {
      id: uuid(),
      timestamp: new Date(),
      level: 'info',
      category: 'audit',
      tags: ['audit', operation.split('.')[0]],
      message: `Audit: ${operation}`,
      data,
      component: 'AuditLogger',
      operation,
    };

    // Synchronous write - don't fire-and-forget audits
    await this.persistLog(log);
  }
}
```

#### D6. Error Recovery Patterns
Add standard recovery patterns:

```typescript
// Retry with exponential backoff and structured logging
async function withRetryAndLogging<T>(
  operation: () => Promise<T>,
  options: {
    maxRetries: number;
    operation: string;
    sessionId?: string;
  }
): Promise<T> {
  const requestId = uuid();

  for (let attempt = 1; attempt <= options.maxRetries; attempt++) {
    try {
      const start = Date.now();
      const result = await operation();

      logger.debug({
        requestId,
        operation: options.operation,
        attempt,
        durationMs: Date.now() - start,
        tags: ['retry', 'success'],
      });

      return result;
    } catch (error) {
      const tronError = TronError.from(error, {
        operation: options.operation,
        attempt,
        maxRetries: options.maxRetries,
      });

      logger.warn({
        ...tronError.toStructuredLog(),
        requestId,
        tags: ['retry', 'attempt_failed'],
      });

      if (attempt === options.maxRetries || !tronError.retryable) {
        throw tronError;
      }

      await sleep(calculateBackoff(attempt));
    }
  }
}
```

#### Files to Modify
- `utils/errors.ts` - Enhance with full error hierarchy
- `logging/index.ts` - Add structured logging
- `events/sqlite/logs.ts` - Schema updates for queryability
- `orchestrator/event-store-orchestrator.ts` - Fix error swallowing
- `orchestrator/event-persister.ts` - Add error collection
- `providers/*.ts` - Use ProviderError consistently

### Phase E: State Management (Highest Risk - Core Logic)
**Risk: HIGH** - Changing core state machine

1. **Eliminate duplicated `isProcessing`**
   - Keep only in `SessionContext`
   - Remove from `ActiveSession` interface
   - Update all call sites

2. **Consolidate session state ownership**
   - Document which object owns which state
   - Remove `lastActivity` duplication
   - Clear access patterns via methods

3. **Add atomic state transitions** (optional, complex)
   - Consider mutex for `isProcessing` check-and-set
   - Or use compare-and-swap pattern

---

## Execution Strategy

**Moderate scope approach:** Tackle related issues together within each phase, but complete one phase before starting the next.

**After each phase:**
```bash
bun run build && bun run test
```

**Commit after each sub-task** within a phase to enable easy rollback.

---

## Verification

After each phase:
```bash
bun run build && bun run test
```

Manual testing:
- New session with tools
- Fork/resume session
- Provider switching mid-session
- Concurrent session operations (race condition check)
