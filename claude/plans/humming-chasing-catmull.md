# Agent Package Code Quality Improvement Plan

## Summary

Comprehensive analysis of `packages/agent/src/` (251 files, ~73K lines) after recent refactoring. The architecture is sound (event-sourced, modular tools, clear layering), but several areas need attention to eliminate spaghetti code, anti-patterns, and hidden special handling.

---

## Critical Issues Found

### 1. Hidden Special Handling for RenderAppUI Tool
**Files:** `orchestrator/agent-event-handler.ts` (lines 448, 558, 921)

The `RenderAppUI` tool has hardcoded special case handling scattered across 3+ locations:
- Line 448: Special `ui_render_start` emission with `startEmitted` flag
- Line 558: Complex `ui_render_complete/error/retry` handling
- Line 921: Skip processing for RenderAppUI in toolcall_delta
- Hidden `activeUIRenders` Map tracking state (lines 82-86)

**Problem:** Future tool changes will be hard to discover and propagate.

**Fix:** Extract a `UIRenderHandler` class that encapsulates all RenderAppUI logic.

---

### 2. Large Orchestrator File (1932 lines)
**File:** `orchestrator/event-store-orchestrator.ts`

Despite extracting 8 modules (SubagentOperations, AgentEventHandler, SkillLoader, etc.), the orchestrator is still too large with too many responsibilities.

**Fix:** Further decompose into domain controllers:
- `SessionController` - Session CRUD and lifecycle
- `AgentController` - Agent execution coordination
- `EventController` - Event persistence and forwarding

---

### 3. Dual-State Tracking in TurnContentTracker
**File:** `orchestrator/turn-content-tracker.ts` (900+ lines)

Maintains parallel data structures:
```typescript
// Accumulated (across ALL turns)
private accumulatedText, accumulatedThinking, accumulatedToolCalls, accumulatedSequence

// Per-turn (cleared each message.assistant)
private thisTurnSequence, thisTurnToolCalls, thisTurnThinking
```

**Problem:** Updates must happen in parallel to both structures. Easy to miss an update leading to state divergence.

**Fix:** Create a `TurnSnapshot` class that maintains consistency between accumulated/per-turn views.

---

### 4. Type System Issues (307+ `as any`, 16+ `as unknown as`)
**Files:** Multiple across providers, tools, utils

Root causes:
- Settings loading returns untyped JSON
- API responses have optional fields not fully typed
- Input vs arguments dual format in tools

**Fix:**
- Add proper types to settings loader: `const settings: TronSettings = JSON.parse(...)`
- Create wrapper types for API responses
- Unify input/arguments handling in tool base class

---

### 5. Code Duplication in FS Tools
**Files:** `tools/fs/read.ts`, `write.ts`, `grep.ts`, `find.ts`, `edit.ts`, `ls.ts`

Every tool duplicates:
- Parameter validation (~15 lines each)
- Path resolution (`resolvePath()` method)
- Error response formatting

**Fix:** Create `ToolValidator` utility and `BaseFilesystemTool` class.

---

### 6. Over-Engineered RPC Handler Interfaces
**File:** `rpc/handler.ts` (lines 62-318)

Defines 13 separate manager interfaces (SessionManager, AgentManager, ContextRpcManager, etc.) in a single file. Most are marked `optional`.

**Fix:**
- Group related managers into 4-5 domain interfaces
- Move interface definitions to their respective domains

---

### 7. Inconsistent Error Handling
**Files:** Scattered across orchestrator, tools, providers

Three patterns observed:
1. Log and rethrow: `catch (err) { logger.error(...); throw err; }`
2. Log and continue: `catch (err) { logger.warn(...); /* continue */ }`
3. Mutate and continue: `catch (e) { input = { _serializationError: true }; }`

**Fix:** Establish error handling spec:
- Critical errors: log and rethrow
- Recoverable errors: log warning, use fallback
- Create `ErrorHandler` utility with consistent patterns

---

### 8. Naming Confusion (rpc/handlers vs gateway/rpc/adapters)
- `rpc/handlers/` - Processes JSON-RPC methods
- `gateway/rpc/adapters/` - Adapts orchestrator to RPC context

**Fix:** Rename `gateway/rpc/adapters/` to `gateway/adapters/` to reduce confusion.

---

## Recommended Prioritization

### Phase 1: Quick Wins (High ROI, Low Risk)
1. **Extract tool parameter validator** - Eliminates 200+ duplicated lines
2. **Extract path resolution utility** - Eliminates 50+ duplicated methods
3. **Create typed settings accessors** - Eliminates 20+ getter functions
4. **Document RenderAppUI handling** - Add clear docstrings until extraction

### Phase 2: Structural Improvements (Medium Risk)
5. **Extract UIRenderHandler** - Consolidate scattered RenderAppUI logic
6. **Split EventStoreOrchestrator** - Create SessionController, AgentController
7. **Unify provider wrapper creation** - Generic wrapper factory
8. **Group RPC manager interfaces** - 13 interfaces → 4-5 domain groups

### Phase 3: Type System Hardening (Lower Priority)
9. **Type settings loader properly**
10. **Create API response wrapper types**
11. **Eliminate `as any` casts systematically**

