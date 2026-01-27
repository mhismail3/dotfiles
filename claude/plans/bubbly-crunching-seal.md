# Plan: Fix Persistent Vitest OOM Error

## Problem Summary

Running `bun run test` consistently fails with:
```
Error: Worker terminated due to reaching memory limit: JS heap out of memory
Serialized Error: { code: 'ERR_WORKER_OUT_OF_MEMORY' }
```

**Key observation**: All 3070 tests pass, but the error occurs AFTER test completion during worker cleanup. This indicates memory accumulation during tests, not a single test failure.

---

## Root Cause Analysis

### PRIMARY CAUSE: Aggressive SQLite Memory Configuration

In `packages/agent/src/events/sqlite/database.ts` (lines 17-21, 145-151):

```typescript
export const DEFAULT_CONFIG = {
  cacheSize: 64000, // 64MB per connection
};

// In configurePragmas():
db.pragma(`cache_size = -${cacheSize}`);  // 64MB cache
db.pragma('temp_store = MEMORY');         // All temp tables in RAM
db.pragma('mmap_size = 268435456');       // 256MB memory-mapped I/O
```

**Memory per EventStore connection**: ~320MB (64MB cache + 256MB mmap)

**EventStore instances in integration tests**: 19 `new EventStore()` calls found in:
- `event-store-enhancements.test.ts`
- `eventstore-integration.test.ts`
- `event-linearization.test.ts` (5 instances!)
- `interrupt-handling.test.ts` (2 instances)
- `model-switch.test.ts` (2 instances)
- `compaction-eventstore-persistence.test.ts` (2 instances)
- Plus 8 more files

**Theoretical peak memory**: 19 × 320MB = **6+ GB** in Vitest workers

The error happening AFTER tests pass confirms memory accumulates during execution and exhausts the heap during worker cleanup/shutdown.

---

## Solution: Test-Aware SQLite Memory Configuration

**File to modify**: `packages/agent/src/events/sqlite/database.ts`

### Change 1: Detect Test Environment

Vitest sets `process.env.VITEST = 'true'` when running tests (per [Vitest Test Environment docs](https://vitest.dev/guide/environment)).

### Change 2: Use Minimal Memory Settings in Tests

```typescript
/**
 * Check if running in test environment
 */
function isTestEnvironment(): boolean {
  return process.env.VITEST === 'true' || process.env.NODE_ENV === 'test';
}

/**
 * Default database configuration values
 */
export const DEFAULT_CONFIG = {
  enableWAL: true,
  busyTimeout: 5000,
  cacheSize: 64000, // 64MB - production
} as const;

/**
 * Test-optimized configuration (minimal memory footprint)
 */
export const TEST_CONFIG = {
  enableWAL: true,
  busyTimeout: 5000,
  cacheSize: 2000, // 2MB - 32x smaller
} as const;

/**
 * Get appropriate config based on environment
 */
export function getDefaultConfig(): typeof DEFAULT_CONFIG {
  return isTestEnvironment() ? TEST_CONFIG : DEFAULT_CONFIG;
}
```

### Change 3: Disable mmap for Test Databases

In `configurePragmas()`:

```typescript
private configurePragmas(db: Database.Database): void {
  const { enableWAL, busyTimeout, cacheSize } = this.state.config;

  // ... existing WAL, timeout, foreign_keys, synchronous settings ...

  // Set cache size
  db.pragma(`cache_size = -${cacheSize}`);

  // Store temp tables in memory
  db.pragma('temp_store = MEMORY');

  // Memory-mapped I/O: disable for tests, enable for production
  const isTest = process.env.VITEST === 'true' || process.env.NODE_ENV === 'test';
  if (isTest) {
    db.pragma('mmap_size = 0');  // Disabled for tests
  } else {
    db.pragma('mmap_size = 268435456');  // 256MB for production
  }
}
```

### Change 4: Update Constructor to Use Test-Aware Config

```typescript
constructor(dbPath: string, config?: Partial<DatabaseConfig>) {
  this.dbPath = dbPath;
  const defaults = getDefaultConfig();
  this.state = {
    db: null,
    initialized: false,
    config: {
      dbPath,
      enableWAL: config?.enableWAL ?? defaults.enableWAL,
      busyTimeout: config?.busyTimeout ?? defaults.busyTimeout,
      cacheSize: config?.cacheSize ?? defaults.cacheSize,
    },
  };
}
```

---

## Memory Impact Analysis

| Setting | Production | Test | Reduction |
|---------|------------|------|-----------|
| `cache_size` | 64MB | 2MB | 32× |
| `mmap_size` | 256MB | 0 | 100% |
| **Per connection** | ~320MB | ~2MB | **160×** |
| **19 connections** | ~6GB | ~38MB | **160×** |

This should completely eliminate the OOM issue while having zero impact on production performance.

---

## Files to Modify

| File | Changes |
|------|---------|
| `packages/agent/src/events/sqlite/database.ts` | Add `isTestEnvironment()`, `TEST_CONFIG`, `getDefaultConfig()`, update constructor, update `configurePragmas()` |

---

## Verification

1. Run `bun run test` - should complete without OOM error
2. Run `bun run test` 3 times consecutively - should be stable
3. All 3070+ tests should still pass
4. Optional: Monitor memory with `top` during test run to confirm reduction

---

## Why This Fix is Robust

1. **Addresses root cause**: Not a workaround, directly fixes the memory allocation issue
2. **Zero production impact**: Only affects test environment
3. **Automatic detection**: No changes needed to test files
4. **Simple implementation**: ~20 lines of code changes
5. **Self-documenting**: Clear constants and comments explain the reasoning

---

## Research Sources

- [Vitest Test Environment Guide](https://vitest.dev/guide/environment) - `process.env.VITEST` detection
- [SQLite PRAGMA cache_size](https://www.sqlite.org/pragma.html#pragma_cache_size)
- [SQLite PRAGMA mmap_size](https://www.sqlite.org/pragma.html#pragma_mmap_size)
