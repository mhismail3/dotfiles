# Tron Agent Architecture Consolidation Plan

## Goal
Establish a rock-solid foundational architecture for the "composable agent unit" by eliminating duplication, consolidating related modules, and establishing clear module boundaries - all while maintaining **absolute zero regressions**.

## Phase Ordering: Strict Sequential

**Phases MUST be completed in order: 0 → 1 → 2 → 3 → 4 → 5 → 6 → 7**

- No skipping phases
- No parallel execution of phases
- Each phase must pass ALL verification before proceeding
- If a phase fails, fix it before moving on (do not skip)

This ensures:
1. Low-risk changes build confidence
2. Learnings from early phases inform later phases
3. Clear rollback points at each phase boundary
4. No cascading failures from interleaved changes

---

## Philosophy: Test-Driven Refactoring

This refactoring follows strict TDD principles:
1. **Understand before changing** - Read existing tests and trace code paths before any modification
2. **Test first, always** - Run full test suite before AND after every change
3. **One logical change at a time** - Never batch unrelated changes
4. **Verify immediately** - Build and test after every file move/edit
5. **Commit atomically** - Each commit is a safe rollback point
6. **When in doubt, stop** - Any unexpected test failure halts progress until understood

## Critical Constraints
- **ABSOLUTE ZERO test regressions** - All 3031 tests must pass at every step
- **Run tests after EVERY file change** - Not just after phases
- **Preserve ALL public APIs** - No breaking changes to external consumers
- **Understand tests before touching code** - Read related tests first
- **Atomic commits** - Each change is independently revertable
- **No behavioral changes** - Pure structural refactoring only

---

## Phase 0: Pre-Refactoring Analysis (MUST DO FIRST)

**Goal**: Establish baseline metrics, identify coverage gaps, and understand architectural history before any changes.

### 0.1 Run Coverage Report

```bash
# Generate coverage report
cd packages/agent
bun test --coverage

# Or with detailed HTML report
bun test --coverage --coverage-reporter=html
# Open coverage/index.html in browser
```

**Document**:
- Overall coverage percentage
- Modules with <70% coverage (HIGH RISK for refactoring)
- Modules with <50% coverage (DO NOT refactor without adding tests first)

**Coverage Risk Matrix**:
| Coverage | Risk Level | Action |
|----------|------------|--------|
| >80% | Low | Safe to refactor |
| 60-80% | Medium | Refactor carefully, verify manually |
| <60% | High | Add tests first OR skip module |

### 0.2 Investigate RPC Layer History

Before deciding on RPC consolidation approach, understand why both layers exist:

```bash
# When were adapters introduced?
git log --oneline --all -- packages/agent/src/gateway/rpc/adapters/ | head -20

# When were handlers created?
git log --oneline --all -- packages/agent/src/rpc/handlers/ | head -20

# Find commits that touch both
git log --oneline --all -- packages/agent/src/gateway/rpc/ packages/agent/src/rpc/ | head -30

# Read key commit messages
git show <commit-hash> --stat
```

**Questions to answer**:
1. Were adapters added as part of a migration?
2. Is there a pattern - do adapters exist for orchestrator while handlers are for other things?
3. Are there any comments in the code explaining the architecture?

**Document findings** before proceeding to Phase 4.

### 0.3 Baseline Metrics

```bash
# Count source files (excluding tests)
find packages/agent/src -name "*.ts" -not -name "*.test.ts" | wc -l

# Count lines of code
find packages/agent/src -name "*.ts" -not -name "*.test.ts" | xargs wc -l | tail -1

# Count directories
find packages/agent/src -type d | wc -l

# Test count baseline
bun test 2>&1 | grep -E "Tests.*passed"
```

**Record these numbers** - we'll compare after refactoring.

### 0.4 iOS App Smoke Test Baseline

Before any changes, verify iOS app works:
1. Start server: `bun run dev` (or however you start it)
2. Open iOS app
3. Verify: Can connect to server
4. Verify: Can send a message and receive response
5. Verify: Tool execution works (e.g., ask it to read a file)

**This establishes the manual verification baseline.**

---

## Verification Protocol (After EVERY Phase)

After completing each phase, run this full verification:

### Automated Verification
```bash
# 1. Build must succeed
bun run build

# 2. ALL tests must pass with same count
bun test
# Verify: 3031 tests passing (or whatever baseline was)

# 3. No new circular dependencies
npx madge --circular packages/agent/src/index.ts
```

### Manual iOS Verification
1. Restart server (kill and restart to pick up changes)
2. Open iOS app - verify connection
3. Send test message: "Hello, what's 2+2?"
4. Verify response received
5. Test tool use: "Read the file package.json"
6. Verify file contents returned

### Commit Gate
**DO NOT proceed to next phase unless**:
- [ ] Build passes
- [ ] All tests pass (same count)
- [ ] iOS app smoke test passes
- [ ] Changes committed with descriptive message

---

## Pre-Flight Checklist (Before ANY Phase)

Before starting any phase, execute this checklist:

```bash
# 1. Ensure clean working state
git status  # Must be clean or only have expected changes

# 2. Run full test suite - establish baseline
bun run build && bun test
# Record: X tests passing, 0 failing

# 3. Verify no existing circular dependencies
# (Install if needed: bun add -d madge)
npx madge --circular packages/agent/src/index.ts

# 4. Create safety branch
git checkout -b refactor/phase-N-description
```

## TDD Workflow for Each File Move

For EVERY file relocation:

```
1. BEFORE moving:
   - Read the file being moved
   - Read ALL tests for that file
   - Grep for ALL imports of that file: grep -r "from.*filename" packages/agent/src/
   - Document the import count

2. Move the file:
   - git mv old/path new/path (preserves history)

3. Update imports in the moved file:
   - Fix relative imports to new location

4. IMMEDIATELY test:
   - bun run build  # Must succeed
   - bun test       # Must have same pass count

5. Update ONE importer at a time:
   - Edit import path
   - bun run build && bun test  # After EACH file

6. Verify import count matches:
   - grep -r "from.*newpath" packages/agent/src/
   - Must match original count

7. Commit:
   - git add -A && git commit -m "Move X to Y, update N imports"
```

---

## Key Issues Identified

### Issue Summary Table

| Issue | Severity | Impact | Effort |
|-------|----------|--------|--------|
| Dual RPC systems (handlers vs adapters) | HIGH | ~2,500 lines duplication | High |
| Tracker pattern duplication (3 classes) | MEDIUM | ~580 lines duplication | Medium |
| Single-file directories (5 modules) | LOW | Navigation overhead | Low |
| Circular import risks (content-normalizer) | MEDIUM | Subtle initialization bugs | Low |
| Content processing scattered | MEDIUM | ~400 lines duplication | Medium |
| Bloated event-store.ts (41K lines) | HIGH | Hard to maintain | High |
| Types module too broad | LOW | Unclear ownership | Medium |

---

## Phase 1: Consolidate Single-File Directories (Low Risk)

**Goal**: Reduce unnecessary directory nesting by moving single-file modules to their logical parents.

**CRITICAL**: Each sub-phase (1.1, 1.2, etc.) is a separate commit. Do NOT batch them.

---

### 1.1 Move `artifacts/` → `productivity/`

**Step 1.1.1: Pre-analysis**
```bash
# Find all importers
grep -r "from.*artifacts" packages/agent/src/ --include="*.ts"
grep -r "from.*canvas-store" packages/agent/src/ --include="*.ts"
# Document count: Expected ~2-3 files
```

**Step 1.1.2: Read and understand**
- Read `src/artifacts/canvas-store.ts` - understand what it exports
- Read `src/artifacts/index.ts` - understand re-exports
- Read any tests: `grep -r "canvas-store" packages/agent/src/**/*.test.ts`

**Step 1.1.3: Move file**
```bash
git mv src/artifacts/canvas-store.ts src/productivity/canvas-store.ts
bun run build  # EXPECT: May fail due to imports - that's OK
```

**Step 1.1.4: Update moved file's internal imports**
- Edit `src/productivity/canvas-store.ts`
- Fix any relative imports (e.g., `../logging` → same, `../types` → same)
```bash
bun run build  # Should get closer to success
```

