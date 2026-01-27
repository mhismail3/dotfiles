# SQLite Database Optimization Plan

## Summary

Analysis of Tron's SQLite database (`$HOME/.tron/db/`) reveals a solid foundation with WAL mode and reasonable cache settings, but several optimization opportunities exist.

---

## Current State

**Current Schema Version:** v003 (v001: core tables, v002: task_backlog, v003: device_tokens)

**Tables (11 total):**
- Core: workspaces, sessions, events, blobs, branches
- FTS: events_fts, logs_fts
- Logging: logs
- New: task_backlog, device_tokens
- Meta: schema_version

**Pragmas configured:**
- `journal_mode = WAL`
- `busy_timeout = 5000ms`
- `foreign_keys = ON`
- `synchronous = NORMAL`
- `cache_size = -64000` (64MB)

**Missing pragmas:**
- `temp_store = MEMORY` (temp tables in RAM)
- `mmap_size` (memory-mapped I/O)
- `optimize` on close (query planner stats)

---

## Phase 1: Quick Wins (Low Risk, High Impact)

### 1.1 Add Missing Pragmas

**File:** `packages/core/src/events/sqlite/database.ts`

```typescript
// In configurePragmas():
db.pragma('temp_store = MEMORY');      // Temp tables in RAM
db.pragma('mmap_size = 268435456');    // 256MB memory-mapped I/O
db.pragma('wal_autocheckpoint = 2000'); // Better write batching
```

```typescript
// In close():
this.state.db.pragma('optimize'); // Update query planner stats
```

### 1.2 Add Missing Indexes

**File:** `packages/core/src/events/sqlite/migrations/versions/v004-indexes.ts` (NEW)

```sql
-- Tool result matching (used in message reconstruction)
CREATE INDEX IF NOT EXISTS idx_events_tool_call_id
  ON events(tool_call_id) WHERE tool_call_id IS NOT NULL;

-- Blob cleanup (DELETE WHERE ref_count <= 0)
CREATE INDEX IF NOT EXISTS idx_blobs_ref_count
  ON blobs(ref_count) WHERE ref_count <= 0;

-- Sessions by created_at (used in ORDER BY)
CREATE INDEX IF NOT EXISTS idx_sessions_created
  ON sessions(created_at DESC);

-- Message preview optimization
CREATE INDEX IF NOT EXISTS idx_events_message_preview
  ON events(session_id, type, sequence DESC)
  WHERE type IN ('message.user', 'message.assistant');
```

---

## Phase 2: Medium Effort Optimizations

### 2.1 Add FTS Sync Triggers

**Problem:** FTS tables manually synced in code - potential for drift with main tables.

**File:** `packages/core/src/events/sqlite/migrations/versions/v004-indexes.ts`

```sql
-- Auto-sync events to FTS on insert
CREATE TRIGGER IF NOT EXISTS events_fts_insert
AFTER INSERT ON events
BEGIN
  INSERT INTO events_fts (id, session_id, type, content, tool_name)
  VALUES (NEW.id, NEW.session_id, NEW.type,
    CASE WHEN json_valid(NEW.payload)
      THEN COALESCE(json_extract(NEW.payload, '$.content'), '')
      ELSE ''
    END,
    COALESCE(json_extract(NEW.payload, '$.toolName'),
             json_extract(NEW.payload, '$.name'), ''));
END;

-- Auto-sync events FTS on delete
CREATE TRIGGER IF NOT EXISTS events_fts_delete
AFTER DELETE ON events
BEGIN
  DELETE FROM events_fts WHERE id = OLD.id;
END;

-- Auto-sync logs to FTS on insert
CREATE TRIGGER IF NOT EXISTS logs_fts_insert
AFTER INSERT ON logs
BEGIN
  INSERT INTO logs_fts (log_id, session_id, component, message, error_message)
  VALUES (NEW.id, NEW.session_id, NEW.component, NEW.message, NEW.error_message);
END;

-- Auto-sync logs FTS on delete
CREATE TRIGGER IF NOT EXISTS logs_fts_delete
AFTER DELETE ON logs
BEGIN
  DELETE FROM logs_fts WHERE log_id = OLD.id;
END;
```

### 2.2 Covering Index for Event Queries

```sql
-- Avoids table lookup for common getBySession query
CREATE INDEX IF NOT EXISTS idx_events_session_covering
  ON events(session_id, sequence, type, timestamp, parent_id);
```

---

## Phase 3: Data Lifecycle Management

### 3.1 Add Maintenance Service

**File:** `packages/core/src/events/sqlite/maintenance.ts` (new)

