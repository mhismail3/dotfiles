# Clauset Enhanced Features Plan: Interaction Timeline, Diffs, Search & Analytics

## Overview

This plan revises the original feature proposal based on the current state of the codebase, particularly the recent robustness improvements (Phases 1-4) that added reliable streaming, connection state management, terminal dimension negotiation, and Safari workarounds.

**Key Insight**: The existing infrastructure provides a solid foundation - we should build upon it rather than replace it.

---

## Current State Summary

### What Already Exists
- **Database**: SQLite with `sessions` table, semi-manual migrations
- **Activity Tracking**: `RecentAction` objects (last 5) parsed from terminal output
- **Cost/Token Tracking**: Per-session totals (`total_cost_usd`, `input_tokens`, `output_tokens`)
- **Reliable Streaming**: Sequence-numbered chunks, ACKs, gap recovery
- **Connection Resilience**: 8-state machine, iOS lifecycle handling, Safari workarounds
- **Hook Types**: Defined but not fully integrated for authoritative event capture
- **WebSocket Events**: `ActivityUpdate` broadcasts to dashboard in real-time

### What's Missing
- Persistent interaction history (currently only last 5 actions)
- File snapshot storage and diff computation
- Full-text search capabilities
- Analytics aggregation
- Rollback functionality

---

## Revised Implementation Phases

### Phase 1: Database Schema & Migrations

**Goal**: Add new tables while preserving existing data and patterns.

#### New Tables

```sql
-- 1. Interactions: Full history of prompt→response cycles
CREATE TABLE interactions (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    sequence_number INTEGER NOT NULL,
    user_prompt TEXT NOT NULL,
    assistant_summary TEXT,
    started_at TEXT NOT NULL,
    ended_at TEXT,
    cost_delta_usd REAL DEFAULT 0,
    input_tokens_delta INTEGER DEFAULT 0,
    output_tokens_delta INTEGER DEFAULT 0,
    UNIQUE(session_id, sequence_number)
);

-- 2. Tool Invocations: Detailed tool call log per interaction
CREATE TABLE tool_invocations (
    id TEXT PRIMARY KEY,
    interaction_id TEXT NOT NULL REFERENCES interactions(id) ON DELETE CASCADE,
    tool_name TEXT NOT NULL,
    tool_input TEXT,              -- JSON
    tool_output_preview TEXT,     -- First 1KB
    is_error BOOLEAN DEFAULT FALSE,
    file_path TEXT,               -- For file operations
    timestamp TEXT NOT NULL
);

-- 3. File Snapshots: Point-in-time file content (metadata)
CREATE TABLE file_snapshots (
    id TEXT PRIMARY KEY,
    interaction_id TEXT NOT NULL REFERENCES interactions(id) ON DELETE CASCADE,
    file_path TEXT NOT NULL,
    content_hash TEXT NOT NULL,   -- SHA256
    snapshot_type TEXT NOT NULL,  -- 'before' or 'after'
    file_size INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    UNIQUE(interaction_id, file_path, snapshot_type)
);

-- 4. File Contents: Deduplicated content storage
CREATE TABLE file_contents (
    content_hash TEXT PRIMARY KEY,
    content BLOB NOT NULL,        -- zstd compressed
    original_size INTEGER NOT NULL,
    created_at TEXT NOT NULL
);

-- 5. FTS Indexes
CREATE VIRTUAL TABLE interactions_fts USING fts5(
    user_prompt, assistant_summary,
    content='interactions', content_rowid='rowid'
);
```

**Files to Modify**:
- `crates/clauset-core/src/db.rs`: Add tables, migrations (same pattern as existing)
- `crates/clauset-types/src/lib.rs`: Add `Interaction`, `ToolInvocation`, `FileSnapshot` structs

**Migration Strategy**: Use existing column-existence-check pattern for backward compatibility.

---

### Phase 2: Interaction Capture Engine

**Goal**: Capture full interaction lifecycle, building on existing activity parsing.

#### Approach: Hook Integration (Preferred)

The hook system (`HookEventPayload` in `hooks.rs`) provides authoritative event data:
- `PreToolUse`: Tool about to execute (capture "before" snapshot)
- `PostToolUse`: Tool completed (capture "after" snapshot, record invocation)
- `UserPromptSubmit`: User sent input (start interaction)
- `Stop`: Claude finished responding (end interaction)

**New Module**: `crates/clauset-core/src/interaction.rs`

```rust
pub struct InteractionTracker {
    current_interaction: Option<ActiveInteraction>,
    pending_snapshots: HashMap<String, PendingSnapshot>,
    db: Arc<SessionStore>,
}

impl InteractionTracker {
    pub async fn on_hook_event(&mut self, event: HookEventPayload);
    pub async fn start_interaction(&mut self, session_id: Uuid, prompt: String);
    pub async fn record_tool(&mut self, tool: ToolInvocation);
    pub async fn capture_file_before(&mut self, path: &Path) -> Result<()>;
    pub async fn capture_file_after(&mut self, path: &Path) -> Result<()>;
    pub async fn end_interaction(&mut self, stats: SessionStats) -> Result<Interaction>;
}
```