**Step 1.1.5: Update `productivity/index.ts`**
- Add: `export * from './canvas-store.js';`
```bash
bun run build && bun test  # May still fail - importers not updated
```

**Step 1.1.6: Update each importer ONE AT A TIME**
```bash
# For each file that imports from artifacts:
# 1. Edit the import
# 2. bun run build && bun test
# 3. Only proceed if tests pass
```

**Step 1.1.7: Update root `index.ts` re-exports**
- Remove: `export * from './artifacts/index.js';`
- Verify productivity already exports canvas-store
```bash
bun run build && bun test  # MUST pass
```

**Step 1.1.8: Delete empty artifacts directory**
```bash
rm -rf src/artifacts/
bun run build && bun test  # MUST pass - same count as baseline
```

**Step 1.1.9: Commit**
```bash
git add -A
git commit -m "Move artifacts/canvas-store to productivity module

- Consolidates single-file artifacts/ directory
- Updates N imports
- All 3031 tests passing"
```

---

### 1.2 Move `features/` → `settings/`

**Step 1.2.1: Pre-analysis**
```bash
grep -r "from.*features" packages/agent/src/ --include="*.ts"
# Document count
```

**Step 1.2.2: Read and understand**
- Read `src/features/index.ts`
- Understand what feature flags exist
- Find tests that cover feature flag behavior

**Step 1.2.3: Move and rename**
```bash
git mv src/features/index.ts src/settings/feature-flags.ts
```

**Step 1.2.4: Update settings/index.ts**
- Add: `export * from './feature-flags.js';`

**Step 1.2.5: Update importers one at a time**
- Change `from '../features/index.js'` → `from '../settings/feature-flags.js'`
- Or use re-export: `from '../settings/index.js'`
```bash
# After EACH file:
bun run build && bun test
```

**Step 1.2.6: Update root index.ts**
- Remove features re-export
- Verify settings exports feature-flags

**Step 1.2.7: Delete features directory**
```bash
rm -rf src/features/
bun run build && bun test  # MUST pass
```

**Step 1.2.8: Commit**
```bash
git add -A
git commit -m "Move features/index to settings/feature-flags

- Consolidates single-file features/ directory
- All tests passing"
```

---

### 1.3 Move `memory/` → `types/`

**Follow same pattern as 1.1 and 1.2**

```bash
# Pre-analysis
grep -r "from.*memory" packages/agent/src/ --include="*.ts"

# Move
git mv src/memory/types.ts src/types/memory.ts

# Update types/index.ts
# Add: export * from './memory.js';

# Update importers one at a time with build+test after each

# Update root index.ts

# Delete directory
rm -rf src/memory/

# Final verification
bun run build && bun test

# Commit
git commit -m "Move memory/types to types/memory - consolidate single-file directory"
```

---

### 1.4 Move `tmux/` → `session/`

**Follow same pattern**

```bash
# Pre-analysis
grep -r "from.*tmux" packages/agent/src/ --include="*.ts"

# Move
git mv src/tmux/manager.ts src/session/tmux-manager.ts

# Update session/index.ts exports

# Update importers one at a time

# Delete directory
rm -rf src/tmux/

# Commit
git commit -m "Move tmux/manager to session/tmux-manager - consolidate single-file directory"
```

---

### 1.5 Move `subagents/` → `tools/`

**Follow same pattern**

```bash
# Pre-analysis
grep -r "from.*subagents" packages/agent/src/ --include="*.ts"

# Move
git mv src/subagents/subagent-tracker.ts src/tools/subagent-tracker.ts

# Update tools/index.ts exports

# Update importers one at a time

# Delete directory
rm -rf src/subagents/

# Commit
git commit -m "Move subagents/tracker to tools/ - co-locate with subagent tools"
```

---

### Phase 1 Completion Checklist

Before moving to Phase 2:
- [ ] All 5 directories consolidated
- [ ] 5 separate commits (one per move)
- [ ] `bun run build` passes
- [ ] `bun test` shows exactly 3031 tests passing
- [ ] No test count changed
- [ ] `git log --oneline -5` shows 5 clean commits

---

## Phase 2: Fix Circular Import Risks (Low Risk)

**Goal**: Eliminate circular dependency risks by using direct imports instead of root re-exports.

