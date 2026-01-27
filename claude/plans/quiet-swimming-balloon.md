# Sub-Agent Spawning Tools Implementation Plan

## Overview

Implement two sub-agent spawning tools for Tron:
1. **SpawnSubsessionTool** - In-process sub-agents using EventStoreOrchestrator
2. **SpawnTmuxAgentTool** - Out-of-process sub-agents in tmux sessions

Both log to the centralized SQLite database and can be monitored via **QuerySubagentTool**.

---

## Phase 1: Schema & Types

### 1.1 Add Event Types
**File:** `packages/core/src/events/types.ts`

Add to `EventType` union:
```typescript
| 'subagent.spawned'
| 'subagent.status_update'
| 'subagent.completed'
| 'subagent.failed'
```

Add interfaces:
- `SubagentSpawnedEvent` - sessionId, spawnType, task, model, tools, skills, tmuxSessionName
- `SubagentCompletedEvent` - resultSummary, totalTurns, totalTokenUsage, duration
- `SubagentFailedEvent` - error, recoverable, partialResult

### 1.2 Database Migration
**New file:** `packages/core/src/events/sqlite/migrations/002_subagent_tracking.sql`

```sql
ALTER TABLE sessions ADD COLUMN spawning_session_id TEXT REFERENCES sessions(id);
ALTER TABLE sessions ADD COLUMN spawn_type TEXT CHECK(spawn_type IN ('subsession', 'tmux', 'fork', NULL));
ALTER TABLE sessions ADD COLUMN spawn_task TEXT;

CREATE INDEX idx_sessions_spawning ON sessions(spawning_session_id, ended_at);
```

### 1.3 Update Session Types
**File:** `packages/core/src/events/sqlite/repositories/session.repo.ts`

Add to `CreateSessionOptions`: `spawningSessionId`, `spawnType`, `spawnTask`

---

## Phase 2: SubAgentTracker

**New file:** `packages/core/src/subagents/subagent-tracker.ts`

Mirrors `SkillTracker` pattern:
- `spawn(sessionId, spawnType, task, model, tmuxSessionName?)`
- `updateStatus(sessionId, status)`
- `complete(sessionId, resultSummary, totalTurns, totalCost)`
- `fail(sessionId, error)`
- `getActive()`, `getAll()`, `get(sessionId)`
- `static fromEvents(events)` - reconstruct from event history

Add to `ActiveSession` interface in orchestrator types.

---

## Phase 3: SpawnSubsessionTool (In-Process)

**New file:** `packages/core/src/tools/spawn-subsession.ts`

### Parameters
```typescript
{
  task: string;           // Required: what the sub-agent should do
  model?: string;         // Optional: override model
  tools?: string[];       // Optional: specific tools to enable
  skills?: string[];      // Optional: skills to load
  workingDirectory?: string;
  maxTurns?: number;      // Default 50
}
```

### Behavior
1. Creates child session via `orchestrator.createSession()` with `spawningSessionId`
2. Emits `subagent.spawned` event in parent session
3. Tracks in parent's `SubAgentTracker`
4. Runs agent asynchronously (doesn't block parent)
5. On completion: emits `subagent.completed`, fires `SubagentStop` hook
6. On failure: emits `subagent.failed`, fires `SubagentStop` hook

### Tool Result
Returns session ID and instructions for monitoring:
```
Sub-agent spawned successfully.
**Session ID**: sess_abc123
**Type**: subsession
**Task**: <task>

You are responsible for monitoring this sub-agent. Use QuerySubagent to check status.
```

---

## Phase 4: SpawnTmuxAgentTool (Out-of-Process)

**New file:** `packages/core/src/tools/spawn-tmux-agent.ts`

### Parameters
```typescript
{
  task: string;
  model?: string;
  tools?: string[];
  skills?: string[];
  workingDirectory?: string;
  sessionName?: string;   // Custom tmux session name
  maxTurns?: number;      // Default 100
}
```

### Behavior
1. Generates unique tmux session name (or uses provided)
2. Spawns via `tmux new-session -d -s <name> "tron --parent-session-id=... --spawn-task=..."`
3. Pre-emits `subagent.spawned` event in parent
4. Child process:
   - Connects to shared SQLite database
   - Creates session with `spawningSessionId`, `spawnType='tmux'`
   - Runs task
   - Emits completion/failure events in parent session

### CLI Changes
**File:** `packages/tui/src/cli.ts`

Add flags:
- `--parent-session-id` - Parent that spawned this
- `--spawn-task` - Initial task/prompt
- `--db-path` - Shared database path

When these flags are present, run in "spawned agent" mode.

---

## Phase 5: QuerySubagentTool

**New file:** `packages/core/src/tools/query-subagent.ts`

### Parameters
```typescript
{
  sessionId: string;
  queryType: 'status' | 'events' | 'logs' | 'output';
  limit?: number;
}
```

### Query Types
- **status**: Running/completed/failed, turn count, token usage, task
- **events**: Recent events from sub-agent session
- **logs**: Log entries from logs table filtered by session
- **output**: Final assistant response (only when completed)

---

## Phase 6: Orchestrator Integration

**File:** `packages/server/src/event-store-orchestrator.ts`

### New Methods
```typescript
async spawnSubsession(parentSessionId, params): Promise<{sessionId, success, error?}>
async spawnTmuxAgent(parentSessionId, params): Promise<{sessionId, tmuxSessionName, success, error?}>
async querySubagent(sessionId, queryType, limit?): Promise<{success, data?, error?}>
private runSubagentAsync(sessionId, parentSessionId, task, maxTurns?)
```

### Tool Registration
In `createAgentForSession`, add:
```typescript
new SpawnSubsessionTool({ workingDirectory, sessionId, model, onSpawn: this.spawnSubsession })
new SpawnTmuxAgentTool({ workingDirectory, sessionId, model, dbPath, onSpawn: this.spawnTmuxAgent })
new QuerySubagentTool({ onQuery: this.querySubagent })
```

### SubagentStop Hook
Fire when sub-agent completes/fails:
```typescript
this.emit('hook', {
  type: 'SubagentStop',
  sessionId: parentSessionId,
  data: { subagentId, stopReason, result }
});
```

---

## Files to Create/Modify

### New Files
1. `packages/core/src/subagents/subagent-tracker.ts`
2. `packages/core/src/subagents/index.ts`
3. `packages/core/src/tools/spawn-subsession.ts`
4. `packages/core/src/tools/spawn-tmux-agent.ts`
5. `packages/core/src/tools/query-subagent.ts`
6. `packages/core/src/events/sqlite/migrations/002_subagent_tracking.sql`

### Modified Files
1. `packages/core/src/events/types.ts` - Event types
2. `packages/core/src/events/sqlite/repositories/session.repo.ts` - Session columns
3. `packages/server/src/event-store-orchestrator.ts` - Spawn methods, tool registration
4. `packages/server/src/orchestrator/types.ts` - ActiveSession.subagentTracker
5. `packages/tui/src/cli.ts` - CLI flags for spawned mode
6. `packages/core/src/tools/index.ts` - Export new tools
7. `packages/core/src/index.ts` - Export subagents module

---

## Verification

1. **Unit Tests**
   - SubAgentTracker state management and reconstruction
   - Event serialization/deserialization
   - Query methods return correct data

2. **Integration Tests**
   - Spawn subsession, verify events logged, query status
   - Spawn tmux agent, verify process runs, events logged
   - SubagentStop hook fires on completion

3. **Manual Testing**
   - Start Tron, spawn a sub-agent, query its progress
   - Verify tmux session created and can be attached
   - Verify all data in SQLite database