---

## Files to Modify

| File | Change |
|------|--------|
| `tools/fs/*.ts` (6 files) | Extract to BaseFilesystemTool |
| `tools/utils.ts` (new) | ToolValidator, resolvePath |
| `orchestrator/agent-event-handler.ts` | Extract UIRenderHandler |
| `orchestrator/ui-render-handler.ts` (new) | RenderAppUI handling |
| `orchestrator/event-store-orchestrator.ts` | Split into controllers |
| `orchestrator/session-controller.ts` (new) | Session CRUD |
| `providers/factory.ts` | Generic wrapper factory |
| `rpc/handler.ts` | Reorganize manager interfaces |
| `gateway/rpc/adapters/` | Rename to `gateway/adapters/` |
| `settings/accessors.ts` (new) | Typed settings getters |

---

## Approach: Zero-Regression Methodology

**Goal:** Make the agent "unit" comprehensive and robust. Every change must improve quality without introducing issues.

### Principles

1. **One concern at a time** - Each PR/commit addresses exactly one issue
2. **Test before touching** - Ensure test coverage exists before refactoring
3. **Behavior preservation** - Extract, don't redesign (preserve APIs)
4. **Incremental validation** - Build + test after every change
5. **Gradual extraction** - For orchestrator, extract one concern per session

### Per-Change Checklist

For EVERY refactoring change:
- [ ] Identify existing test coverage for affected code
- [ ] Add tests if coverage is insufficient
- [ ] Make the change (extract/consolidate/rename)
- [ ] Run `bun run build && bun run test`
- [ ] Verify no new TypeScript errors
- [ ] Verify no new `any`/`unknown` escapes introduced
- [ ] Manual smoke test if touching critical paths (session resume, fork, tool execution)

---

## Verification Strategy

### Automated Verification
```bash
# Run after EVERY change
bun run build && bun run test
```

### Critical Path Testing
Before marking any phase complete, manually verify:
1. **Session lifecycle:** Create → prompt → interrupt → resume
2. **Fork/branch:** Fork session, verify event chain integrity
3. **Tool execution:** Run FS tools, verify parameter handling
4. **Compaction:** Trigger compaction, verify context reconstruction
5. **Subagent:** Spawn subagent, query status, receive result

### Regression Indicators
Watch for these during refactoring:
- Event linearization breaks (orphaned events)
- Message reconstruction fails (missing tool results)
- State divergence (accumulated vs per-turn mismatch)
- Type errors at runtime (where `as any` masked issues)

---

## Execution Order

### Session 1: Foundation (Quick Wins)
1. Extract `ToolValidator` utility with tests
2. Extract `resolvePath` utility with tests
3. Create typed settings accessors with tests
4. **Checkpoint:** Full test suite passes

### Session 2: UIRenderHandler Extraction
1. Write tests for current RenderAppUI behavior
2. Extract `UIRenderHandler` class (preserve exact API)
3. Update `AgentEventHandler` to delegate
4. **Checkpoint:** RenderAppUI flows work identically

### Session 3: Orchestrator - Session Concerns
1. Identify session-related methods in orchestrator
2. Extract `SessionController` (preserve method signatures)
3. Orchestrator delegates to controller
4. **Checkpoint:** Session CRUD works identically

### Session 4: Orchestrator - Event Concerns
1. Extract event forwarding/persistence logic
2. Create `EventController`
3. **Checkpoint:** Event linearization verified

### Session 5: Type System Hardening
1. Type settings loader properly
2. Eliminate `as any` casts one file at a time
3. Add proper discriminated unions for content blocks
4. **Checkpoint:** No type escapes in touched files

### Session 6: Final Cleanup
1. Rename `gateway/rpc/adapters/` → `gateway/adapters/`
2. Group RPC manager interfaces
3. Update documentation
4. **Final verification:** All critical paths tested

---

## Files to Modify

| File | Change | Risk |
|------|--------|------|
| `tools/utils.ts` (new) | ToolValidator, resolvePath | Low |
| `tools/fs/*.ts` (6 files) | Use shared utilities | Low |
| `settings/accessors.ts` (new) | Typed settings getters | Low |
| `orchestrator/ui-render-handler.ts` (new) | RenderAppUI handling | Medium |
| `orchestrator/agent-event-handler.ts` | Delegate to UIRenderHandler | Medium |
| `orchestrator/session-controller.ts` (new) | Session CRUD extraction | Medium |
| `orchestrator/event-store-orchestrator.ts` | Delegate to controllers | Medium |
| `gateway/adapters/` (rename) | Rename from gateway/rpc/adapters | Low |
| `rpc/handler.ts` | Reorganize interfaces | Low |

---

## Success Criteria

1. **Zero test regressions** - All 146+ existing tests pass
2. **Zero new type escapes** - No new `any`/`unknown` casts
3. **Improved discoverability** - No hidden special handling
4. **Reduced file sizes** - Orchestrator < 1000 lines
5. **Consistent patterns** - Error handling, validation unified
6. **Full critical path verification** - Manual testing complete
