# WorktreeCoordinator Decomposition Plan

## Status: COMPLETED

**Completed:** Commit `aa3262f` - Extract focused handlers from WorktreeCoordinator

**Results:**
- GitExecutor: 138 lines, 29 tests
- WorktreeLifecycle: 181 lines, 12 tests
- MergeHandler: 233 lines, 16 tests
- WorktreeEvents: 152 lines, 10 tests
- types.ts: 132 lines
- Total: 67 new tests, all passing

## Goal

Decompose `packages/agent/src/session/worktree-coordinator.ts` (991 lines) into focused modules while maintaining the same public API. The coordinator currently handles too many concerns: git operations, worktree lifecycle, session tracking, merge strategies, event emission, and recovery.

---

## Current State Analysis

### File Structure (991 lines)

```
worktree-coordinator.ts
├── Types (lines 31-78)
│   └── WorktreeCoordinatorConfig, AcquireOptions, ReleaseOptions, ActiveSession
├── Git Helpers (lines 78-124)
│   ├── pathExists()
│   └── execGit()
├── WorktreeCoordinator Class (lines 124-979)
│   ├── Repository Detection (158-202)
│   │   ├── isGitRepo()
│   │   ├── getRepoRoot()
│   │   ├── getCurrentBranch()
│   │   └── getCurrentCommit()
│   ├── Core Operations (202-400)
│   │   ├── acquire() - 45 lines
│   │   ├── release() - 122 lines
│   │   ├── getWorkingDirectory()
│   │   ├── getActiveSessions()
│   │   └── isSessionActive()
│   ├── Isolation Decision (400-437)
│   │   └── shouldIsolate() - 28 lines
│   ├── Worktree Creation (437-676)
│   │   ├── acquireMainDirectory() - 35 lines
│   │   ├── acquireIsolatedWorktree() - 85 lines
│   │   ├── acquireNonGitDirectory() - 25 lines
│   │   ├── createWorktree() - 45 lines
│   │   ├── branchExists() - 15 lines
│   │   └── removeWorktree() - 40 lines
│   ├── Merge Operations (676-783)
│   │   └── mergeSession() - 107 lines (handles merge/rebase/squash)
│   ├── Event Emission (783-859)
│   │   ├── emitAcquiredEvent()
│   │   ├── emitReleasedEvent()
│   │   ├── emitCommitEvent()
│   │   └── emitMergedEvent()
│   └── Recovery (859-979)
│       ├── recoverOrphanedWorktrees() - 78 lines
│       └── listWorktrees() - 42 lines
└── Factory (979-991)
    └── createWorktreeCoordinator()
```

### Problems

1. **Mixed Abstraction Levels**: Low-level git commands mixed with high-level business logic
2. **Large Methods**: `release()` is 122 lines, `mergeSession()` is 107 lines
3. **Multiple Responsibilities**: Git ops, worktree CRUD, session tracking, merge strategies, events
4. **Difficult to Test**: Hard to test merge strategies without full worktree setup
5. **No Separation of Concerns**: Event emission interleaved with operations

---

## Proposed Architecture

### New Structure

```
session/
├── worktree-coordinator.ts          # Slim coordinator (~250 lines)
├── worktree/
│   ├── types.ts                     # Shared types
│   ├── git-executor.ts              # Low-level git command execution
│   ├── worktree-lifecycle.ts        # Create, remove, list worktrees
│   ├── merge-handler.ts             # Merge/rebase/squash strategies
│   ├── worktree-events.ts           # Event emission
│   ├── __tests__/
│   │   ├── git-executor.test.ts
│   │   ├── worktree-lifecycle.test.ts
│   │   ├── merge-handler.test.ts
│   │   └── worktree-events.test.ts
│   └── index.ts                     # Barrel export
└── working-directory.ts             # Existing (unchanged)
```

### Module Responsibilities

| Module | Responsibility | Est. Lines |
|--------|----------------|------------|
| `types.ts` | Shared interfaces, result types | ~80 |
| `git-executor.ts` | `execGit`, `pathExists`, repo detection | ~120 |
| `worktree-lifecycle.ts` | Create, remove, list, recover worktrees | ~200 |
| `merge-handler.ts` | Merge, rebase, squash strategies | ~150 |
| `worktree-events.ts` | Event emission helpers | ~100 |
| `worktree-coordinator.ts` | Orchestration, session tracking | ~250 |