```typescript
export class DatabaseMaintenance {
  constructor(private db: Database.Database) {}

  runMaintenance(logRetentionDays = 30): MaintenanceResult {
    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - logRetentionDays);

    // 1. Prune old logs
    this.db.exec(`DELETE FROM logs_fts WHERE log_id IN
      (SELECT id FROM logs WHERE timestamp < '${cutoff.toISOString()}')`);
    const logsPruned = this.db.prepare(
      'DELETE FROM logs WHERE timestamp < ?'
    ).run(cutoff.toISOString()).changes;

    // 2. Clean unreferenced blobs
    const blobsCleaned = this.db.prepare(
      'DELETE FROM blobs WHERE ref_count <= 0'
    ).run().changes;

    // 3. VACUUM if significant deletions
    if (logsPruned + blobsCleaned > 10000) {
      this.db.exec('VACUUM');
    }

    // 4. Update statistics
    this.db.exec('ANALYZE');

    return { logsPruned, blobsCleaned };
  }

  checkpoint(): void {
    this.db.pragma('wal_checkpoint(PASSIVE)');
  }
}
```

---

## Implementation Order

| # | Task | Files | Risk |
|---|------|-------|------|
| 1 | Add pragma optimize on close | database.ts | Very Low |
| 2 | Add temp_store, mmap_size pragmas | database.ts | Low |
| 3 | Create v004 migration with indexes | migrations/versions/v004-indexes.ts | Low |
| 4 | Add FTS triggers to v004 | migrations/versions/v004-indexes.ts | Medium |
| 5 | Create maintenance service | maintenance.ts (new) | Low |
| 6 | Register migration in index.ts | migrations/index.ts | Low |

---

## Files to Modify

1. `packages/core/src/events/sqlite/database.ts` - Pragma changes
2. `packages/core/src/events/sqlite/migrations/versions/v004-indexes.ts` - New migration (v004)
3. `packages/core/src/events/sqlite/migrations/index.ts` - Register v004 migration
4. `packages/core/src/events/sqlite/maintenance.ts` - New maintenance service (optional)
5. `packages/core/src/events/sqlite/facade.ts` - Expose maintenance (optional)

---

## Rollback Strategy

### Risk Analysis

| Change | Risk | Rollback Method | Data Loss |
|--------|------|-----------------|-----------|
| Pragmas | None | Remove lines from database.ts | None |
| New indexes | None | `DROP INDEX IF EXISTS idx_name` | None |
| FTS triggers | Low | `DROP TRIGGER IF EXISTS trigger_name` | None |
| Maintenance service | None | Don't call it / remove file | None |

### Rollback SQL (if needed)

```sql
-- Drop all new indexes (safe, no data loss)
DROP INDEX IF EXISTS idx_events_tool_call_id;
DROP INDEX IF EXISTS idx_blobs_ref_count;
DROP INDEX IF EXISTS idx_sessions_created;
DROP INDEX IF EXISTS idx_events_message_preview;
DROP INDEX IF EXISTS idx_events_session_covering;

-- Drop FTS triggers (reverts to manual sync)
DROP TRIGGER IF EXISTS events_fts_insert;
DROP TRIGGER IF EXISTS events_fts_delete;
DROP TRIGGER IF EXISTS logs_fts_insert;
DROP TRIGGER IF EXISTS logs_fts_delete;

-- Update schema_version (optional - revert migration record)
DELETE FROM schema_version WHERE version = 4;
```

### Key Points

1. **All changes are additive** - no tables modified, no columns changed
2. **Indexes can be dropped instantly** - no rebuild needed
3. **Triggers can be removed** - reverts to existing manual FTS sync (which still works)
4. **Pragmas are runtime-only** - removing them just uses SQLite defaults

### Pre-Implementation Backup

```bash
# Always backup before running migrations
cp ~/.tron/db/tron.db ~/.tron/db/tron.db.backup-$(date +%Y%m%d)
```

---

## Test-Driven Development

### Test Files to Create/Modify

1. **`packages/core/test/events/sqlite/database.test.ts`** (new or extend)
2. **`packages/core/test/events/sqlite/migrations/v004-indexes.test.ts`** (new)
3. **`packages/core/test/events/sqlite/maintenance.test.ts`** (new)

### Test Cases by Phase

#### Phase 1: Pragma Tests

```typescript
// packages/core/test/events/sqlite/database.test.ts
describe('DatabaseConnection pragmas', () => {
  it('should set temp_store to MEMORY', () => {
    const conn = new DatabaseConnection(':memory:');
    const db = conn.open();
    const result = db.pragma('temp_store');
    expect(result[0].temp_store).toBe(2); // 2 = MEMORY
  });

  it('should set mmap_size', () => {
    const conn = new DatabaseConnection(':memory:');
    const db = conn.open();
    const result = db.pragma('mmap_size');
    expect(result[0].mmap_size).toBeGreaterThan(0);
  });

  it('should call optimize on close', () => {
    // Verify no errors thrown
    const conn = new DatabaseConnection(':memory:');
    conn.open();
    expect(() => conn.close()).not.toThrow();
  });
});
```

