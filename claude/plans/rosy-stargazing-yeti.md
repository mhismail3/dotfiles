# Plan: Event Orchestration System Incremental Refactor

## Overview

Incremental extraction refactor of the event orchestration system (~2900 lines in `event-store-orchestrator.ts`) into a modular, robust architecture. This is a **first-principles rework** prioritizing:

- **Robustness**: Data integrity, error recovery, concurrent sessions, deterministic reconstruction
- **Separation of concerns**: Orchestrator coordinates, TronAgent handles LLM calls, ContextManager owns reconstruction
- **Incremental safety**: Extract one component at a time, tests pass at each step
- **API standardization**: Consistent naming across all components

## Strategic Approach: Incremental Extraction

Unlike a ground-up rewrite, we will:

1. **Extract one module at a time** from the existing orchestrator
2. **Write tests first** for each extracted module (TDD)
3. **Verify build + tests pass** after each extraction
4. **Commit liberally** to create rollback points
5. **Keep existing orchestrator working** until final swap

This prevents the API mismatch disasters that derailed the previous attempt.

## Requirements Summary

| Requirement | Decision |
|-------------|----------|
| Robustness | Full: data integrity + error recovery + concurrent sessions |
| Extensibility | Minimal: strategies are internal, not public API |
| Testing | TDD: unit + integration tests at each step |
| iOS compatibility | Sync incrementally, update after each phase |
| Edge cases | All combinations must work |
| Approach | Incremental extraction with checkpoint commits |

## Current State Analysis

### Existing Orchestrator (`event-store-orchestrator.ts` ~2900 lines)

**Key responsibilities (to be extracted):**
1. Session lifecycle (create, resume, fork, destroy)
2. Event persistence with linearization
3. Turn management (start, content, end)
4. Agent coordination (run, interrupt)
5. Special case handling (AskUserQuestion, compaction, plan mode, interrupts)
6. Context reconstruction for API calls
7. Skill/rules tracking
8. Worktree coordination
9. Browser service coordination

**Already modularized:**
- `orchestrator/event-linearizer.ts` - Promise-chain event linearization
- `orchestrator/turn-content-tracker.ts` - Turn content accumulation
- `orchestrator/types.ts` - Type definitions
- `orchestrator/worktree-ops.ts` - Worktree operations

**Core module dependencies:**
- `@tron/core` → `TronAgent`, `EventStore`, `ContextManager`, `WorktreeCoordinator`
- `./browser/` → `BrowserService`

### API Audit (Critical for Success)

The previous attempt failed due to API assumptions. Here are the **actual** APIs:

#### TronAgent (`@tron/core`)
```typescript
class TronAgent {
  // Lifecycle
  abort(): void;                           // NOT cancel()
  async run(content: string | UserContent[]): Promise<RunResult>;

  // Context (delegates to ContextManager)
  clearMessages(): void;                   // NOT clearContext()
  setMessages(messages: Message[]): void;
  getMessages(): Message[];

  // Configuration
  setReasoningLevel(level): void;
  setSkillContext(context: string | undefined): void;
  setRulesContent(rules: string | undefined): void;
  setSummarizer(summarizer: Summarizer): void;

  // State
  getModel(): string;
  getProviderType(): ProviderType;
  isRunning: boolean;  // private, check via abortController
}
```

#### EventStore (`@tron/core`)
```typescript
class EventStore {
  // Session management
  async createSession(options): Promise<CreateSessionResult>;
  async getSession(sessionId): Promise<SessionRow | null>;
  async listSessions(options): Promise<SessionRow[]>;

  // Event operations
  async append(options: AppendEventOptions): Promise<SessionEvent>;
  async getAncestors(eventId): Promise<SessionEvent[]>;

  // Reconstruction (KEY for context rebuild)
  async getMessagesAt(eventId): Promise<Message[]>;        // NOT getMessages()
  async getMessagesAtHead(sessionId): Promise<Message[]>;
  async getStateAt(eventId): Promise<SessionState>;
  async getStateAtHead(sessionId): Promise<SessionState>;

  // Fork
  async fork(eventId, options): Promise<ForkResult>;
}
```