### Dependency Graph

```
worktree-coordinator.ts
    ├── git-executor.ts (no deps)
    ├── worktree-lifecycle.ts
    │   └── git-executor.ts
    ├── merge-handler.ts
    │   └── git-executor.ts
    └── worktree-events.ts (no deps, receives EventStore)
```

---

## Implementation Phases

### Phase 1: Create Types Module

**Goal**: Extract shared types to break circular dependencies.

**Files**:
- Create `worktree/types.ts`

**Types to Extract**:
```typescript
// From worktree-coordinator.ts
export interface GitExecResult {
  stdout: string;
  stderr: string;
  exitCode: number;
}

export interface WorktreeInfo {
  path: string;
  branch: string;
  sessionId?: string;
  baseCommit?: string;
}

export interface WorktreeAcquireResult {
  path: string;
  branch: string;
  baseCommit: string;
  isolated: boolean;
  forkedFrom?: { sessionId: SessionId; commit: string };
}

export interface MergeResult {
  success: boolean;
  strategy: 'merge' | 'rebase' | 'squash';
  conflicts?: string[];
  error?: string;
}

// Dependencies interface for handlers
export interface WorktreeDeps {
  repoRoot: string;
  config: WorktreeCoordinatorConfig;
}
```

**Verification**:
```bash
bun run build
```

---

### Phase 2: Extract GitExecutor (TDD)

**Goal**: Extract low-level git operations.

**Step 2.1**: Write tests first
```typescript
// worktree/__tests__/git-executor.test.ts
describe('GitExecutor', () => {
  describe('execGit', () => {
    it('should execute git command successfully');
    it('should return stdout and stderr');
    it('should handle command failure');
    it('should respect timeout');
    it('should handle non-Error exceptions');
  });

  describe('pathExists', () => {
    it('should return true for existing path');
    it('should return false for non-existing path');
  });

  describe('isGitRepo', () => {
    it('should return true for git repository');
    it('should return false for non-git directory');
  });

  describe('getRepoRoot', () => {
    it('should return repo root for git directory');
    it('should return null for non-git directory');
  });

  describe('getCurrentBranch', () => {
    it('should return current branch name');
    it('should handle detached HEAD');
  });

  describe('getCurrentCommit', () => {
    it('should return current commit hash');
  });

  describe('branchExists', () => {
    it('should return true for existing branch');
    it('should return false for non-existing branch');
  });
});
```

**Step 2.2**: Implement `git-executor.ts`
```typescript
export class GitExecutor {
  constructor(private defaultTimeout: number = 30000) {}

  async execGit(args: string[], cwd: string, options?: { timeout?: number }): Promise<GitExecResult>;
  async pathExists(path: string): Promise<boolean>;
  async isGitRepo(dir: string): Promise<boolean>;
  async getRepoRoot(dir: string): Promise<string | null>;
  async getCurrentBranch(dir: string): Promise<string>;
  async getCurrentCommit(dir: string): Promise<string>;
  async branchExists(dir: string, branch: string): Promise<boolean>;
}

export function createGitExecutor(timeout?: number): GitExecutor;
```

**Step 2.3**: Run tests
```bash
bun test worktree/__tests__/git-executor.test.ts
```

---

### Phase 3: Extract WorktreeLifecycle (TDD)

**Goal**: Extract worktree CRUD operations.

**Step 3.1**: Write tests first
```typescript
// worktree/__tests__/worktree-lifecycle.test.ts
describe('WorktreeLifecycle', () => {
  describe('createWorktree', () => {
    it('should create worktree with new branch');
    it('should create worktree from specific commit');
    it('should handle existing worktree path');
    it('should return error for invalid commit');
  });

  describe('removeWorktree', () => {
    it('should remove worktree directory');
    it('should optionally delete branch');
    it('should handle non-existing worktree');
    it('should force remove dirty worktree when requested');
  });

  describe('listWorktrees', () => {
    it('should list all worktrees');
    it('should parse worktree info correctly');
    it('should extract session ID from path');
  });

  describe('recoverOrphanedWorktrees', () => {
    it('should find orphaned worktrees');
    it('should clean up orphaned worktrees');
    it('should preserve active session worktrees');
  });
});
```