### 2.1 Fix `utils/content-normalizer.ts`
Change:
```typescript
// BEFORE (circular risk)
import { normalizeToolArguments, normalizeToolResultId } from '../index.js';

// AFTER (direct import)
import { normalizeToolArguments, normalizeToolResultId } from '../types/messages.js';
```

### 2.2 Audit other utils/ files for similar patterns
Check: `clipboard.ts`, `errors.ts`, `retry.ts`, `media.ts`, `file-completion.ts`

### 2.3 Move domain-specific utilities to their modules
```
src/utils/file-completion.ts → src/tools/file-completion.ts
```
- Only used by bash and find tools
- Co-locate with consumers

**Verification**:
```bash
bun run build && bun test
```

**Commit**: "Fix circular imports and relocate domain-specific utilities"

---

## Phase 3: Create Generic Tracker Base Class (Medium Risk)

**Goal**: Extract common tracker pattern to eliminate ~300 lines of duplication.

### 3.1 Create base tracker abstraction
Create `src/utils/event-sourced-tracker.ts`:
```typescript
/**
 * Generic base class for event-sourced state trackers.
 * Eliminates duplication across skill-tracker, rules-tracker, subagent-tracker.
 */
export abstract class EventSourcedTracker<TItem, TEvent extends { type: string; payload: unknown }> {
  protected items: Map<string, TItem> = new Map();

  abstract processEvent(event: TEvent): void;

  getItems(): TItem[] {
    return Array.from(this.items.values());
  }

  static fromEvents<T extends EventSourcedTracker<any, any>>(
    this: new () => T,
    events: Array<{ type: string; payload: unknown }>
  ): T {
    const tracker = new this();
    for (const event of events) {
      tracker.processEvent(event as any);
    }
    return tracker;
  }
}
```

### 3.2 Refactor existing trackers to extend base
- `skills/skill-tracker.ts` extends `EventSourcedTracker<TrackedSkill, SkillEvent>`
- `context/rules-tracker.ts` extends `EventSourcedTracker<TrackedRule, RulesEvent>`
- `tools/subagent-tracker.ts` extends `EventSourcedTracker<TrackedSubagent, SubagentEvent>`

### 3.3 Preserve existing public APIs
- Keep same method signatures
- Base class provides common implementation

**Verification**:
```bash
bun run build && bun test
# Specifically run tracker-related tests
bun test skill-track rules-track subagent-track
```

**Commit**: "Extract EventSourcedTracker base class to eliminate duplication"

---

## Phase 4: Consolidate RPC Layer (High Risk - CONTINGENT ON PHASE 0 FINDINGS)

**Goal**: Unify the dual RPC systems (handlers vs adapters) into a single coherent pattern.

**PREREQUISITE**: Complete Phase 0.2 (RPC history investigation) before starting this phase.

### Decision Point Based on History Investigation

After investigating git history in Phase 0.2, choose ONE path:

#### Path A: Remove Adapter Layer (if adapters are pure pass-through)
If investigation shows adapters are just wrapping orchestrator methods with no additional logic:

```
Current: WebSocket → RpcHandler → handlers → adapters → orchestrator
Target:  WebSocket → RpcHandler → handlers → orchestrator (directly)
```

#### Path B: Remove Handler Layer (if handlers are thin wrappers)
If investigation shows handlers just extract params and call adapters:

```
Current: WebSocket → RpcHandler → handlers → adapters → orchestrator
Target:  WebSocket → RpcHandler → adapters → orchestrator
```

#### Path C: Keep Both (if they serve different purposes)
If investigation reveals legitimate separation of concerns:
- Document the architecture clearly
- Skip consolidation
- Move to Phase 5

### 4.1 Pre-Consolidation Analysis (After Path Selection)

```bash
# Map handler → adapter relationships
for handler in packages/agent/src/rpc/handlers/*.ts; do
  echo "=== $handler ==="
  grep -l "$(basename $handler .handler.ts)" packages/agent/src/gateway/rpc/adapters/
done

# Check if adapters add any logic beyond delegation
grep -r "if\|switch\|try\|catch" packages/agent/src/gateway/rpc/adapters/ --include="*.ts"
```

