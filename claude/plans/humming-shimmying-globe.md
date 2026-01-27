# Things 3 CLI - Test-Driven Development Plan

## Overview

Create a comprehensive standalone CLI tool (`things3`) for complete Things 3 interaction with robust rollback support.

**Location:** `~/Downloads/projects/things3-cli/`
**Binary destination:** `~/.tron/mods/things3`

**Design Principles:**
- **Test-first**: Write failing tests before any implementation
- **Verbose by default**: Every command shows exactly what happened
- **Structured output**: JSON output option for programmatic use
- **Safe**: Rollback support for all destructive operations

---

## TDD Methodology

For each component, follow strict **Red → Green → Refactor**:

1. **RED**: Write failing tests that define expected behavior
2. **GREEN**: Write minimal code to make tests pass
3. **REFACTOR**: Clean up while keeping tests green

### Testing Strategy

| Layer | Test Type | Mocking Strategy |
|-------|-----------|------------------|
| URL Builder | Unit | None - pure functions |
| Rate Limiter | Unit | Mock timers |
| Auth | Unit | Temp directories |
| Output | Unit | Capture stdout |
| Database | Integration | In-memory SQLite (`:memory:`) |
| AppleScript | Integration | Mock `exec` |
| URL Executor | Integration | Mock `exec` |
| Services | Integration | Mock dependencies |
| Commands | Integration | Mock services |

---

## Project Structure

```
~/Downloads/projects/things3-cli/
├── package.json
├── tsconfig.json
├── .gitignore
│
├── src/
│   ├── index.ts
│   ├── cli.ts
│   ├── config.ts
│   ├── core/
│   │   ├── url-builder.ts
│   │   ├── url-executor.ts
│   │   ├── applescript.ts
│   │   ├── auth.ts
│   │   ├── rate-limiter.ts
│   │   └── output.ts
│   ├── db/
│   │   ├── connection.ts
│   │   ├── migrations.ts
│   │   └── snapshot-repo.ts
│   ├── services/
│   │   ├── snapshot-manager.ts
│   │   └── things-client.ts
│   ├── commands/
│   │   └── [14 command files]
│   └── types/
│       ├── things.ts
│       ├── snapshot.ts
│       └── output.ts
│
├── tests/
│   ├── setup.ts                    # Test utilities
│   ├── core/
│   │   ├── url-builder.test.ts
│   │   ├── rate-limiter.test.ts
│   │   ├── auth.test.ts
│   │   ├── output.test.ts
│   │   ├── url-executor.test.ts
│   │   └── applescript.test.ts
│   ├── db/
│   │   ├── connection.test.ts
│   │   ├── migrations.test.ts
│   │   └── snapshot-repo.test.ts
│   ├── services/
│   │   ├── snapshot-manager.test.ts
│   │   └── things-client.test.ts
│   └── commands/
│       └── [14 command test files]
│
└── dist/
    └── things3
```

---

## Implementation Phases (TDD Order)

### Phase 1: Project Setup
1. Create directory structure
2. `package.json` with test dependencies
3. `tsconfig.json`, `.gitignore`
4. `tests/setup.ts` - test utilities
5. Type definitions (`src/types/*.ts`)

### Phase 2: URL Builder (Pure Functions)
**Tests first:** `tests/core/url-builder.test.ts`
```
- buildAddTodoUrl() all parameter combinations
- buildAddProjectUrl() all parameters
- buildUpdateUrl() all parameters
- buildUpdateProjectUrl() all parameters
- buildShowUrl() lists and items
- buildSearchUrl() with/without query
- buildJsonUrl() bulk operations
- buildCompleteUrl() / buildCancelUrl()
- Special characters encoding
- Empty/null value handling
```
**Then implement:** `src/core/url-builder.ts`