**Step 3.2**: Implement `worktree-lifecycle.ts`
```typescript
export interface WorktreeLifecycleDeps {
  gitExecutor: GitExecutor;
  repoRoot: string;
  worktreeBaseDir: string;
  branchPrefix: string;
}

export class WorktreeLifecycle {
  constructor(private deps: WorktreeLifecycleDeps) {}

  async createWorktree(path: string, branch: string, baseCommit: string): Promise<void>;
  async removeWorktree(path: string, options?: { deleteBranch?: boolean; force?: boolean }): Promise<void>;
  async listWorktrees(): Promise<WorktreeInfo[]>;
  async recoverOrphanedWorktrees(activeSessions: Set<string>): Promise<void>;
}

export function createWorktreeLifecycle(deps: WorktreeLifecycleDeps): WorktreeLifecycle;
```

**Step 3.3**: Run tests
```bash
bun test worktree/__tests__/worktree-lifecycle.test.ts
```

---

### Phase 4: Extract MergeHandler (TDD)

**Goal**: Extract merge strategy logic.

**Step 4.1**: Write tests first
```typescript
// worktree/__tests__/merge-handler.test.ts
describe('MergeHandler', () => {
  describe('merge', () => {
    it('should perform git merge');
    it('should handle merge conflicts');
    it('should return conflict file list');
  });

  describe('rebase', () => {
    it('should perform git rebase');
    it('should handle rebase conflicts');
    it('should abort on failure');
  });

  describe('squash', () => {
    it('should squash commits into one');
    it('should use provided commit message');
    it('should handle empty diff');
  });

  describe('mergeSession', () => {
    it('should select correct strategy based on options');
    it('should commit changes before merge');
    it('should return detailed result');
  });

  describe('hasUncommittedChanges', () => {
    it('should detect uncommitted changes');
    it('should return false for clean worktree');
  });

  describe('commitChanges', () => {
    it('should commit all changes');
    it('should use provided message');
  });
});
```

**Step 4.2**: Implement `merge-handler.ts`
```typescript
export interface MergeHandlerDeps {
  gitExecutor: GitExecutor;
}

export class MergeHandler {
  constructor(private deps: MergeHandlerDeps) {}

  async merge(worktreePath: string, targetBranch: string): Promise<MergeResult>;
  async rebase(worktreePath: string, targetBranch: string): Promise<MergeResult>;
  async squash(worktreePath: string, targetBranch: string, message: string): Promise<MergeResult>;
  async hasUncommittedChanges(worktreePath: string): Promise<boolean>;
  async commitChanges(worktreePath: string, message: string): Promise<string | null>;

  async mergeSession(
    worktreePath: string,
    targetBranch: string,
    options: { strategy: 'merge' | 'rebase' | 'squash'; commitMessage?: string }
  ): Promise<MergeResult>;
}

export function createMergeHandler(deps: MergeHandlerDeps): MergeHandler;
```

**Step 4.3**: Run tests
```bash
bun test worktree/__tests__/merge-handler.test.ts
```

---

### Phase 5: Extract WorktreeEvents (TDD)

**Goal**: Extract event emission logic.

**Step 5.1**: Write tests first
```typescript
// worktree/__tests__/worktree-events.test.ts
describe('WorktreeEvents', () => {
  describe('emitAcquired', () => {
    it('should emit worktree.acquired event');
    it('should include all required fields');
    it('should handle fork info');
  });

  describe('emitReleased', () => {
    it('should emit worktree.released event');
    it('should include cleanup info');
  });

  describe('emitCommit', () => {
    it('should emit worktree.commit event');
    it('should include commit hash and message');
  });

  describe('emitMerged', () => {
    it('should emit worktree.merged event');
    it('should include merge result');
  });
});
```

