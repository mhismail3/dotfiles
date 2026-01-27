# EventStoreOrchestrator Refactoring Plan

## Status: COMPLETED ✓

### Completed Phases
- [x] **Phase 1: EventController** - Created `orchestrator.events` with getState, getMessages, getEvents, getAncestors, search, append, deleteMessage, flush, flushAll. All consumers updated.
- [x] **Phase 2: BrowserController** - Created `orchestrator.browser` with startStream, stopStream, getStatus. Browser adapter updated.
- [x] **Phase 3: WorktreeController** - Created `orchestrator.worktree` with getStatus, commit, merge, list, getCoordinator. Worktree adapter updated.
- [x] **Phase 4: AgentController** - Created `orchestrator.agent` with run, cancel. Agent adapter updated. SubagentOperations updated to use lazy callback.
- [x] **Phase 5: Promote existing controllers to public** - Changed all private controllers to `public readonly`. Updated all RPC adapters and integration tests to use `orchestrator.{controller}.{method}()` pattern.
- [x] **Phase 6: Final cleanup** - Verified clean orchestrator structure with ~10 public controllers and ~5 lifecycle/accessor methods. All 3366 tests pass.

## Goal

Transform the EventStoreOrchestrator from a 1223-line "god facade" with 58 public methods into a clean coordinator that:
1. Initializes and wires up domain controllers
2. Manages lifecycle (initialize/shutdown)
3. Exposes controllers directly - NO facade methods

Consumers access functionality through domain controllers, not through the orchestrator.

---

## Design Principles

1. **Single Responsibility** - Each controller owns one domain completely
2. **Direct Access** - `orchestrator.browser.startStream()` not `orchestrator.startBrowserStream()`
3. **Test-Driven** - Write tests first, then implementation
4. **No Facades** - Remove ALL thin wrapper methods from orchestrator
5. **Zero Regressions** - All 3305+ tests must pass after each phase

---

## Target Architecture

```typescript
// AFTER: Clean controller access
const orchestrator = new EventStoreOrchestrator(config);
await orchestrator.initialize();

// Domain operations via controllers
await orchestrator.sessions.create({ workingDirectory: '/project' });
await orchestrator.agent.run({ sessionId, prompt: 'Hello' });
orchestrator.context.getSnapshot(sessionId);
await orchestrator.browser.startStream(sessionId);
await orchestrator.events.append({ sessionId, type, payload });
```

### Controller Hierarchy

```
EventStoreOrchestrator
├── sessions: SessionController      # Session lifecycle
├── agent: AgentController           # Agent execution
├── context: ContextController       # Context & compaction
├── events: EventController          # Event query & mutation
├── browser: BrowserController       # Browser automation
├── worktree: WorktreeController     # Git worktree ops
├── subagent: SubagentController     # Subagent spawning
├── planMode: PlanModeController     # Plan mode state
├── todos: TodoController            # Task management
└── models: ModelController          # Model switching
```

---

## Current State Analysis

### Existing Extracted Components (to be promoted to public controllers)

| Current Name | New Public Name | Status |
|--------------|-----------------|--------|
| `SessionManager` | `sessions` | Exists, needs interface cleanup |
| `ContextOps` | `context` | Exists, needs interface cleanup |
| `SubagentOperations` | `subagent` | Exists, needs interface cleanup |
| `PlanModeController` | `planMode` | Exists, already clean |
| `TodoController` | `todos` | Exists, already clean |
| `ModelController` | `models` | Exists, already clean |
| `AgentRunner` | `agent` | Exists, needs to absorb runAgent/cancelAgent |

### New Controllers to Create

| Controller | Methods | Source |
|------------|---------|--------|
| `BrowserController` | startStream, stopStream, getStatus | Inline in orchestrator |
| `WorktreeController` | getStatus, commit, merge, list | Inline in orchestrator |
| `EventController` | getState, getMessages, getEvents, getAncestors, search, append, delete, flush | Inline in orchestrator |

---

## Implementation Phases

### Phase 1: Create EventController (Highest Value)

The EventController consolidates all event operations including the critical linearization logic.

**Step 1.1: Write tests first**

Create `orchestrator/controllers/__tests__/event-controller.test.ts`:
- Test event query operations (getState, getMessages, getEvents, getAncestors, search)
- Test event mutation with linearization (append for active sessions)
- Test event mutation without linearization (append for inactive sessions)
- Test deleteMessage with linearization
- Test flush operations