#### WorktreeCoordinator (`@tron/core`)
```typescript
class WorktreeCoordinator {
  async acquire(sessionId: SessionId, workingDir: string, options?): Promise<WorkingDirectory>;
  async release(sessionId: SessionId, options?): Promise<void>;
  // NOT acquireWorkingDirectory() / releaseWorkingDirectory()
}
```

#### BrowserService (`./browser/`)
```typescript
class BrowserService {
  async cleanup(): Promise<void>;          // NOT shutdown()
  async getPage(sessionId): Promise<Page>;
}
```

#### ContextManager (`@tron/core`)
```typescript
class ContextManager {
  // Token tracking
  getCurrentTokens(): number;
  getContextLimit(): number;
  shouldCompact(): boolean;

  // Compaction
  async previewCompaction(opts): Promise<CompactionPreview>;
  async executeCompaction(opts): Promise<CompactionResult>;

  // Snapshot
  getSnapshot(): ContextSnapshot;
  getDetailedSnapshot(): DetailedContextSnapshot;
  canAcceptTurn(opts): PreTurnValidation;
}
```

## Architecture Design

### Core Principle: SQLite as Single Source of Truth

**The SQLite database IS the truth.** Everything deterministic must be persisted there in linearized fashion so we can reconstruct any state at any point in time.

#### What Gets Persisted (Linearized)
| Category | Events | Purpose |
|----------|--------|---------|
| **Messages** | `message.user`, `message.assistant`, `message.system` | Conversation history |
| **Tools** | `tool.call`, `tool.result` | Tool execution records |
| **Turns** | `stream.turn_start`, `stream.turn_end` | Turn boundaries with token usage |
| **Context** | `compact.boundary`, `compact.summary`, `context.cleared` | Context management markers |
| **Config** | `config.model_switch`, `config.reasoning_level` | Configuration changes |
| **Skills** | `skill.added`, `skill.removed` | Skill context tracking |
| **Rules** | `rules.loaded` | Rules files loaded |
| **Plan Mode** | `plan.mode_entered`, `plan.mode_exited` | Plan mode state |
| **Interrupts** | `notification.interrupted` | User abort markers |
| **Errors** | `error.agent`, `error.tool`, `error.provider` | Error records |

#### What Does NOT Get Persisted
| Item | Reason |
|------|--------|
| Text deltas (`agent.text_delta`) | High frequency, consolidated into `message.assistant` |
| Tool progress (`agent.tool_start/end`) | Ephemeral UI updates, tool.call/result is the record |
| Accumulated in-memory content | Derived state, reconstructable from events |

#### Linearization Invariant

**Every event must chain to the previous one via `parentId`:**

```
session.start (root, parentId: null)
    ↓
message.user (parentId: session.start.id)
    ↓
stream.turn_start (parentId: message.user.id)
    ↓
tool.call (parentId: stream.turn_start.id)
    ↓
tool.result (parentId: tool.call.id)
    ↓
message.assistant (parentId: tool.result.id)
    ↓
stream.turn_end (parentId: message.assistant.id)
    ↓
... and so on
```

This linear chain enables:
- **Deterministic reconstruction**: Walk ancestors from head → root to rebuild state
- **Forking**: Create new session with parentId pointing to any event in the chain
- **Audit trail**: Every change is traceable and immutable

### Target Module Structure

