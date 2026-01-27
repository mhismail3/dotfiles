# AgentRunner Extraction Plan

## Status: COMPLETED

## Goal

Extract the `runAgent()` method (430 lines) from `EventStoreOrchestrator` into a dedicated `AgentRunner` class. This is the largest method in the codebase and handles too many responsibilities. The extraction will improve maintainability, testability, and reduce the orchestrator's complexity.

---

## Final Results

**File:** `packages/agent/src/orchestrator/event-store-orchestrator.ts`

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| Orchestrator Lines | 1,667 | 1,283 | -384 |
| `runAgent()` Lines | 430 | 32 | -398 (thin wrapper) |
| AgentRunner Lines | 0 | 715 | NEW |
| Unit Tests Added | 0 | 51 | +51 |

**New File Created:** `packages/agent/src/orchestrator/agent-runner.ts` (715 lines)

---

## Implementation Summary

### What Was Done

1. **Created AgentRunner class** with comprehensive implementation:
   - Full context injection (skills, subagents, todos)
   - User content building (text, images, PDFs, attachments)
   - Message event recording
   - Reasoning level handling
   - Agent execution coordination
   - Interrupt handling with partial content persistence
   - Error handling with persistence
   - Event emission (turn_complete, agent.complete)

2. **Created comprehensive unit tests** (51 tests) using TDD:
   - Basic flow tests
   - Context injection tests
   - User content building tests
   - Reasoning level tests
   - Completion handling tests
   - Interrupt handling tests
   - Error handling tests
   - Plan mode callback tests
   - Edge case tests

3. **Integrated into orchestrator**:
   - Added `agentRunner: AgentRunner` property
   - Initialized in constructor with proper config
   - Replaced `runAgent()` body with thin 32-line wrapper
   - Removed unused imports

4. **Exported from module index** for testing

### Files Modified/Created

| File | Action |
|------|--------|
| `agent-runner.ts` | Created (715 lines) |
| `agent-runner.test.ts` | Created (51 tests) |
| `event-store-orchestrator.ts` | Modified (1,667 → 1,283 lines) |
| `index.ts` | Updated (export AgentRunner) |

---

## Success Criteria - All Met

- [x] `AgentRunner` class created (715 lines - includes comprehensive documentation)
- [x] `EventStoreOrchestrator` reduced to 1,283 lines (target was ~1,250)
- [x] `runAgent()` in orchestrator is 32 lines (delegation only)
- [x] All existing tests pass (3,177 tests)
- [x] 51 new unit tests added for AgentRunner
- [x] No behavior changes (same events emitted, same persistence)
- [x] All integration tests pass (interrupt handling, skill injection)

---

## Architecture After Extraction

```
packages/agent/src/orchestrator/
├── agent-runner.ts              (NEW: 715 lines)
├── agent-runner.test.ts         (NEW: 51 tests)
├── event-store-orchestrator.ts  (REDUCED: 1,283 lines)
├── agent-event-handler.ts       (unchanged)
├── session-manager.ts           (unchanged)
├── turn-content-tracker.ts      (unchanged)
├── index.ts                     (updated: exports AgentRunner)
└── ...
```

---

## Key Design Decisions

1. **AgentRunner is stateless** - all state lives in ActiveSession and SessionContext
2. **Dependency injection via config** - improves testability, avoids circular deps
3. **Logging context preserved** - withLoggingContext wraps entire run
4. **Processing state in orchestrator** - try/finally ensures cleanup
5. **Event linearization preserved** - all appends via SessionContext.appendEvent()
6. **TDD approach** - 51 tests written before/alongside implementation

---

## Test Coverage

| Test Category | Count |
|---------------|-------|
| Factory function | 1 |
| Basic flow | 7 |
| Context injection | 7 |
| User content building | 5 |
| Reasoning level | 3 |
| Completion handling | 4 |
| Interrupt handling | 9 |
| Error handling | 6 |
| Plan mode callback | 3 |
| Edge cases | 6 |
| **Total** | **51** |