**Step 1.2: Create EventController**

```typescript
// orchestrator/controllers/event-controller.ts
interface EventControllerConfig {
  eventStore: EventStore;
  getActiveSession: (sessionId: string) => ActiveSession | undefined;
  onEventCreated?: (event: SessionEvent, sessionId: string) => void;
}

class EventController {
  // Query operations
  async getState(sessionId: string, atEventId?: string): Promise<SessionState>
  async getMessages(sessionId: string, atEventId?: string): Promise<Message[]>
  async getEvents(sessionId: string): Promise<SessionEvent[]>
  async getAncestors(eventId: string): Promise<SessionEvent[]>
  async search(query: string, options?: SearchOptions): Promise<SearchResult[]>

  // Mutation operations (with linearization for active sessions)
  async append(options: AppendEventOptions): Promise<SessionEvent>
  async deleteMessage(sessionId: string, targetEventId: string, reason?: string): Promise<SessionEvent>

  // Flush operations
  async flush(sessionId: string): Promise<void>
  async flushAll(): Promise<void>
}
```

**Step 1.3: Update orchestrator**
- Remove all event methods from orchestrator
- Add `events: EventController` property
- Update constructor to create EventController

**Step 1.4: Update all consumers**
- Find all `orchestrator.getSessionState()` → `orchestrator.events.getState()`
- Find all `orchestrator.appendEvent()` → `orchestrator.events.append()`
- etc.

**Step 1.5: Verify**
```bash
bun run build && bun run test
```

---

### Phase 2: Create BrowserController

**Step 2.1: Write tests first**

Create `orchestrator/controllers/__tests__/browser-controller.test.ts`:
- Test startStream creates session if needed
- Test startStream starts screencast
- Test stopStream handles missing session gracefully
- Test getStatus returns correct state

**Step 2.2: Create BrowserController**

```typescript
// orchestrator/controllers/browser-controller.ts
interface BrowserControllerConfig {
  browserService: BrowserService;
}

class BrowserController {
  async startStream(sessionId: string): Promise<{ success: boolean; error?: string }>
  async stopStream(sessionId: string): Promise<{ success: boolean; error?: string }>
  async getStatus(sessionId: string): Promise<{ hasBrowser: boolean; isStreaming: boolean; currentUrl?: string }>
}
```

**Step 2.3: Update orchestrator**
- Remove browser methods
- Add `browser: BrowserController` property

**Step 2.4: Update all consumers**

**Step 2.5: Verify**
```bash
bun run build && bun run test
```

---

### Phase 3: Create WorktreeController

**Step 3.1: Write tests first**

Create `orchestrator/controllers/__tests__/worktree-controller.test.ts`:
- Test getStatus returns null for session without worktree
- Test getStatus returns WorktreeInfo for session with worktree
- Test commit creates commit and returns hash
- Test merge delegates to coordinator
- Test list returns all worktrees

**Step 3.2: Create WorktreeController**

```typescript
// orchestrator/controllers/worktree-controller.ts
interface WorktreeControllerConfig {
  worktreeCoordinator: WorktreeCoordinator;
  getActiveSession: (sessionId: string) => ActiveSession | undefined;
}

class WorktreeController {
  async getStatus(sessionId: string): Promise<WorktreeInfo | null>
  async commit(sessionId: string, message: string): Promise<CommitResult>
  async merge(sessionId: string, targetBranch: string, strategy?: MergeStrategy): Promise<MergeResult>
  async list(): Promise<WorktreeInfo[]>
  getCoordinator(): WorktreeCoordinator  // For advanced use cases
}
```

**Step 3.3: Update orchestrator**
- Remove worktree methods
- Add `worktree: WorktreeController` property

**Step 3.4: Update all consumers**

**Step 3.5: Verify**
```bash
bun run build && bun run test
```

---

### Phase 4: Promote AgentRunner to AgentController

The existing AgentRunner needs to absorb `runAgent` and `cancelAgent` from orchestrator.

**Step 4.1: Write/update tests**

Update `orchestrator/__tests__/agent-runner.test.ts`:
- Test run with auto-resume for inactive session
- Test run throws if session not found
- Test run throws if already processing
- Test cancel returns false for non-active session
- Test cancel aborts agent and clears processing state

**Step 4.2: Expand AgentRunner → AgentController**