### Phase 3: Rate Limiter
**Tests first:** `tests/core/rate-limiter.test.ts`
```
- Allows operations under 250 limit
- Blocks when limit reached
- Resets after 10s window
- getWaitTime() returns correct delay
- acquire() waits appropriately
- Concurrent calls handled correctly
```
**Then implement:** `src/core/rate-limiter.ts`

### Phase 4: Auth Token Management
**Tests first:** `tests/core/auth.test.ts`
```
- getAuthToken() null when missing
- getAuthToken() returns token
- setAuthToken() creates directory
- setAuthToken() correct permissions
- clearAuthToken() removes file
- hasAuthToken() correct boolean
- maskToken() masks correctly
- requireAuthToken() throws when missing
```
**Then implement:** `src/core/auth.ts`

### Phase 5: Output Formatting
**Tests first:** `tests/core/output.test.ts`
```
- Text output formatting
- JSON output formatting
- Table formatting
- Color on/off handling
- Quiet mode suppression
- Snapshot info formatting
```
**Then implement:** `src/core/output.ts`

### Phase 6: Database Layer
**Tests first:** `tests/db/*.test.ts`
```
connection.test.ts:
- Creates file if missing
- Returns same instance
- withTransaction() commits
- withTransaction() rolls back on error

migrations.test.ts:
- Creates all tables
- Creates all indexes
- Idempotent (safe to run multiple times)

snapshot-repo.test.ts:
- generateSnapshotId() format
- createSnapshot() inserts
- addSnapshotCreated() links
- addSnapshotModified() stores JSON
- addSnapshotStatus() records change
- getSnapshot() null for missing
- getSnapshot() correct data
- getSnapshotDetails() includes relations
- listSnapshots() pagination
- listSnapshots() status filter
- updateSnapshotStatus()
- deleteSnapshot() cascades
- purgeOldSnapshots()
```
**Then implement:** `src/db/*.ts`

### Phase 7: URL Executor
**Tests first:** `tests/core/url-executor.test.ts`
```
- executeUrl() calls `open` correctly
- executeUrl() returns success
- executeUrl() returns error on failure
- executeUrl() respects rate limiter
- isThingsInstalled() detection
- isThingsRunning() detection
```
**Then implement:** `src/core/url-executor.ts`

### Phase 8: AppleScript Queries
**Tests first:** `tests/core/applescript.test.ts`
```
- getThingsVersion() parses version
- queryList() returns items
- queryById() returns item or null
- queryByTag() filters correctly
- queryProject() returns items
- getAllProjects() returns all
- getAllAreas() returns all
- Error handling
```
**Then implement:** `src/core/applescript.ts`

### Phase 9: Snapshot Manager Service
**Tests first:** `tests/services/snapshot-manager.test.ts`
```
- createAddSnapshot() correct records
- createUpdateSnapshot() captures state
- createCompleteSnapshot() records status
- rollbackAddSnapshot() cancels items
- rollbackUpdateSnapshot() restores state
- Partial rollback failure handling
```
**Then implement:** `src/services/snapshot-manager.ts`

### Phase 10: Things Client Service
**Tests first:** `tests/services/things-client.test.ts`
```
- addTodo() builds URL, executes
- addProject() builds URL, executes
- updateTodo() requires auth
- updateProject() requires auth
- completeTodo() marks complete
- cancelTodo() marks canceled
- show() navigates correctly
- search() opens search
- bulkJson() handles array
```
**Then implement:** `src/services/things-client.ts`

### Phase 11: Commands (in order of complexity)
For each command, **tests first** then implementation:

1. **show** - simplest, no state
2. **search** - simple, no state
3. **version** - read-only
4. **auth** - setup/set/show/clear/test
5. **add** - creates snapshot
6. **add-project** - creates snapshot
7. **update** - requires auth, snapshot
8. **update-project** - requires auth, snapshot
9. **complete** - requires auth, snapshot
10. **cancel** - warning about irreversibility
11. **query** - read-only, filters
12. **json** - bulk, complex snapshot
13. **snapshots** - list/show/delete/purge
14. **rollback** - executes rollback