```
packages/server/src/orchestrator/
├── index.ts                      # Public exports
├── orchestrator.ts               # Main orchestrator (~500 lines max)
├── types.ts                      # [EXISTS] Extend with new types
├── event-linearizer.ts           # [EXISTS] Keep as-is
├── turn-content-tracker.ts       # [EXISTS] Keep as-is
├── worktree-ops.ts               # [EXISTS] Keep as-is
│
├── event-persister.ts            # [EXTRACT] Linearized event persistence
├── turn-manager.ts               # [EXTRACT] Turn lifecycle
├── session-state.ts              # [EXTRACT] Session state reconstruction
│
└── handlers/                     # [EXTRACT] Special case handlers
    ├── index.ts                  # Handler registration and dispatch
    ├── ask-user-question.ts      # Stop turn, await user
    ├── compaction.ts             # Context compaction
    ├── context-clear.ts          # Clear all messages
    ├── plan-mode.ts              # Block destructive tools
    ├── interrupt.ts              # Handle user abort
    └── skill-rules.ts            # Track skills and rules
```

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     EventStoreOrchestrator                       │
│                    (thin coordination layer)                     │
│                                                                  │
│  Responsibilities:                                               │
│  - Session lifecycle (create/resume/fork/destroy)               │
│  - Coordinate components for each operation                     │
│  - Emit WebSocket events                                        │
│  - Delegate to specialized handlers                              │
└───────────────────────────┬─────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        ▼                   ▼                   ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│  TurnManager  │   │ EventPersister│   │   Handlers    │
│ (lifecycle)   │   │ (linearized)  │   │ (special cases)│
├───────────────┤   ├───────────────┤   ├───────────────┤
│ startTurn()   │   │ append()      │   │ AskUserQuestion│
│ addContent()  │   │ appendAsync() │   │ Compaction     │
│ endTurn()     │   │ flush()       │   │ ContextClear   │
│ interrupt()   │   │ getPendingHead│   │ PlanMode       │
└───────────────┘   └───────────────┘   │ Interrupt      │
        │                   │           │ SkillRules     │
        │                   │           └───────────────┘
        │                   │
        │                   ▼
        │           ┌───────────────────────────────────────┐
        │           │           SQLite Database              │
        │           │  (events, sessions, workspaces, logs)  │
        │           │                                        │
        │           │  SINGLE SOURCE OF TRUTH                │
        │           │  Everything reconstructable from here  │
        │           └───────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────────────────────────────┐