### 4.2 Incremental Migration (ONE handler/adapter pair at a time)

**DO NOT batch migrate all handlers at once.**

For EACH handler/adapter pair:

**Step 1**: Pick ONE handler (start with simplest, e.g., `system.handler.ts`)

**Step 2**: Read both files thoroughly
```bash
cat packages/agent/src/rpc/handlers/system.handler.ts
cat packages/agent/src/gateway/rpc/adapters/system.adapter.ts
```

**Step 3**: Identify what adapter does beyond delegation

**Step 4**: Merge logic into handler (or vice versa based on Path chosen)

**Step 5**: Update imports

**Step 6**: Run full verification
```bash
bun run build && bun test
# iOS smoke test
```

**Step 7**: Commit this single handler migration
```bash
git commit -m "Consolidate system handler/adapter - remove adapter indirection"
```

**Step 8**: Repeat for next handler/adapter pair

### 4.3 Handler Migration Order (simplest to most complex)

1. `system.handler.ts` - Simple, low risk
2. `model.handler.ts` - Simple
3. `file.handler.ts` - Simple
4. `tree.handler.ts` - Simple
5. `search.handler.ts` - Medium complexity
6. `context.handler.ts` - Medium complexity
7. `session.handler.ts` - Complex, high risk
8. `agent.handler.ts` - Most complex, do last

### 4.4 Rollback Plan

If ANY handler migration causes issues:
```bash
git revert HEAD  # Revert the single handler change
# Previous handlers remain consolidated
# Skip problematic handler for now
```

### 4.5 Phase 4 Completion

After all handlers migrated:
```bash
# Delete adapter directory only after ALL are migrated
rm -rf packages/agent/src/gateway/rpc/adapters/

bun run build && bun test
# Full iOS verification
```

**Commit**: "Complete RPC consolidation - remove adapter layer"

---

## Phase 5: Split Bloated Event Store (High Risk - INCREMENTAL)

**Goal**: Break up the 41K-line `event-store.ts` into focused modules while preserving ALL public APIs.

**CRITICAL**: This is the highest-risk phase. Do ONE extraction at a time with full verification.

### 5.0 Pre-Split Analysis

```bash
# Understand the file structure
wc -l packages/agent/src/events/event-store.ts
# Expected: ~1500-2000 lines (41K was the whole events/ folder)

# Find all public methods
grep -E "^\s+(public |async )?[a-z].*\(" packages/agent/src/events/event-store.ts | head -50

# Find all external importers
grep -r "from.*event-store" packages/agent/src/ --include="*.ts" | grep -v test | wc -l

# Check test coverage for event-store
bun test --coverage packages/agent/src/events/event-store.ts
```

**Document**:
- Line count of event-store.ts
- Number of public methods
- Number of external importers
- Test coverage percentage

**If coverage < 70%**: Add tests before splitting, or skip this phase.

### 5.1 Identify Natural Seams

Read event-store.ts and identify method clusters:

```
Cluster 1: Session Operations
- createSession()
- getSession()
- updateSession()
- deleteSession()
- listSessions()

Cluster 2: Event Operations
- appendEvent()
- getEvents()
- getEventsAfter()

Cluster 3: Message Reconstruction
- getMessagesAt()
- reconstructState()

Cluster 4: Branch Operations
- createBranch()
- forkSession()

Cluster 5: Search Operations
- searchEvents()
- searchSessions()

Cluster 6: Workspace Operations
- createWorkspace()
- getWorkspace()
```

### 5.2 Extraction Order (Lowest Risk First)

1. **Search Operations** - Likely most isolated, least coupled
2. **Workspace Operations** - Usually independent
3. **Branch Operations** - May have session dependencies
4. **Message Reconstruction** - Complex but isolated
5. **Session Operations** - Core, do last

### 5.3 Extraction Pattern (Repeat for Each Cluster)

**Example: Extract Search Operations**

**Step 1**: Create new file with types
```typescript
// src/events/search-ops.ts
import type { SQLiteBackend } from './sqlite/index.js';

export interface SearchOperations {
  searchEvents(query: string): Promise<SearchResult[]>;
  searchSessions(query: string): Promise<SessionSearchResult[]>;
}

export function createSearchOperations(backend: SQLiteBackend): SearchOperations {
  return {
    async searchEvents(query) {
      // Move implementation here
    },
    async searchSessions(query) {
      // Move implementation here
    }
  };
}
```