#### Phase 2: Index Tests

```typescript
// packages/core/test/events/sqlite/migrations/v004-indexes.test.ts
describe('v004 migration - indexes', () => {
  let connection: DatabaseConnection;

  beforeEach(() => {
    connection = new DatabaseConnection(':memory:');
    runMigrations(connection.open());
  });

  it('should create idx_events_tool_call_id index', () => {
    const indexes = connection.getDatabase()
      .prepare("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_events_tool_call_id'")
      .all();
    expect(indexes).toHaveLength(1);
  });

  it('should create idx_blobs_ref_count index', () => {
    const indexes = connection.getDatabase()
      .prepare("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_blobs_ref_count'")
      .all();
    expect(indexes).toHaveLength(1);
  });

  it('should create idx_sessions_created index', () => {
    const indexes = connection.getDatabase()
      .prepare("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_sessions_created'")
      .all();
    expect(indexes).toHaveLength(1);
  });

  it('should create idx_events_message_preview index', () => {
    const indexes = connection.getDatabase()
      .prepare("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_events_message_preview'")
      .all();
    expect(indexes).toHaveLength(1);
  });

  it('should use tool_call_id index in query plan', () => {
    const db = connection.getDatabase();
    const plan = db.prepare(
      "EXPLAIN QUERY PLAN SELECT * FROM events WHERE tool_call_id = 'test'"
    ).all();
    expect(plan.some(p => p.detail?.includes('idx_events_tool_call_id'))).toBe(true);
  });
});
```

#### Phase 3: FTS Trigger Tests

```typescript
describe('v004 migration - FTS triggers', () => {
  it('should auto-insert into events_fts on event insert', async () => {
    const db = connection.getDatabase();
    // Insert an event
    db.prepare(`INSERT INTO events (...) VALUES (...)`).run(...);

    // Verify FTS entry created
    const ftsCount = db.prepare('SELECT COUNT(*) as c FROM events_fts WHERE id = ?').get(eventId);
    expect(ftsCount.c).toBe(1);
  });

  it('should auto-delete from events_fts on event delete', async () => {
    // Insert then delete
    db.prepare('DELETE FROM events WHERE id = ?').run(eventId);

    // Verify FTS entry removed
    const ftsCount = db.prepare('SELECT COUNT(*) as c FROM events_fts WHERE id = ?').get(eventId);
    expect(ftsCount.c).toBe(0);
  });

  it('should extract content from payload for FTS', async () => {
    // Insert event with content payload
    // Search FTS and verify match
  });
});
```

#### Phase 4: Maintenance Service Tests

```typescript
// packages/core/test/events/sqlite/maintenance.test.ts
describe('DatabaseMaintenance', () => {
  describe('runMaintenance', () => {
    it('should prune logs older than retention period', () => {
      // Insert old logs
      // Run maintenance
      // Verify old logs deleted
    });

    it('should clean unreferenced blobs', () => {
      // Insert blob with ref_count = 0
      // Run maintenance
      // Verify blob deleted
    });

    it('should run VACUUM after large deletions', () => {
      // Insert and delete many rows
      // Run maintenance
      // Verify no error (VACUUM ran)
    });

    it('should run ANALYZE after maintenance', () => {
      // Run maintenance
      // Verify sqlite_stat1 updated
    });
  });

  describe('checkpoint', () => {
    it('should run WAL checkpoint without error', () => {
      const maintenance = new DatabaseMaintenance(db);
      expect(() => maintenance.checkpoint()).not.toThrow();
    });
  });
});
```

### Implementation Order (TDD)

| Step | Action |
|------|--------|
| 1 | Write pragma tests → make them fail |
| 2 | Implement pragma changes → tests pass |
| 3 | Write index tests → make them fail |
| 4 | Create v004 migration → tests pass |
| 5 | Write FTS trigger tests → make them fail |
| 6 | Add triggers to v004 → tests pass |
| 7 | Write maintenance tests → make them fail |
| 8 | Implement maintenance service → tests pass |

---

## Verification

1. Run `bun run build && bun run test` after each change
2. Test migration on existing database:
   ```bash
   # Backup first
   cp ~/.tron/db/tron.db ~/.tron/db/tron.db.bak
   ```
3. Verify FTS sync:
   ```sql
   SELECT (SELECT COUNT(*) FROM events) - (SELECT COUNT(*) FROM events_fts) AS drift;
   ```
4. Check new indexes are used:
   ```sql
   EXPLAIN QUERY PLAN SELECT * FROM events WHERE tool_call_id = 'test';
   ```