│                        TronAgent                               │
│              (LLM communication ONLY)                          │
├───────────────────────────────────────────────────────────────┤
│ Responsibilities:                                              │
│ - Make LLM API calls                                          │
│ - Execute tools                                                │
│ - Stream events                                                │
│ - Handle abort                                                 │
│                                                                │
│ NOT responsible for:                                           │
│ - Persisting events (orchestrator does this)                  │
│ - Context reconstruction (EventStore.getMessagesAt does this) │
│ - Session state (reconstructed from events)                   │
└───────────────────────────────────────────────────────────────┘
```

### Separation of Concerns

| Component | Responsibility | Does NOT |
|-----------|---------------|----------|
| **Orchestrator** | Coordinates operations, emits WS events | Make LLM calls, persist directly |
| **TurnManager** | Turn lifecycle, content accumulation | Persist events, make LLM calls |
| **EventPersister** | Linearized event persistence | Know about turn content |
| **Handlers** | Special case logic | Coordinate other handlers |
| **TronAgent** | LLM calls, tool execution | Persist events, manage sessions |
| **EventStore** | Event storage, reconstruction | Know about sessions' runtime state |

## Special Cases (Handlers)

### 1. AskUserQuestion Handler
**Trigger**: `tool_execution_end` where tool is `AskUserQuestion`
**Behavior**:
- Stop current turn (don't continue agent loop)
- Persist tool.result event
- Do NOT create message.user from tool result (user will provide input)
- Emit `agent.awaiting_input` WebSocket event

**Edge cases**:
- Interrupt during AskUserQuestion → persist partial, mark interrupted
- Resume after AskUserQuestion → user's next message is the response

### 2. Compaction Handler
**Trigger**: `confirmCompaction()` RPC call
**Behavior**:
- Persist `compact.boundary` event
- Call `contextManager.executeCompaction()`
- Persist `compact.summary` event with summary
- Clear skill tracker (skills must be re-added post-compaction)
- Update TronAgent messages via `setMessages()`

**Edge cases**:
- Compaction during active run → must wait for turn end
- Interrupt during compaction → rollback, don't persist boundary
- Concurrent compaction requests → serialize via persister

### 3. ContextClear Handler
**Trigger**: `clearContext()` RPC call
**Behavior**:
- Persist `context.cleared` event
- Call `agent.clearMessages()`
- Clear skill tracker
- Reset turn number

**Edge cases**:
- Clear during active run → abort first, then clear
- Clear with pending tool results → discard them

### 4. PlanMode Handler
**Trigger**:
- `plan.mode_entered` event (from EnterPlanMode tool)
- `plan.mode_exited` event (from ExitPlanMode tool)
**Behavior**:
- Track blocked tools list
- On blocked tool call → return error result, don't execute
- Persist mode events for reconstruction

**Edge cases**:
- Interrupt while in plan mode → preserve mode state
- Fork from plan mode session → inherit mode state

### 5. Interrupt Handler
**Trigger**: `abort()` called during agent run
**Behavior**:
- Abort the agent (`agent.abort()`)
- Persist partial content as `message.assistant` (with stop_reason: 'interrupted')
- If tool was executing → persist `tool.result` with error
- Persist `notification.interrupted` event
- Emit `agent.interrupted` WebSocket event

**Edge cases**:
- Interrupt during text streaming → save accumulated text
- Interrupt during tool execution → mark tool as interrupted
- Multiple rapid interrupts → only process first

### 6. SkillRules Handler
**Trigger**:
- `skill.added` / `skill.removed` events
- `rules.loaded` event
**Behavior**:
- Update skill tracker
- Build skill context XML for injection
- Update rules content on agent

**Edge cases**:
- Add skill during run → inject in next turn
- Remove skill → update context for next turn
- Compaction → skills cleared, must re-add

## Concurrent Sessions

**Critical requirement**: Multiple sessions can run concurrently.

### Per-Session Isolation
Each active session has its own:
- `EventPersister` instance (with its own promise chain)
- `TurnManager` instance (with its own content tracker)
- `TronAgent` instance (with its own ContextManager)
- `pendingHeadEventId` (tracked per-session)

### Shared Resources
- `EventStore` - thread-safe SQLite operations
- `WorktreeCoordinator` - manages worktree locks
- `BrowserService` - manages browser instances

### Linearization per Session
Each session's events form their own linear chain:
```
Session A: A1 → A2 → A3 → A4
Session B: B1 → B2 → B3
```
No cross-session dependencies. Each session's `pendingHeadEventId` is independent.

## Implementation Phases

### Phase 0: Setup and API Audit
**Goal**: Verify all API assumptions, create test infrastructure

**Tasks**:
1. Create test file structure under `packages/server/test/orchestrator/`
2. Write integration test that verifies current orchestrator behavior
3. Document any API surprises
4. Commit: "Phase 0: Test infrastructure and API audit"

### Phase 1: Extract EventPersister
**Goal**: Extract linearized event persistence into dedicated module

**Source**: Event append logic from `event-store-orchestrator.ts`
- `appendEventLinearized` calls
- `pendingHeadEventId` tracking
- `appendPromiseChain` management

**New file**: `orchestrator/event-persister.ts`
```typescript
interface EventPersister {
  append(type: EventType, payload: object): void;  // Fire-and-forget
  appendAsync(type: EventType, payload: object): Promise<TronSessionEvent>;  // Wait for result
  flush(): Promise<void>;  // Wait for all pending
  getPendingHeadEventId(): EventId;
  hasError(): boolean;
}
```

**Tests**:
- Linearization preserves order
- Concurrent appends serialize correctly
- Error handling stops chain
- Flush waits for all pending

**Commit**: "Phase 1: Extract EventPersister module"

### Phase 2: Extract TurnManager
**Goal**: Extract turn lifecycle management

**Source**: Turn tracking from `event-store-orchestrator.ts`
- `currentTurn` tracking
- `TurnContentTracker` wrapping
- Turn start/end logic

**New file**: `orchestrator/turn-manager.ts`
```typescript
interface TurnManager {
  startTurn(turn: number): void;
  addTextDelta(text: string): void;
  startToolCall(id: string, name: string, args: object): void;
  endToolCall(id: string, result: string, isError: boolean): void;
  endTurn(tokenUsage: TokenUsage): EndTurnResult;
  buildInterruptedContent(): ContentBlock[];
  getAccumulatedContent(): AccumulatedContent;
  getCurrentTurn(): number;
}
```

**Tests**:
- Turn number increments
- Content accumulates correctly
- Interrupted content preserved
- Multiple tool calls tracked

**Commit**: "Phase 2: Extract TurnManager module"

### Phase 3: Extract Handlers
**Goal**: Extract special case handling into dedicated handlers

**New directory**: `orchestrator/handlers/`

**Extract in order** (simplest first):
1. `plan-mode.ts` - Simplest, just tracks state
2. `skill-rules.ts` - Track skills/rules
3. `context-clear.ts` - Clear messages
4. `ask-user-question.ts` - Stop turn for input
5. `interrupt.ts` - Handle abort
6. `compaction.ts` - Most complex, depends on others

**Interface**:
```typescript
interface Handler {
  readonly name: string;
  canHandle(event: TronEvent, session: SessionState): boolean;
  handle(event: TronEvent, context: HandlerContext): Promise<HandlerResult>;
}

