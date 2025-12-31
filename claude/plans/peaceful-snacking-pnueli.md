# Plan: Implement Prefix/Partial Search Matching

## Goal
Enable real-time "search as you type" where partial queries like "Re" match "Read" and "De" matches "Describe".

## Problem Analysis
Current `escape_fts5_query()` wraps queries in double quotes for phrase search:
```rust
format!("\"{}\"", escaped)  // "Re" looks for exact token "re" - doesn't match "Read"
```

FTS5 supports prefix matching with the `*` wildcard operator - we just need to use it.

## Implementation Plan

### Step 1: Update FTS5 Query Escaping (Backend)
**File**: `crates/clauset-core/src/interaction_store.rs`

Change `escape_fts5_query()` to support prefix matching:

```rust
fn escape_fts5_query(query: &str) -> String {
    // Split into tokens and add wildcard suffix to each for prefix matching
    let tokens: Vec<String> = query
        .split_whitespace()
        .filter(|t| !t.is_empty())
        .map(|t| {
            // Escape double quotes and append * for prefix matching
            let escaped = t.replace('"', "\"\"");
            format!("\"{}\"*", escaped)
        })
        .collect();

    if tokens.is_empty() {
        return String::new();
    }

    // Join with AND - all tokens must match (as prefixes)
    tokens.join(" AND ")
}
```

**Behavior**:
- `"Re"` → `"Re"*` → matches Read, Return, Rebuild
- `"describe project"` → `"describe"* AND "project"*` → matches "describe this project"
- `"package.json"` → `"package.json"*` → matches exact and prefixes

### Step 2: Add FTS5 Prefix Indexes (Backend - Schema Migration)
**File**: `crates/clauset-core/src/interaction_store.rs`

Update FTS5 table creation to include prefix indexes for faster prefix queries:

```rust
CREATE VIRTUAL TABLE IF NOT EXISTS interactions_fts USING fts5(
    user_prompt,
    assistant_summary,
    content='interactions',
    content_rowid='rowid',
    prefix='2 3'  -- Index 2 and 3 character prefixes
);

CREATE VIRTUAL TABLE IF NOT EXISTS tool_invocations_fts USING fts5(
    file_path,
    tool_input,
    tool_name,
    content='tool_invocations',
    content_rowid='rowid',
    prefix='2 3'
);
```

**Note**: This requires dropping and recreating FTS tables (one-time migration).

### Step 3: Reduce Minimum Query Length (Frontend)
**File**: `frontend/src/components/interactions/SearchModal.tsx`

Change minimum from 2 characters to 1:
```typescript
// Line ~62: Change from 2 to 1
if (q.trim().length >= 1) {
```

### Step 4: Reduce Debounce for Faster Response (Frontend)
**File**: `frontend/src/components/interactions/SearchModal.tsx`

Optionally reduce debounce from 300ms to 150ms for snappier feel:
```typescript
// Line ~71
debounceTimer = setTimeout(() => { ... }, 150);
```

## Files to Modify
1. `crates/clauset-core/src/interaction_store.rs` - Query escaping + schema
2. `frontend/src/components/interactions/SearchModal.tsx` - Min length + debounce

## Testing Checklist
- [ ] "R" matches Read, Rebuild, Return
- [ ] "Re" matches Read, Return (not Rebuild)
- [ ] "De" matches Describe, Delete, Deploy
- [ ] "package.json" still works (special chars)
- [ ] Multi-word: "describe project" matches "describe this project"
- [ ] Empty/whitespace query returns no results
- [ ] Performance: Search remains fast with 1000+ interactions

## Migration Note
The `prefix='2 3'` option requires recreating FTS tables. Options:
1. **Simple**: Drop and recreate FTS tables (loses nothing - they're virtual indexes)
2. **Safe**: Add migration version check in `create_fts_tables()`

## Estimated Changes
- ~20 lines in interaction_store.rs
- ~2 lines in SearchModal.tsx