**Step 2**: Build and test (should pass - new file, not used yet)
```bash
bun run build && bun test
```

**Step 3**: Update EventStore to use extracted module
```typescript
// In event-store.ts
import { createSearchOperations, type SearchOperations } from './search-ops.js';

export class EventStore {
  private searchOps: SearchOperations;

  constructor(backend: SQLiteBackend) {
    this.searchOps = createSearchOperations(backend);
  }

  // Delegate to extracted module
  async searchEvents(query: string) {
    return this.searchOps.searchEvents(query);
  }
}
```

**Step 4**: Build and test (MUST pass with same test count)
```bash
bun run build && bun test
bun test event-store  # Run event store tests specifically
```

**Step 5**: Delete old implementation from EventStore (now using delegation)

**Step 6**: Final verification
```bash
bun run build && bun test
# iOS smoke test
```

**Step 7**: Commit single extraction
```bash
git commit -m "Extract search operations from event-store.ts

- Creates search-ops.ts with SearchOperations interface
- EventStore delegates to extracted module
- All tests passing, public API unchanged"
```

### 5.4 Facade Pattern Preservation

**CRITICAL**: EventStore class MUST keep all existing method signatures.

```typescript
// BEFORE (monolithic)
class EventStore {
  searchEvents(query: string) { /* 50 lines of impl */ }
}

// AFTER (facade)
class EventStore {
  searchEvents(query: string) {
    return this.searchOps.searchEvents(query);  // 1 line delegation
  }
}
```

External code sees NO change. Internal implementation is modular.

### 5.5 Extraction Commits (One Per Cluster)

- Commit 1: "Extract search operations from event-store"
- Commit 2: "Extract workspace operations from event-store"
- Commit 3: "Extract branch operations from event-store"
- Commit 4: "Extract message reconstruction from event-store"
- Commit 5: "Extract session operations from event-store"

### 5.6 Post-Split Verification

```bash
# Compare line counts
wc -l packages/agent/src/events/event-store.ts
# Should be significantly smaller (target: <500 lines)

# Verify all tests still pass
bun test

# Verify no new circular dependencies
npx madge --circular packages/agent/src/events/

# Full iOS verification
```

### 5.7 Rollback Plan

If any extraction causes issues:
```bash
git revert HEAD  # Revert single extraction
# Previous extractions remain
# Skip problematic cluster
```

**Phase 5 Complete When**:
- [ ] event-store.ts reduced to facade (~500 lines or less)
- [ ] All operations in focused modules
- [ ] All tests pass
- [ ] Public API unchanged
- [ ] iOS app works

---

## Phase 6: Unify Content Processing (Medium Risk)

**Goal**: Single source of truth for content normalization and truncation.

### Current Problem
Content processing logic in:
1. `utils/content-normalizer.ts` - Main implementation
2. `agent/compaction-handler.ts` - Uses normalizer + has own logic
3. `orchestrator/agent-event-handler.ts` - Duplicates some truncation logic

### 6.1 Consolidate in content-normalizer
Move ALL content processing to `utils/content-normalizer.ts`:
- `normalizeContentBlock()`
- `truncateString()`
- `MAX_TOOL_INPUT_SIZE`, `MAX_TOOL_RESULT_SIZE` constants
- Any streaming content normalization

### 6.2 Update consumers to use single source
- `agent/compaction-handler.ts` - Import from content-normalizer
- `orchestrator/agent-event-handler.ts` - Import from content-normalizer
- Remove duplicated constants/logic

**Verification**:
```bash
bun run build && bun test
bun test compaction agent-event
```

**Commit**: "Unify content processing in single content-normalizer module"

---

## Phase 7: Clean Up Types Module (Low Risk)

**Goal**: Move domain-specific types to their owning modules.

### 7.1 Relocate domain types
```
src/types/events.ts → src/events/types.ts (if not already there)
src/types/tools.ts → Keep (used broadly)
src/types/messages.ts → Keep (used broadly)
src/types/ask-user-question.ts → src/tools/ask-user-question-types.ts
```