interface HandlerResult {
  handled: boolean;
  stopTurn: boolean;
  events?: EventToAppend[];
  error?: Error;
}
```

**Tests per handler**:
- Normal flow
- Edge cases specific to handler
- Interaction with other handlers

**Commits**: One per handler extraction

### Phase 4: Extract Session State Reconstruction
**Goal**: Centralize session state reconstruction

**Source**: State reconstruction scattered in orchestrator

**New file**: `orchestrator/session-state.ts`
```typescript
interface SessionStateReconstructor {
  reconstruct(events: TronSessionEvent[]): ReconstructedState;
}

interface ReconstructedState {
  currentTurn: number;
  skills: SkillInfo[];
  rulesFiles: RulesFileInfo[];
  planMode: PlanModeState;
  wasInterrupted: boolean;
  reasoningLevel?: string;
  pendingToolResults: ToolResult[];
}
```

**Tests**:
- Reconstruct after agentic loop
- Reconstruct after compaction
- Reconstruct after interrupt
- Reconstruct after fork

**Commit**: "Phase 4: Extract session state reconstruction"

### Phase 5: Create New Orchestrator
**Goal**: Create new lean orchestrator using extracted modules

**New file**: `orchestrator/orchestrator.ts` (~500 lines max)

**Structure**:
```typescript
class EventStoreOrchestrator {
  // Dependencies
  private eventStore: EventStore;
  private worktreeCoordinator: WorktreeCoordinator;
  private browserService: BrowserService;

  // Per-session state (Map<SessionId, SessionContext>)
  private sessions: Map<SessionId, SessionContext>;

  // Session lifecycle
  async createSession(options): Promise<SessionInfo>;
  async resumeSession(sessionId): Promise<SessionInfo>;
  async forkSession(eventId, options): Promise<ForkResult>;
  async destroySession(sessionId): Promise<void>;

  // Agent operations
  async runAgent(sessionId, prompt, options): Promise<void>;
  async interruptSession(sessionId): Promise<void>;

  // Context operations
  async getContext(sessionId): Promise<ContextSnapshot>;
  async previewCompaction(sessionId): Promise<CompactionPreview>;
  async confirmCompaction(sessionId): Promise<CompactionResult>;
  async clearContext(sessionId): Promise<void>;

