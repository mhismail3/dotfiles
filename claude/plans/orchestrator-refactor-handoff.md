# Orchestrator Refactor - Handoff Plan

## Status: Phases 1-3 Complete, Phases 4-6 Remaining

**Original Plan:** `~/.claude/plans/rosy-stargazing-yeti.md`
**Date:** 2026-01-16

---

## What Was Completed

### Phase 1: Foundation ✅

Created foundation modules with comprehensive unit tests:

| File | Purpose | Tests |
|------|---------|-------|
| `packages/server/src/orchestrator/event-persister.ts` | Linearized event persistence facade | 16 |
| `packages/server/src/orchestrator/turn-manager.ts` | Turn lifecycle and content tracking wrapper | 22 |
| `packages/server/src/orchestrator/strategies/index.ts` | Strategy pattern types and runner | - |
| `packages/server/src/orchestrator/index.ts` | Module exports | - |

### Phase 2: Strategies ✅

Created all strategy implementations with unit tests (34 tests total):

| Strategy | File | Purpose |
|----------|------|---------|
| PlanMode | `strategies/plan-mode.ts` | Block destructive tools (Write, Edit, Bash) during planning |
| AskUserQuestion | `strategies/ask-user-question.ts` | Stop turn when question presented, await user response |
| Interrupt | `strategies/interrupt.ts` | Handle user abort, persist partial content |
| Compaction | `strategies/compaction.ts` | Context compaction with summary |
| ContextClear | `strategies/compaction.ts` | Clear all messages without summary |
| SkillRules | `strategies/skill-rules.ts` | Track skills and rules context |

### Phase 3: Session Reconstruction ✅

Created session reconstructor with tests (12 tests):

| File | Purpose |
|------|---------|
| `packages/server/src/orchestrator/session-reconstructor.ts` | Rebuild session state from event history |

**Test Results:** 84 new orchestrator tests, all passing

---

## What Remains

### Phase 4: New Orchestrator (Partial - Needs Completion)

**Current State:** `packages/server/src/orchestrator/orchestrator.ts` exists as a skeleton/stub.

**What's Missing:**

1. **Complete the Orchestrator Implementation**
   - Wire up strategies to handle events during agent runs
   - Integrate EventPersister for all event persistence
   - Integrate TurnManager for turn lifecycle
   - Integrate SessionReconstructor for session resume
   - Implement the public API to match existing `EventStoreOrchestrator`

2. **Integration Tests**
   - Test full prompt → agent run → persistence flow
   - Test interrupt handling end-to-end
   - Test plan mode blocking end-to-end
   - Test compaction flow end-to-end
   - Test session resume from events

**Key Files to Reference:**
- Existing orchestrator: `packages/server/src/event-store-orchestrator.ts` (1997 lines)
- Existing tests: `packages/server/test/agentic-loop-reconstruction.test.ts`

### Phase 5: Migration

**Goal:** Replace `event-store-orchestrator.ts` with the new modular orchestrator.

**Steps:**

1. **Update Exports**
   - Modify `packages/server/src/orchestrator/index.ts` to export the new orchestrator
   - Ensure API compatibility with existing consumers

2. **Update Consumers**
   - Find all imports of `EventStoreOrchestrator`
   - Update to use new modular structure
   - Key consumer: `packages/server/src/session-manager.ts`

3. **Run Existing Tests**
   ```bash
   npm run test --workspace=@tron/server -- --run
   ```
   All 459 tests must pass.

4. **Manual iOS App Testing**
   - Test session creation
   - Test prompt handling
   - Test tool execution
   - Test interrupt/cancel
   - Test session resume
   - Test plan mode

### Phase 6: Cleanup

**After Migration Verified:**

1. **Remove Legacy Code**
   - Delete or archive `packages/server/src/event-store-orchestrator.ts`
   - Remove any unused helper functions

2. **Remove Dual-Tracking**
   - Check for legacy fields that are no longer needed
   - Remove redundant state tracking

3. **Final Verification**
   - Full test suite passes
   - TypeScript compilation clean
   - iOS app works end-to-end

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     Orchestrator                             │
│  (coordinates session lifecycle, agent runs, persistence)    │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │ EventPersister│  │ TurnManager  │  │SessionReconstructor│ │
│  │ (linearized   │  │ (turn lifecycle│ │(rebuild state     │ │
│  │  persistence) │  │  & content)   │  │ from events)      │ │
│  └──────────────┘  └──────────────┘  └──────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                    Strategies                         │   │
│  │  ┌─────────┐ ┌───────────────┐ ┌───────────┐        │   │
│  │  │PlanMode │ │AskUserQuestion│ │ Interrupt │ ...    │   │
│  │  └─────────┘ └───────────────┘ └───────────┘        │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Key Interfaces

### EventPersister

```typescript
interface EventPersister {
  // Fire-and-forget append (queued)
  append(request: AppendRequest): void;

  // Append and wait for persistence
  appendAsync(request: AppendRequest): Promise<TronSessionEvent | null>;

  // Wait for all pending appends
  flush(): Promise<void>;

  // Get current head event ID
  getPendingHeadEventId(): EventId;

  // Check/get errors
  hasError(): boolean;
  getError(): Error | undefined;
}
```

### TurnManager

```typescript
interface TurnManager {
  // Lifecycle
  onAgentStart(): void;
  onAgentEnd(): void;
  startTurn(turn: number): void;
  endTurn(tokenUsage?: TokenUsage): EndTurnResult;

  // Content accumulation
  addTextDelta(text: string): void;
  startToolCall(id: string, name: string, args: object): void;
  endToolCall(id: string, result: string, isError: boolean): void;

  // Access
  getAccumulatedContent(): AccumulatedContent;
  buildInterruptedContent(): InterruptedContent;
  getCurrentTurn(): number;
}
```

### Strategy

```typescript
interface Strategy {
  readonly name: string;
  applies(event: TronEvent, session: SessionState): boolean;
  handle(event: TronEvent, context: StrategyContext): Promise<StrategyResult>;
}

interface StrategyResult {
  handled: boolean;
  stopTurn: boolean;
  persist?: EventToAppend[];
  error?: Error;
  metadata?: Record<string, unknown>;
}
```

---

## Test Commands

```bash
# Run only orchestrator tests
npm run test --workspace=@tron/server -- --run test/orchestrator/

# Run all server tests
npm run test --workspace=@tron/server -- --run

# TypeScript check
npx tsc --noEmit --project packages/server/tsconfig.json
```

---

## Notes

- The new modules are designed to work alongside the existing orchestrator during migration
- Strategy pattern allows adding new special-case handlers without modifying core logic
- EventPersister ensures linear event chains via promise serialization
- SessionReconstructor finds boundaries (compaction, context clear) and rebuilds state

---

## Files Created in This Session

```
packages/server/src/orchestrator/
├── index.ts                          # Module exports
├── event-persister.ts                # Linearized persistence
├── turn-manager.ts                   # Turn lifecycle
├── session-reconstructor.ts          # State reconstruction
├── orchestrator.ts                   # Main orchestrator (skeleton)
└── strategies/
    ├── index.ts                      # Strategy types & runner
    ├── plan-mode.ts                  # Plan mode blocking
    ├── ask-user-question.ts          # Question handling
    ├── interrupt.ts                  # Abort handling
    ├── compaction.ts                 # Compaction & clear
    └── skill-rules.ts                # Skill tracking

packages/server/test/orchestrator/
├── event-persister.test.ts           # 16 tests
├── turn-manager.test.ts              # 22 tests
├── strategies.test.ts                # 34 tests
└── session-reconstructor.test.ts     # 12 tests
```