### 7.2 Update types/index.ts
- Re-export from new locations for backwards compatibility
- Add deprecation comments for moved types

**Verification**:
```bash
bun run build && bun test
```

**Commit**: "Relocate domain-specific types to owning modules"

---

## Verification Strategy

### After Each Phase
```bash
# From project root
bun run build && bun test
```

### Final Verification
```bash
# Full test suite
bun test

# Verify no circular dependencies
npx madge --circular packages/agent/src/index.ts

# Count source lines (should decrease)
find packages/agent/src -name "*.ts" -not -name "*.test.ts" | xargs wc -l
```

---

## Risk Assessment

| Phase | Risk | Mitigation |
|-------|------|------------|
| 1. Single-file dirs | Low | Simple moves, grep for imports |
| 2. Circular imports | Low | Direct imports, no API change |
| 3. Tracker base | Medium | Preserve public API exactly |
| 4. RPC consolidation | High | Extensive testing, gradual migration |
| 5. Event store split | High | Facade pattern preserves API |
| 6. Content processing | Medium | Centralize, don't change behavior |
| 7. Types cleanup | Low | Re-export for compatibility |

---

## Success Criteria

### Hard Requirements (Must Have)
- [ ] **ZERO test regressions** - Exact same test count passing (3031)
- [ ] **Build succeeds** - `bun run build` clean
- [ ] **iOS app works** - All smoke tests pass after each phase
- [ ] **No circular dependencies** - `madge --circular` reports none
- [ ] **Atomic commits** - Each change independently revertable

### Soft Goals (Should Have)
- [ ] Single-file directories eliminated (5 modules consolidated)
- [ ] Tracker pattern deduplicated (~300 lines removed)
- [ ] RPC layer simplified (if investigation supports it)
- [ ] Event store split into focused modules
- [ ] Content processing unified
- [ ] Clear module ownership for all types

### Metrics to Track
| Metric | Before | After | Change |
|--------|--------|-------|--------|
| Test count | 3031 | 3031 | 0 (must be zero) |
| Source files | TBD | TBD | Slight decrease expected |
| Lines of code | TBD | TBD | Decrease expected |
| Top-level directories | TBD | TBD | -5 expected |
| Largest file (lines) | TBD | TBD | Decrease expected |

---

## Global Rollback Strategy

### If Tests Start Failing

```bash
# 1. STOP immediately
# 2. Check what changed
git diff HEAD~1

# 3. If cause is obvious, fix it
# 4. If cause is unclear, revert
git revert HEAD

# 5. Re-run tests to confirm revert worked
bun run build && bun test
```

### If iOS App Breaks

```bash
# 1. STOP - this is a regression
# 2. Revert to last known good state
git revert HEAD

# 3. Restart server
# 4. Verify iOS app works

# 5. Investigate what the change broke before retrying
```

### If Stuck or Uncertain

**DO NOT push forward with uncertainty.**

Options:
1. Revert to last known good state
2. Ask for help/clarification
3. Skip the current sub-task and document why
4. Take a break and revisit with fresh eyes

### Emergency Full Rollback

If multiple phases have issues and state is confused:

```bash
# Find the last known good commit
git log --oneline -20

# Hard reset to that commit
git reset --hard <good-commit-hash>

# Verify
bun run build && bun test
```

---

## Files Modified Summary

### Deleted Directories
- `src/artifacts/` → merged into `productivity/`
- `src/features/` → merged into `settings/`
- `src/memory/` → merged into `types/`
- `src/tmux/` → merged into `session/`
- `src/subagents/` → merged into `tools/`
- `src/gateway/rpc/adapters/` → removed (consolidated into handlers)

### New Files
- `src/utils/event-sourced-tracker.ts` - Base tracker class
- `src/events/session-ops.ts` - Extracted from event-store
- `src/events/branch-ops.ts` - Extracted from event-store
- `src/events/message-reconstruction.ts` - Extracted from event-store

### Significantly Modified
- `src/events/event-store.ts` - Reduced from 41K to ~500 lines (facade)
- `src/rpc/handlers/*.ts` - Direct orchestrator calls
- `src/index.ts` - Updated re-exports