**Integration Points**:
- Add `/api/hooks` endpoint to receive Claude Code hook events
- Wire `InteractionTracker` into `SessionManager`
- Emit new WebSocket events for real-time updates

**New WebSocket Messages**:
```rust
InteractionStarted { interaction_id, sequence, prompt_preview },
InteractionCompleted { interaction_id, summary, cost_delta, files_changed },
ToolRecorded { interaction_id, tool_name, file_path },
```

**Files to Modify**:
- `crates/clauset-core/src/interaction.rs` (NEW)
- `crates/clauset-core/src/session.rs`: Integrate tracker
- `crates/clauset-server/src/main.rs`: Add `/api/hooks` endpoint
- `crates/clauset-types/src/ws.rs`: Add new message types

---

### Phase 3: Diff Engine

**Goal**: Compute diffs between any two file snapshots.

#### Implementation

```rust
// crates/clauset-core/src/diff.rs (NEW)

pub struct DiffRequest {
    pub file_path: String,
    pub from_interaction_id: Uuid,
    pub to_interaction_id: Uuid,
}

pub struct FileDiff {
    pub file_path: String,
    pub hunks: Vec<DiffHunk>,
    pub stats: DiffStats,  // additions, deletions
}

pub fn compute_diff(from: &str, to: &str, context_lines: usize) -> Vec<DiffHunk>;
```

**Dependencies**: Use `similar` crate for diff computation (already Rust-native, no FFI).

**API Endpoints**:
```
GET /api/sessions/{id}/interactions         → List all interactions
GET /api/interactions/{id}                  → Single interaction with tools
GET /api/diff?from={id}&to={id}&file={path} → Compute diff
GET /api/sessions/{id}/files-changed        → Files modified in session
```

**Files to Create/Modify**:
- `crates/clauset-core/src/diff.rs` (NEW)
- `crates/clauset-server/src/main.rs`: Add endpoints

---

### Phase 4: Cross-Session Search

**Goal**: Full-text search across all interactions and file operations.

#### Implementation

```rust
// crates/clauset-core/src/search.rs (NEW)

pub struct SearchQuery {
    pub query: String,
    pub scope: Vec<SearchScope>,  // prompts, files, commands
    pub project_path: Option<String>,
    pub date_range: Option<(DateTime, DateTime)>,
}

pub struct SearchResult {
    pub match_type: String,
    pub session_id: Uuid,
    pub interaction_id: Option<Uuid>,
    pub snippet: String,  // Highlighted match
    pub timestamp: DateTime,
}
```

**API Endpoint**:
```
GET /api/search?q={query}&scope={all|prompts|files}&project={path}
```

**SQLite FTS5**: Use triggers to keep FTS index in sync with `interactions` table.

---

### Phase 5: Cost Analytics

**Goal**: Aggregate cost data across sessions, projects, time periods.

#### Implementation

```rust
// crates/clauset-core/src/analytics.rs (NEW)

pub struct CostAnalytics {
    pub total_cost: f64,
    pub by_project: Vec<ProjectCost>,
    pub by_model: Vec<ModelCost>,
    pub by_day: Vec<DailyCost>,
}

pub async fn get_analytics(
    db: &SessionStore,
    date_range: Option<(DateTime, DateTime)>,
) -> Result<CostAnalytics>;
```

**API Endpoint**:
```
GET /api/analytics?from={date}&to={date}
```

**Note**: Build on existing `total_cost_usd`, `input_tokens`, `output_tokens` in sessions table.

---

### Phase 6: Frontend - Timeline View

**Goal**: Interactive timeline of all interactions within a session.

#### Component Structure

```
frontend/src/
├── pages/
│   └── SessionTimeline.tsx (NEW)
├── components/
│   ├── timeline/
│   │   ├── InteractionCard.tsx (NEW)
│   │   └── TimelineFilters.tsx (NEW)
├── stores/
│   └── interactions.ts (NEW)
└── lib/
    └── api.ts (extend)
```

#### InteractionCard Features
- Expandable prompt text
- Tool invocation list with icons (Read, Edit, Write, Bash, etc.)
- Files changed badges (tap to view diff)
- Cost/token delta display
- Relative timestamp

#### Real-time Updates
- Use existing WebSocket infrastructure
- Subscribe to `InteractionStarted`, `InteractionCompleted`, `ToolRecorded`
- Update timeline reactively via Solid.js signals

---

### Phase 7: Frontend - Diff Viewer

**Goal**: Mobile-optimized diff viewing with any-to-any comparison.

#### Component Structure