  // Skill operations
  async addSkill(sessionId, skill): Promise<void>;
  async removeSkill(sessionId, skillName): Promise<void>;
}

interface SessionContext {
  sessionId: SessionId;
  agent: TronAgent;
  persister: EventPersister;
  turnManager: TurnManager;
  skillTracker: SkillTracker;
  rulesTracker: RulesTracker;
  planMode: PlanModeState;
  workingDir?: WorkingDirectory;
}
```

**Tests**:
- Full agent run with tools
- Interrupt and resume
- Compaction flow
- Fork and continue
- Concurrent sessions

**Commit**: "Phase 5: Create new lean orchestrator"

### Phase 6: Migration
**Goal**: Replace old orchestrator with new

**Tasks**:
1. Update `index.ts` exports
2. Update RPC handlers to use new interface
3. Run all existing tests
4. Run manual iOS app test
5. Delete old `event-store-orchestrator.ts`

**Commit**: "Phase 6: Complete migration to modular orchestrator"

### Phase 7: iOS App Synchronization
**Goal**: Ensure iOS app is in full parity

**Review these iOS files**:
- `UnifiedEventTransformer.swift` - Event to message transformation
- `EventTypeRegistry.swift` - Event type definitions
- `PersistedEventType` enum - Must match server
- `MessagePayloads.swift` / `ToolPayloads.swift` - Payload parsing
- `RPCClient.swift` - RPC method calls

**Verification**:
- iOS can parse all server events
- Session resume shows complete history
- Interrupted sessions display properly
- Compaction boundaries respected
- Fork works correctly

**Commit**: "Phase 7: iOS app synchronization"

### Phase 8: Cleanup
**Goal**: Remove legacy code, final polish

**Tasks**:
1. Remove any backward-compatibility shims
2. Remove dead code paths
3. Update documentation
4. Final test pass

**Commit**: "Phase 8: Cleanup and documentation"

## RPC Interface Updates

The RPC handlers should use cleaner, more predictable interfaces:

### Current (scattered, inconsistent)
```typescript
// Various methods with different patterns
orchestrator.getSession(sessionId)
orchestrator.runAgent(options)
orchestrator.compactContext(sessionId)
```

### Target (consistent, predictable)
```typescript
interface OrchestratorRPC {
  // Session lifecycle
  session: {
    create(options: CreateSessionOptions): Promise<SessionInfo>;
    resume(sessionId: SessionId): Promise<SessionInfo>;
    fork(eventId: EventId, options?: ForkOptions): Promise<ForkResult>;
    destroy(sessionId: SessionId): Promise<void>;
    list(options?: ListOptions): Promise<SessionInfo[]>;
    get(sessionId: SessionId): Promise<SessionInfo | null>;
  };

  // Agent operations
  agent: {
    run(sessionId: SessionId, prompt: string, options?: RunOptions): Promise<void>;
    interrupt(sessionId: SessionId): Promise<void>;
  };

  // Context operations
  context: {
    get(sessionId: SessionId): Promise<ContextSnapshot>;
    getDetailed(sessionId: SessionId): Promise<DetailedContextSnapshot>;
    previewCompaction(sessionId: SessionId): Promise<CompactionPreview>;
    confirmCompaction(sessionId: SessionId, editedSummary?: string): Promise<CompactionResult>;
    clear(sessionId: SessionId): Promise<void>;
  };

  // Skill operations
  skill: {
    add(sessionId: SessionId, skill: SkillRef): Promise<void>;
    remove(sessionId: SessionId, skillName: string): Promise<void>;
    list(sessionId: SessionId): Promise<SkillInfo[]>;
  };
}
```

## Test Strategy

### TDD Approach
1. **Write tests first** for each module before extraction
2. **Tests define the contract** - implementation must satisfy tests
3. **Integration tests** verify modules work together
4. **Existing tests** must pass throughout

### Test Categories

#### Unit Tests (per module)
```
test/orchestrator/
├── event-persister.test.ts      # Linearization, error handling
├── turn-manager.test.ts         # Turn lifecycle, content tracking
├── session-state.test.ts        # State reconstruction
└── handlers/
    ├── plan-mode.test.ts
    ├── ask-user-question.test.ts
    ├── compaction.test.ts
    ├── context-clear.test.ts
    ├── interrupt.test.ts
    └── skill-rules.test.ts
