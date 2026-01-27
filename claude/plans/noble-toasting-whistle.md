# Semantic Search for Tron SQLite Database

## Overview

Add vector-based semantic search to Tron's existing SQLite event store, enabling agents to find sessions and events by meaning rather than just keyword matching.

**Current State:** FTS5 full-text search with BM25 scoring (keyword-only)
**Target State:** Hybrid search combining BM25 + vector similarity

---

## What is Semantic Search?

Traditional search (what Tron has now) matches **exact keywords**:
- Query: "authentication" → finds events containing "authentication"
- Query: "login flow" → misses events about "user sign-in process"

Semantic search matches **meaning**:
- Query: "authentication" → finds events about login, sign-in, credentials, OAuth
- Query: "database optimization" → finds events about query performance, indexes, caching

This works by converting text into **embeddings** (dense vectors of 384-1536 numbers) where similar meanings cluster together in vector space.

---

## Current Database Architecture

| Component | Status |
|-----------|--------|
| SQLite + better-sqlite3 | ✅ Exists |
| WAL mode, 64MB cache | ✅ Configured |
| FTS5 tables (events_fts, logs_fts) | ✅ Exists |
| BM25 keyword search | ✅ Works |
| Vector/embedding storage | ❌ Not present |
| Similarity search | ❌ Not present |

**Key files:**
- `packages/agent/src/events/sqlite/database.ts` - connection management
- `packages/agent/src/events/sqlite/migrations/versions/` - schema versions
- `packages/agent/src/events/sqlite/repositories/search.repo.ts` - FTS5 search
- `packages/agent/src/rpc/handlers/search.handler.ts` - search API

---

## Implementation Plan

### Phase 1: Schema & Storage

**New migration: v005-embeddings.ts**

```sql
-- Vector storage per event
CREATE TABLE embeddings (
  id TEXT PRIMARY KEY,
  event_id TEXT NOT NULL UNIQUE,
  session_id TEXT NOT NULL,
  content_hash TEXT NOT NULL,      -- deduplication
  model TEXT NOT NULL,             -- e.g., 'all-MiniLM-L6-v2'
  dimensions INTEGER NOT NULL,     -- 384
  vector BLOB NOT NULL,            -- Float32Array as Buffer
  created_at TEXT NOT NULL
);

-- Session-level aggregated vectors
CREATE TABLE session_embeddings (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL UNIQUE,
  model TEXT NOT NULL,
  dimensions INTEGER NOT NULL,
  vector BLOB NOT NULL,
  event_count INTEGER NOT NULL,
  last_updated_at TEXT NOT NULL
);

-- Background processing queue
CREATE TABLE embedding_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  event_id TEXT NOT NULL UNIQUE,
  session_id TEXT NOT NULL,
  priority INTEGER DEFAULT 0,
  created_at TEXT NOT NULL
);
```

**Storage format:** 384-dim Float32Array → ~1.5KB per event

---

### Phase 2: Embedding Model

**Recommended: Transformers.js + all-MiniLM-L6-v2**

| Factor | Value |
|--------|-------|
| Library | `@xenova/transformers` |
| Model | `Xenova/all-MiniLM-L6-v2` |
| Dimensions | 384 |
| Size | ~23MB (quantized) |
| Runtime | ONNX/WASM (Bun compatible) |
| Inference | ~50-100ms per text |
| API dependency | None (fully local) |

**Why this choice:**
- Pure JS/WASM - no native bindings, works with Bun
- Small vectors (384 dims) - efficient storage
- High quality for semantic similarity tasks
- Zero API costs

---

### Phase 3: Repository Layer

**New file: `embedding.repo.ts`**

```typescript
class EmbeddingRepository extends BaseRepository {
  // Core operations
  store(eventId, sessionId, contentHash, model, vector): string
  storeBatch(embeddings[]): void
  getByEventId(eventId, model): number[] | null

  // Similarity search (cosine)
  findSimilar(queryVector, model, { sessionId?, limit?, minSimilarity? }): VectorSearchResult[]
  findSimilarSessions(queryVector, model, { limit? }): SessionSearchResult[]

  // Queue management
  enqueue(eventId, sessionId, priority): void
  dequeue(limit): { eventId, sessionId }[]
  removeFromQueue(eventIds): void
}
```

---

### Phase 4: Hybrid Search Algorithm

Combine BM25 (keyword) + vector (semantic) using **Reciprocal Rank Fusion**:

```
Score = (bm25Weight × 1/(k + bm25Rank)) + (vectorWeight × 1/(k + vectorRank))
```

**Default weights:** BM25=0.4, Vector=0.6, k=60

Results appearing in **both** searches get 20% boost.

**New file: `hybrid-search.repo.ts`**

```typescript
class HybridSearchRepository {
  search(query, queryVector, options): HybridSearchResult[]
  semanticSearch(queryVector, options): HybridSearchResult[]  // vector-only
}
```

---

### Phase 5: Indexing Pipeline

**Background service: `EmbeddingIndexer`**

1. Hook into event append → queue events for embedding
2. Background worker polls queue every 5s
3. Batch embed texts (20 at a time)
4. Store vectors with content hash deduplication
5. Update session aggregate embeddings

**Events to embed:**
- `message.user` (priority 10)
- `message.assistant` (priority 5)

---

### Phase 6: Search API

**New RPC method: `search.semantic`**

```typescript
interface SemanticSearchParams {
  query: string;
  sessionId?: string;
  workspaceId?: string;
  limit?: number;
  mode?: 'hybrid' | 'semantic' | 'keyword';  // default: hybrid
  minSimilarity?: number;
}
```

**New RPC method: `search.similar_sessions`**

```typescript
interface SimilarSessionsParams {
  query: string;
  limit?: number;
}
```

---

## Files to Create/Modify

| File | Action |
|------|--------|
| `packages/agent/src/events/sqlite/migrations/versions/v005-embeddings.ts` | Create |
| `packages/agent/src/events/sqlite/repositories/embedding.repo.ts` | Create |
| `packages/agent/src/events/sqlite/repositories/hybrid-search.repo.ts` | Create |
| `packages/agent/src/services/embedding-indexer.ts` | Create |
| `packages/agent/src/events/sqlite/facade.ts` | Modify - add embedding repo |
| `packages/agent/src/rpc/handlers/search.handler.ts` | Modify - add semantic handlers |
| `packages/agent/package.json` | Modify - add @xenova/transformers |

---

## Performance Considerations

**Storage estimate:**
- 100K events × 1.5KB = ~150MB embedding data
- Acceptable for SQLite single-file DB

**Search performance:**
- In-memory cosine similarity: O(n) scan
- 100K vectors: ~600ms worst case
- Session-scoped searches much faster (filter first)
- Cache frequently accessed embeddings (LRU, 1000 entries)

**Future optimization:** When sqlite-vec matures for Bun, add vector index for O(log n) ANN search.

---

## Verification Plan

1. **Unit tests** for EmbeddingRepository CRUD and similarity
2. **Integration test** for hybrid search merging
3. **Manual test:**
   - Run several agent sessions with diverse topics
   - Query "find sessions about database optimization"
   - Verify semantic matches (not just keyword)
4. **Build/test:** `bun run build && bun run test`

---

## Dependencies to Add

```json
{
  "@xenova/transformers": "^2.17.0"
}
```

No native bindings - pure WASM, Bun compatible.