### Phase 12: CLI Integration
**Tests first:** `tests/cli.test.ts`
```
- All commands registered
- Global options work
- Help text correct
- Version correct
- Unknown commands error
```
**Then implement:** `src/cli.ts`, `src/index.ts`

### Phase 13: Build & Install
1. Build binary: `bun run build`
2. Run all tests: `bun test`
3. Install to `~/.tron/mods/`

---

## Test Utilities (tests/setup.ts)

```typescript
// Temporary directory management
export function createTempDir(): string
export function cleanupTempDir(path: string): void

// In-memory database for tests
export function createTestDatabase(): Database

// Output capture
export function captureOutput(fn: () => void): { stdout: string, stderr: string }

// Mock exec for AppleScript/URL tests
export function mockExec(responses: Map<string, string>): void
export function resetExecMock(): void

// Mock filesystem
export function mockFs(files: Map<string, string>): void
```

---

## Storage Locations

| Data | Location |
|------|----------|
| Auth token | `~/.tron/things3/auth-token` |
| Snapshots DB | `~/.tron/things3/snapshots.db` |
| Config | `~/.tron/things3/config.json` |
| Binary | `~/.tron/mods/things3` |

---

## Database Schema

```sql
CREATE TABLE snapshots (
  id TEXT PRIMARY KEY,
  description TEXT NOT NULL,
  operation_type TEXT NOT NULL,
  command TEXT NOT NULL,
  created_at TEXT DEFAULT (datetime('now')),
  rolled_back_at TEXT,
  status TEXT DEFAULT 'active'
);

CREATE TABLE snapshot_created (
  id INTEGER PRIMARY KEY,
  snapshot_id TEXT REFERENCES snapshots(id) ON DELETE CASCADE,
  things_id TEXT NOT NULL,
  item_type TEXT NOT NULL,
  title TEXT NOT NULL,
  parent_id TEXT
);

CREATE TABLE snapshot_modified (
  id INTEGER PRIMARY KEY,
  snapshot_id TEXT REFERENCES snapshots(id) ON DELETE CASCADE,
  things_id TEXT NOT NULL,
  item_type TEXT NOT NULL,
  previous_state TEXT NOT NULL,
  modified_fields TEXT NOT NULL
);

CREATE TABLE snapshot_status (
  id INTEGER PRIMARY KEY,
  snapshot_id TEXT REFERENCES snapshots(id) ON DELETE CASCADE,
  things_id TEXT NOT NULL,
  item_type TEXT NOT NULL,
  previous_status TEXT NOT NULL,
  new_status TEXT NOT NULL
);
```

---

## Key Commands Reference

| Command | Auth Required | Creates Snapshot |
|---------|---------------|------------------|
| `add` | No | Yes |
| `add-project` | No | Yes |
| `update` | Yes | Yes |
| `update-project` | Yes | Yes |
| `complete` | Yes | Yes |
| `cancel` | Yes | Yes (warning: irreversible) |
| `show` | No | No |
| `search` | No | No |
| `query` | No | No |
| `version` | No | No |
| `json` | For updates | Yes |
| `rollback` | Yes | No |
| `snapshots` | No | No |
| `auth` | No | No |

---

## Verification

### Automated
```bash
bun test                    # All tests pass
bun run typecheck           # No TS errors
bun run build               # Binary builds
```

### Manual Smoke Test
```bash
things3 add "Test" --when today --json
things3 query today
things3 rollback <snapshot-id>
```

---

## Definition of Done

Per component:
- [ ] Tests written and failing (RED)
- [ ] Implementation makes tests pass (GREEN)
- [ ] Code refactored (REFACTOR)
- [ ] No TypeScript errors

Project complete:
- [ ] All tests pass
- [ ] Binary builds
- [ ] Manual smoke test passes
- [ ] Installed to ~/.tron/mods/