```

#### Integration Tests
```
test/orchestrator/
├── orchestrator-integration.test.ts  # Full flows
├── concurrent-sessions.test.ts       # Multiple sessions
└── reconstruction.test.ts            # State from events
```

#### Existing Tests to Preserve
- `agentic-loop-reconstruction.test.ts` - Message reconstruction
- `event-linearization.test.ts` - Event chaining
- `ask-user-question-flow.test.ts` - AskUserQuestion special case
- `orchestrator-compaction.test.ts` - Compaction flow
- `plan-mode.test.ts` - Plan mode behavior
- `interrupt-handling.test.ts` - Interrupt scenarios

### Test Scenarios

| Scenario | What it tests |
|----------|--------------|
| Simple agent run | Basic turn lifecycle |
| Multi-turn with tools | Agentic loop handling |
| Interrupt during text | Partial content preservation |
| Interrupt during tool | Tool result handling |
| AskUserQuestion flow | Turn stop, user response |
| Compaction flow | Summary generation, context update |
| Context clear | Full reset |
| Session resume | State reconstruction |
| Session fork | Branch creation |
| Concurrent sessions | Isolation, no cross-contamination |
| Model switch during run | Config persistence |
| Skill add/remove | Skill tracking |
| Plan mode enter/exit | Tool blocking |

## Success Criteria

1. **Module sizes**: Main orchestrator < 500 lines, each handler < 200 lines
2. **Test coverage**: All modules have unit tests, all flows have integration tests
3. **All existing tests pass**: No regressions
4. **Concurrent sessions work**: Verified with specific test
5. **iOS app works**: Manual verification
6. **Clean git history**: Logical commits with rollback points
7. **No backward compatibility hacks**: Clean interfaces

## Git Strategy

### Branch
`refactor/orchestrator-modular`

### Commit Pattern
```
Phase N: <description>

- What was extracted/changed
- Key decisions made
- Tests added

🔖 Checkpoint: build passes, tests pass
```

### Rollback Points
Each phase commit is a safe rollback point where:
- Build passes
- All tests pass
- System is functional

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| API mismatch | Phase 0 audit, verify each API before use |
| Test gaps | TDD approach, write tests first |
| Integration issues | Run full test suite after each phase |
| iOS breakage | Sync after each major phase |
| Scope creep | Strict phase boundaries, commit before moving on |
| Data loss | SQLite is source of truth, events are immutable |

## Timeline Estimate

Not providing time estimates per instructions. Phases are ordered by dependency and complexity.

## Appendix: Agentic Loop Reconstruction

From `agentic-loop-reconstruction.test.ts`, the key scenarios:

### Scenario 1: Consecutive Assistant Messages
```
Events: user → assistant(tool_use) → tool.result → assistant(continuation)
Messages: user → assistant → user(tool_result) → assistant
```
Tool result is injected as user message to maintain alternation.

### Scenario 2: User Response After Tool
```
Events: user → assistant(AskUserQuestion) → tool.result → message.user
Messages: user → assistant → user
```
Tool result is NOT injected - user message is the response.

### Scenario 3: Compaction Boundary
```
Events: [old messages] → compact.boundary → compact.summary → [new messages]
Messages: user(summary) → assistant(ack) → [new messages only]
```
Pre-compaction messages are replaced with summary pair.

### Scenario 4: Context Cleared
```
Events: [old messages] → context.cleared → [new messages]
Messages: [new messages only]
```
Pre-clear messages are discarded entirely.

This reconstruction logic lives in `EventStore.getMessagesAt()` and must be preserved.