```typescript
// orchestrator/agent-controller.ts (rename from agent-runner.ts)
interface AgentControllerConfig {
  // existing config...
  getActiveSession: (sessionId: string) => ActiveSession | undefined;
  resumeSession: (sessionId: string) => Promise<SessionInfo>;
}

class AgentController {
  async run(options: AgentRunOptions): Promise<TurnResult[]>
  cancel(sessionId: string): boolean
}
```

**Step 4.3: Update orchestrator**
- Remove runAgent/cancelAgent
- Rename agentRunner → agent
- Add `agent: AgentController` property

**Step 4.4: Update all consumers**

**Step 4.5: Verify**
```bash
bun run build && bun run test
```

---

### Phase 5: Promote Existing Controllers to Public Interface

Rename and expose existing internal controllers:

| Internal | Public Property | Changes Needed |
|----------|-----------------|----------------|
| `sessionManager` | `sessions` | Rename property |
| `contextOps` | `context` | Rename property |
| `subagentOps` | `subagent` | Rename property |
| `planModeController` | `planMode` | Already clean |
| `todoController` | `todos` | Already clean |
| `modelController` | `models` | Already clean |

**Step 5.1: Update orchestrator**
- Rename private properties to public
- Remove ALL remaining facade methods
- Keep only: initialize, shutdown, getEventStore, getHealth, getActiveSession

**Step 5.2: Update all consumers**
- `orchestrator.createSession()` → `orchestrator.sessions.create()`
- `orchestrator.switchModel()` → `orchestrator.models.switch()`
- etc.

**Step 5.3: Verify**
```bash
bun run build && bun run test
```

---

### Phase 6: Final Cleanup

**Step 6.1: Verify final orchestrator structure**

The orchestrator should only have:
```typescript
class EventStoreOrchestrator extends EventEmitter {
  // Public controllers
  readonly sessions: SessionController;
  readonly agent: AgentController;
  readonly context: ContextController;
  readonly events: EventController;
  readonly browser: BrowserController;
  readonly worktree: WorktreeController;
  readonly subagent: SubagentController;
  readonly planMode: PlanModeController;
  readonly todos: TodoController;
  readonly models: ModelController;

  // Lifecycle only
  constructor(config: EventStoreOrchestratorConfig)
  async initialize(): Promise<void>
  async shutdown(): Promise<void>

  // Core accessors
  getEventStore(): EventStore
  getActiveSession(sessionId: string): ActiveSession | undefined
  getHealth(): HealthStatus
}
```

**Step 6.2: Update exports**

```typescript
// orchestrator/index.ts
export { EventStoreOrchestrator } from './persistence/event-store-orchestrator.js';

// Export all controllers for direct instantiation if needed
export * from './controllers/index.js';
```

**Step 6.3: Final verification**
```bash
bun run build && bun run test
```

---

## Files to Create

| File | Purpose |
|------|---------|
| `controllers/event-controller.ts` | Event query and mutation |
| `controllers/browser-controller.ts` | Browser streaming |
| `controllers/worktree-controller.ts` | Git worktree operations |
| `controllers/agent-controller.ts` | Agent execution (renamed from agent-runner.ts) |
| `controllers/__tests__/event-controller.test.ts` | Tests |
| `controllers/__tests__/browser-controller.test.ts` | Tests |
| `controllers/__tests__/worktree-controller.test.ts` | Tests |

## Files to Modify

| File | Change |
|------|--------|
| `persistence/event-store-orchestrator.ts` | Remove 50+ methods, expose controllers |
| `controllers/index.ts` | Export new controllers |
| `agent-runner.ts` | Rename to agent-controller.ts, expand interface |
| All consumers | Update to use `orchestrator.{controller}.{method}()` pattern |

---

## Consumer Migration Examples

### Before → After