**Step 5.2**: Implement `worktree-events.ts`
```typescript
export interface WorktreeEventsDeps {
  eventStore: EventStore;
}

export class WorktreeEvents {
  constructor(private deps: WorktreeEventsDeps) {}

  async emitAcquired(sessionId: SessionId, info: WorktreeAcquireResult): Promise<void>;
  async emitReleased(sessionId: SessionId, info: { path: string; branch: string }): Promise<void>;
  async emitCommit(sessionId: SessionId, info: { hash: string; message: string }): Promise<void>;
  async emitMerged(sessionId: SessionId, result: MergeResult): Promise<void>;
}

export function createWorktreeEvents(deps: WorktreeEventsDeps): WorktreeEvents;
```

**Step 5.3**: Run tests
```bash
bun test worktree/__tests__/worktree-events.test.ts
```

---

### Phase 6: Create Index and Update WorktreeCoordinator

**Goal**: Wire everything together, slim down the coordinator.

**Step 6.1**: Create `worktree/index.ts`
```typescript
export * from './types.js';
export * from './git-executor.js';
export * from './worktree-lifecycle.js';
export * from './merge-handler.js';
export * from './worktree-events.js';
```

**Step 6.2**: Update `worktree-coordinator.ts`
- Import from `./worktree/index.js`
- Replace inline implementations with handler delegations
- Keep session tracking (`activeSessions`, `mainDirectoryOwner`)
- Keep `acquire()` and `release()` as coordination methods
- Keep `shouldIsolate()` as business logic
- Delegate git operations to `GitExecutor`
- Delegate worktree CRUD to `WorktreeLifecycle`
- Delegate merge operations to `MergeHandler`
- Delegate event emission to `WorktreeEvents`

**Step 6.3**: Verify existing tests still pass
```bash
bun test packages/agent/src/session/__tests__/
bun test packages/agent/src/__integration__/worktree
```

---

### Phase 7: Final Verification

**Step 7.1**: Run full test suite
```bash
bun run build && bun run test
```

**Step 7.2**: Verify line counts
```bash
wc -l packages/agent/src/session/worktree-coordinator.ts
wc -l packages/agent/src/session/worktree/*.ts
```

**Expected Results**:
- `worktree-coordinator.ts`: ~250 lines (down from 991)
- `worktree/types.ts`: ~80 lines
- `worktree/git-executor.ts`: ~120 lines
- `worktree/worktree-lifecycle.ts`: ~200 lines
- `worktree/merge-handler.ts`: ~150 lines
- `worktree/worktree-events.ts`: ~100 lines

**Step 7.3**: Commit
```bash
git add -A
git commit -m "Decompose WorktreeCoordinator into focused modules

Extract worktree operations from WorktreeCoordinator (991→250 lines) into 5 modules:

- git-executor.ts: Low-level git command execution
- worktree-lifecycle.ts: Worktree CRUD operations
- merge-handler.ts: Merge/rebase/squash strategies
- worktree-events.ts: Event emission helpers
- types.ts: Shared type definitions

Each module follows TDD with comprehensive tests. WorktreeCoordinator now
acts as a slim orchestrator, delegating to specialized handlers.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Breaking existing tests | Run `worktree-integration.test.ts` after each phase |
| Circular dependencies | Types in separate module, clear dependency graph |
| Git operation failures | Preserve existing error handling, add tests |
| Session state corruption | Keep session tracking in coordinator, don't extract |

---

## Test Coverage Goals

| Module | Target Tests |
|--------|--------------|
| `git-executor.ts` | ~15 tests |
| `worktree-lifecycle.ts` | ~12 tests |
| `merge-handler.ts` | ~15 tests |
| `worktree-events.ts` | ~8 tests |
| **Total New Tests** | **~50 tests** |

---

## Success Criteria

- [ ] All existing worktree tests pass
- [ ] All integration tests pass
- [ ] `worktree-coordinator.ts` reduced to ~250 lines
- [ ] Each new module has comprehensive tests
- [ ] No circular dependencies
- [ ] Build succeeds with zero errors
- [ ] Public API unchanged (createWorktreeCoordinator exports same interface)

---

## Out of Scope

1. Changing the public API of WorktreeCoordinator
2. Modifying WorkingDirectory class
3. Changing event types or payloads
4. Adding new features