```
frontend/src/components/diff/
├── DiffViewer.tsx (NEW)      - Unified diff with syntax highlighting
├── CompareModal.tsx (NEW)    - Select two interactions to compare
└── FileChangeSummary.tsx (NEW) - List of changed files
```

#### Features
- Unified diff view (mobile-friendly single column)
- Syntax highlighting via highlight.js or Prism
- Collapsible hunks
- Swipe navigation between files
- Compare any two interactions via dropdown selectors

---

### Phase 8: Frontend - Search

**Goal**: Global search across all sessions.

#### Component Structure

```
frontend/src/components/
└── SearchModal.tsx (NEW)
```

#### Features
- Filter chips: All | Prompts | Files | Commands
- Project filter
- Highlighted search results
- Tap result to navigate to session/interaction
- Debounced search with loading state

---

### Phase 9: Frontend - Analytics Dashboard

**Goal**: Visualize cost and usage metrics.

#### Component Structure

```
frontend/src/pages/
└── Analytics.tsx (NEW)
```

#### Features
- Total cost display (week/month/all-time)
- Daily spending chart (simple bar chart)
- Breakdown by project
- Breakdown by model
- Token efficiency metrics

**Mobile Consideration**: Use simple, touch-friendly visualizations. Avoid complex chart libraries.

---

### Phase 10: Rollback Feature

**Goal**: Restore files to state before a specific interaction.

#### Implementation

**For Git Repos**:
1. Use existing git stash or lightweight tags
2. Store reference in interaction record
3. Rollback = checkout that state

**For Non-Git**:
1. Use file snapshots already captured
2. Restore all 'before' snapshots from target interaction

**API Endpoint**:
```
POST /api/interactions/{id}/rollback
```

**UI**:
- Add "Undo" button to InteractionCard
- Confirmation modal showing affected files
- Preview of what will change

---

## Implementation Order (Revised)

### Sprint 1: Foundation (Phases 1-2)
1. Database schema migrations
2. Interaction tracker module
3. Hook endpoint integration
4. File snapshot capture with deduplication

### Sprint 2: Backend Features (Phases 3-5)
5. Diff computation module
6. Search with FTS5
7. Analytics queries
8. API endpoints for all features

### Sprint 3: Frontend Timeline & Diffs (Phases 6-7)
9. Interactions store
10. Timeline view page
11. InteractionCard component
12. DiffViewer component
13. CompareModal component

### Sprint 4: Frontend Search, Analytics & Rollback (Phases 8-10)
14. SearchModal component
15. Analytics page
16. Rollback API + UI

---

## Critical Files Summary

### Backend (Rust)
| File | Changes |
|------|---------|
| `crates/clauset-core/src/db.rs` | New tables, migrations, FTS triggers |
| `crates/clauset-core/src/interaction.rs` | **NEW** - Interaction tracker |
| `crates/clauset-core/src/diff.rs` | **NEW** - Diff computation |
| `crates/clauset-core/src/search.rs` | **NEW** - FTS search |
| `crates/clauset-core/src/analytics.rs` | **NEW** - Cost analytics |
| `crates/clauset-types/src/lib.rs` | New structs |
| `crates/clauset-types/src/ws.rs` | New WebSocket messages |
| `crates/clauset-server/src/main.rs` | New API endpoints, hook handler |

### Frontend (SolidJS)
| File | Changes |
|------|---------|
| `frontend/src/pages/SessionTimeline.tsx` | **NEW** - Timeline view |
| `frontend/src/pages/Analytics.tsx` | **NEW** - Cost dashboard |
| `frontend/src/components/timeline/InteractionCard.tsx` | **NEW** |
| `frontend/src/components/diff/DiffViewer.tsx` | **NEW** |
| `frontend/src/components/diff/CompareModal.tsx` | **NEW** |
| `frontend/src/components/SearchModal.tsx` | **NEW** |
| `frontend/src/stores/interactions.ts` | **NEW** |
| `frontend/src/lib/api.ts` | Extended with new endpoints |

---

## Testing & Verification

### Per-Phase Testing
1. Run existing tests to ensure no regressions
2. Manual testing on iPhone Safari (primary target)
3. Verify WebSocket real-time updates work correctly
4. Check database migrations run cleanly

### End-to-End Verification
1. Create session, send 3-4 prompts that edit files
2. View timeline with all interactions
3. Compare diffs between interaction #1 and #3
4. Search for a term in prompts
5. View cost analytics
6. Rollback to before interaction #2, verify files restored

---

## Open Questions

1. **Hook Integration**: Should we use Claude Code hooks (most reliable) or continue parsing terminal output (simpler, already works)?

2. **File Snapshot Scope**: Capture ALL files touched (Read/Write/Edit) or only modified files (Write/Edit)?

3. **Storage Limits**: What retention policy for old interactions and snapshots?

4. **Analytics Granularity**: Per-interaction cost deltas require hook integration. Is session-level sufficient initially?

5. **Rollback Scope**: Should rollback affect git working tree or only non-git files?