```typescript
// Session operations
orchestrator.createSession(opts)        → orchestrator.sessions.create(opts)
orchestrator.resumeSession(id)          → orchestrator.sessions.resume(id)
orchestrator.endSession(id)             → orchestrator.sessions.end(id)
orchestrator.getSession(id)             → orchestrator.sessions.get(id)
orchestrator.listSessions(opts)         → orchestrator.sessions.list(opts)
orchestrator.forkSession(id, eventId)   → orchestrator.sessions.fork(id, eventId)

// Agent operations
orchestrator.runAgent(opts)             → orchestrator.agent.run(opts)
orchestrator.cancelAgent(id)            → orchestrator.agent.cancel(id)

// Context operations
orchestrator.getContextSnapshot(id)     → orchestrator.context.getSnapshot(id)
orchestrator.shouldCompact(id)          → orchestrator.context.shouldCompact(id)
orchestrator.confirmCompaction(id)      → orchestrator.context.confirmCompaction(id)
orchestrator.clearContext(id)           → orchestrator.context.clear(id)

// Event operations
orchestrator.getSessionState(id)        → orchestrator.events.getState(id)
orchestrator.getSessionMessages(id)     → orchestrator.events.getMessages(id)
orchestrator.appendEvent(opts)          → orchestrator.events.append(opts)
orchestrator.deleteMessage(id, eid)     → orchestrator.events.deleteMessage(id, eid)
orchestrator.searchEvents(q, opts)      → orchestrator.events.search(q, opts)

// Browser operations
orchestrator.startBrowserStream(id)     → orchestrator.browser.startStream(id)
orchestrator.stopBrowserStream(id)      → orchestrator.browser.stopStream(id)
orchestrator.getBrowserStatus(id)       → orchestrator.browser.getStatus(id)

// Worktree operations
orchestrator.getWorktreeStatus(id)      → orchestrator.worktree.getStatus(id)
orchestrator.commitWorktree(id, msg)    → orchestrator.worktree.commit(id, msg)
orchestrator.mergeWorktree(id, br, st)  → orchestrator.worktree.merge(id, br, st)
orchestrator.listWorktrees()            → orchestrator.worktree.list()

// Model operations
orchestrator.switchModel(id, model)     → orchestrator.models.switch(id, model)

// Plan mode operations
orchestrator.isInPlanMode(id)           → orchestrator.planMode.isActive(id)
orchestrator.enterPlanMode(id, opts)    → orchestrator.planMode.enter(id, opts)
orchestrator.exitPlanMode(id, opts)     → orchestrator.planMode.exit(id, opts)

// Todo operations
orchestrator.getTodos(id)               → orchestrator.todos.get(id)
orchestrator.getTodoSummary(id)         → orchestrator.todos.getSummary(id)
orchestrator.getBacklog(wsId)           → orchestrator.todos.getBacklog(wsId)

// Subagent operations
orchestrator.spawnSubsession(...)       → orchestrator.subagent.spawnSession(...)
orchestrator.spawnTmuxAgent(...)        → orchestrator.subagent.spawnTmux(...)
orchestrator.querySubagent(...)         → orchestrator.subagent.query(...)
orchestrator.waitForSubagents(...)      → orchestrator.subagent.wait(...)
```

---

## Verification Strategy

### After Each Phase
```bash
# Must pass before proceeding
bun run build && bun run test
```

### Find All Consumers
```bash
# Find all direct orchestrator method calls that need migration
grep -rn "orchestrator\.[a-z]*(" packages/agent/src --include="*.ts" | grep -v "orchestrator\.\(sessions\|agent\|context\|events\|browser\|worktree\|subagent\|planMode\|todos\|models\)\."
```

### Verify No Facade Methods Remain
```bash
# After final phase, orchestrator should have minimal public methods
grep -E "^\s+(async\s+)?[a-z][A-Za-z]+\(" packages/agent/src/orchestrator/persistence/event-store-orchestrator.ts | wc -l
# Target: ~5 methods (initialize, shutdown, getEventStore, getActiveSession, getHealth)
```

---

## Success Criteria

- [x] EventController created with tests, all tests pass
- [x] BrowserController created with tests, all tests pass
- [x] WorktreeController created with tests, all tests pass
- [x] AgentController expanded with tests, all tests pass
- [x] All internal controllers promoted to public, all tests pass
- [x] Final orchestrator has ~6 methods (lifecycle + accessors only)
- [x] All 3366 tests pass
- [x] Zero facade methods remain
- [x] Clean `orchestrator.{controller}.{method}()` API throughout codebase

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Missing consumer updates | Use grep to find ALL usages before each phase |
| Linearization bugs | EventController tests specifically cover linearization |
| Test failures | TDD - write tests first, run after each change |
| Circular dependencies | Controllers receive callbacks, not orchestrator reference |

---

## Estimated Outcome

### Before
```
event-store-orchestrator.ts: 1223 lines, 58 public methods
```

### After
```
event-store-orchestrator.ts: ~200-300 lines, 5 public methods
event-controller.ts: ~200 lines
browser-controller.ts: ~80 lines
worktree-controller.ts: ~100 lines
agent-controller.ts: ~150 lines (expanded from agent-runner)
```

**Net result:** Same total lines, but clean separation of concerns with testable, focused controllers.
