# Clauset Feature Plan: Interaction Timeline, Diffs, Search & Analytics

## Overview
Build a comprehensive interaction tracking system that captures every prompt→response cycle, enables diff viewing between any two points in time, provides cross-session search, and displays cost analytics.

---

## Phase 1: Database Schema & Core Infrastructure

### New Tables

**1. `interactions` table** - Track each prompt→response cycle
```sql
CREATE TABLE interactions (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    sequence_number INTEGER NOT NULL,
    user_prompt TEXT NOT NULL,
    assistant_summary TEXT,          -- Parsed/generated summary of response
    started_at TEXT NOT NULL,
    ended_at TEXT,
    cost_delta_usd REAL DEFAULT 0,
    input_tokens_delta INTEGER DEFAULT 0,
    output_tokens_delta INTEGER DEFAULT 0,
    UNIQUE(session_id, sequence_number)
);
CREATE INDEX idx_interactions_session ON interactions(session_id);
CREATE INDEX idx_interactions_started ON interactions(started_at);
```

**2. `file_snapshots` table** - Point-in-time file content for any-to-any diffs
```sql
-- Snapshot ALL touched files (read, write, edit) for comprehensive comparison
CREATE TABLE file_snapshots (
    id TEXT PRIMARY KEY,
    interaction_id TEXT NOT NULL REFERENCES interactions(id) ON DELETE CASCADE,
    file_path TEXT NOT NULL,
    content_hash TEXT NOT NULL,      -- SHA256 for deduplication
    snapshot_type TEXT NOT NULL,     -- 'before' or 'after'
    created_at TEXT NOT NULL,
    UNIQUE(interaction_id, file_path, snapshot_type)
);
CREATE INDEX idx_snapshots_interaction ON file_snapshots(interaction_id);
CREATE INDEX idx_snapshots_path ON file_snapshots(file_path);

-- Separate content storage with deduplication (same content = same hash = stored once)
-- This makes comprehensive snapshots storage-efficient
CREATE TABLE file_contents (
    content_hash TEXT PRIMARY KEY,
    content BLOB NOT NULL,           -- zstd compressed content
    file_size INTEGER NOT NULL,
    created_at TEXT NOT NULL
);
```

**3. `tool_invocations` table** - Detailed tool call log
```sql
CREATE TABLE tool_invocations (
    id TEXT PRIMARY KEY,
    interaction_id TEXT NOT NULL REFERENCES interactions(id) ON DELETE CASCADE,
    tool_name TEXT NOT NULL,
    tool_input TEXT,                 -- JSON args
    tool_output_preview TEXT,        -- First 1KB of output
    is_error BOOLEAN DEFAULT FALSE,
    file_path TEXT,                  -- For Read/Write/Edit tools
    timestamp TEXT NOT NULL
);
CREATE INDEX idx_tools_interaction ON tool_invocations(interaction_id);
CREATE INDEX idx_tools_name ON tool_invocations(tool_name);
CREATE INDEX idx_tools_file ON tool_invocations(file_path);
```

**4. Full-Text Search indexes**
```sql
CREATE VIRTUAL TABLE interactions_fts USING fts5(
    user_prompt, assistant_summary,
    content='interactions', content_rowid='rowid'
);
CREATE VIRTUAL TABLE tool_invocations_fts USING fts5(
    file_path, tool_input,
    content='tool_invocations', content_rowid='rowid'
);
```

### Files to Modify
- `crates/clauset-core/src/db.rs` - Add new tables, queries, FTS triggers
- `crates/clauset-types/src/lib.rs` - Add Interaction, FileSnapshot, ToolInvocation structs

---

## Phase 2: Interaction Capture Engine

### Capture Points in Buffer Parser

**File:** `crates/clauset-core/src/buffer.rs`

1. **Interaction Start Detection**
   - Triggered when `mark_busy()` is called (user sent input)
   - Create new interaction record with `user_prompt`
   - Snapshot current session stats (cost, tokens) for delta calculation

2. **Tool Invocation Capture**
   - Extend `parse_tool_activity_flexible()` to emit structured events
   - For Read/Write/Edit tools: extract file path
   - For Write/Edit: trigger file snapshot capture

3. **File Snapshot Capture**
   - **Before snapshot:** When Write/Edit tool detected, read current file content
   - **After snapshot:** When tool completes (detect via next tool or ready state)
   - Compress and deduplicate via content hash

4. **Interaction End Detection**
   - Triggered when session transitions to "Ready" state
   - Calculate cost/token deltas
   - Generate summary from tool invocations

### New Module: `crates/clauset-core/src/interaction.rs`
```rust
pub struct InteractionTracker {
    current_interaction: Option<ActiveInteraction>,
    pending_snapshots: HashMap<String, PendingSnapshot>,
}

impl InteractionTracker {
    pub fn start_interaction(&mut self, session_id: Uuid, prompt: String);
    pub fn record_tool(&mut self, tool: ToolInvocation);
    pub fn capture_file_before(&mut self, path: &Path);
    pub fn capture_file_after(&mut self, path: &Path);
    pub fn end_interaction(&mut self, stats: SessionStats) -> Interaction;
}
```

### WebSocket Events
**File:** `crates/clauset-types/src/ws.rs`
```rust
// New server→client messages
InteractionStarted { interaction_id, sequence, prompt_preview },
InteractionCompleted { interaction_id, summary, cost_delta, files_changed: Vec<String> },
ToolRecorded { interaction_id, tool_name, file_path: Option<String> },
```

---

## Phase 3: Diff Engine

### Any-to-Any Diff Computation

**File:** `crates/clauset-core/src/diff.rs`

```rust
pub struct DiffRequest {
    pub file_path: String,
    pub from_interaction_id: Uuid,  // Use 'after' snapshot
    pub to_interaction_id: Uuid,    // Use 'after' snapshot
}

pub struct FileDiff {
    pub file_path: String,
    pub from_interaction: Uuid,
    pub to_interaction: Uuid,
    pub hunks: Vec<DiffHunk>,
    pub stats: DiffStats,  // additions, deletions, changes
}

pub fn compute_diff(from_content: &str, to_content: &str, context: usize) -> Vec<DiffHunk>;
```

### Git Integration for Current State
```rust
// Get file content from git at specific ref
pub fn git_show_file(repo_path: &Path, file_path: &str, ref_name: &str) -> Result<String>;

// Get uncommitted changes (working tree vs HEAD)
pub fn git_diff_working(repo_path: &Path) -> Result<Vec<FileDiff>>;
```

### API Endpoints
**File:** `crates/clauset-server/src/main.rs`

```
GET /api/sessions/{id}/interactions
    → List all interactions with file change summaries

GET /api/interactions/{id}
    → Full interaction detail with tool invocations

GET /api/diff?from={interaction_id}&to={interaction_id}&file={path}
    → Compute diff between two interaction snapshots

GET /api/sessions/{id}/files-changed
    → List all files modified in session with change counts

GET /api/sessions/{id}/git-status
    → Current git status for session's project
```

---

## Phase 4: Cross-Session Search

### Search API
**File:** `crates/clauset-server/src/search.rs`

```rust
pub struct SearchQuery {
    pub query: String,
    pub filters: SearchFilters,
}

pub struct SearchFilters {
    pub search_in: Vec<SearchScope>,  // prompts, files, commands, all
    pub project_path: Option<String>,
    pub date_range: Option<(DateTime, DateTime)>,
    pub model: Option<String>,
}

pub struct SearchResult {
    pub match_type: String,           // "prompt", "file", "command"
    pub session_id: Uuid,
    pub interaction_id: Option<Uuid>,
    pub snippet: String,              // Highlighted match
    pub context: SearchContext,
}
```

### API Endpoint
```
GET /api/search?q={query}&scope={prompts|files|commands|all}&project={path}
```

---

## Phase 5: Cost Analytics

### Analytics Queries
**File:** `crates/clauset-core/src/analytics.rs`

```rust
pub struct CostAnalytics {
    pub total_cost: f64,
    pub by_project: Vec<ProjectCost>,
    pub by_model: Vec<ModelCost>,
    pub by_day: Vec<DailyCost>,
    pub token_efficiency: f64,  // output_tokens / cost
}

pub fn get_analytics(date_range: Option<(DateTime, DateTime)>) -> CostAnalytics;
```

### API Endpoint
```
GET /api/analytics?from={date}&to={date}
```

---

## Phase 6: Frontend - Timeline View

### New Page: Session Timeline
**File:** `frontend/src/pages/SessionTimeline.tsx`

```
┌─────────────────────────────────────┐
│ ← Session Name          [Terminal]  │
├─────────────────────────────────────┤
│ Timeline    Files    Analytics      │  ← Tab bar
├─────────────────────────────────────┤
│ ┌─────────────────────────────────┐ │
│ │ #3 · 2 min ago · $0.12         │ │  ← Interaction card
│ │ "Fix the auth middleware..."    │ │
│ │ ┌────┐ ┌────┐ ┌────┐           │ │
│ │ │Edit│ │Bash│ │Read│           │ │  ← Tool badges
│ │ └────┘ └────┘ └────┘           │ │
│ │ Files: auth.ts, middleware.ts   │ │
│ │                      [View Diff]│ │
│ └─────────────────────────────────┘ │
│ ┌─────────────────────────────────┐ │
│ │ #2 · 5 min ago · $0.08         │ │
│ │ "Add user authentication..."    │ │
│ │ ...                             │ │
│ └─────────────────────────────────┘ │
│ ┌─────────────────────────────────┐ │
│ │ #1 · 10 min ago · $0.04        │ │
│ │ "Set up the project structure"  │ │
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

### Interaction Card Component
**File:** `frontend/src/components/InteractionCard.tsx`

- Expandable prompt text
- Tool invocation list with icons
- Files changed badges (tap to view diff)
- Cost/token delta display
- Timestamp relative to now

---

## Phase 7: Frontend - Diff Viewer

### Mobile-Optimized Diff Component
**File:** `frontend/src/components/diff/DiffViewer.tsx`

Features:
- **Unified diff view** (single column, mobile-friendly)
- **Syntax highlighting** via highlight.js
- **Collapsible hunks** with expand/collapse all
- **Swipe navigation** between files
- **Compare selector** - pick any two interactions to diff

```
┌─────────────────────────────────────┐
│ ← Diff: auth.ts                     │
├─────────────────────────────────────┤
│ Compare: [#1 ▼] → [#3 ▼]           │  ← Interaction pickers
├─────────────────────────────────────┤
│ +15 -8 lines                        │
├─────────────────────────────────────┤
│ @@ -10,6 +10,12 @@           [−]   │  ← Collapsible hunk
│   10 │ import { User } from './..   │
│   11 │                              │
│  -12 │ function auth() {            │  ← Deletion (red bg)
│  +12 │ async function auth(req) {   │  ← Addition (green bg)
│  +13 │   const token = req.header   │
│   14 │   // ...                     │
└─────────────────────────────────────┘
```

### File Comparison Modal
**File:** `frontend/src/components/diff/CompareModal.tsx`

- Select two interactions from dropdown
- See all files that differ between them
- Tap file to view its diff

---

## Phase 8: Frontend - Search

### Search Modal
**File:** `frontend/src/components/SearchModal.tsx`

```
┌─────────────────────────────────────┐
│ 🔍 Search sessions...               │
├─────────────────────────────────────┤
│ [All] [Prompts] [Files] [Commands]  │  ← Filter chips
├─────────────────────────────────────┤
│ Results for "auth bug"              │
│ ┌─────────────────────────────────┐ │
│ │ 📁 my-app · 2 hours ago         │ │
│ │ "Fix the **auth bug** in..."    │ │  ← Highlighted match
│ │ Interaction #3 · $0.12          │ │
│ └─────────────────────────────────┘ │
│ ┌─────────────────────────────────┐ │
│ │ 📁 api-server · yesterday       │ │
│ │ Edited: src/**auth**/login.ts   │ │
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

---

## Phase 9: Frontend - Cost Analytics

### Analytics Dashboard
**File:** `frontend/src/pages/Analytics.tsx`

```
┌─────────────────────────────────────┐
│ 📊 Cost Analytics                   │
├─────────────────────────────────────┤
│ Total: $12.45 this week            │
│ ┌─────────────────────────────────┐ │
│ │ 📈 Daily spending chart         │ │
│ │    ▂ ▄ █ ▆ ▃ ▅ ▇               │ │
│ │   M T W T F S S                 │ │
│ └─────────────────────────────────┘ │
├─────────────────────────────────────┤
│ By Project                          │
│ ├─ my-app         $8.20  ████████  │
│ ├─ api-server     $3.15  ███       │
│ └─ docs           $1.10  █         │
├─────────────────────────────────────┤
│ By Model                            │
│ ├─ Opus           $9.50  █████████ │
│ ├─ Sonnet         $2.50  ██        │
│ └─ Haiku          $0.45  ▌         │
└─────────────────────────────────────┘
```

---

## Phase 10: Undo/Rollback Feature

### Rollback Implementation

**For Git Repos:**
1. Before each interaction, create a git stash or lightweight tag
2. Store stash/tag reference in interaction record
3. "Rollback to before #N" = checkout that state

**For Non-Git:**
1. Use file snapshots already captured
2. Restore all 'before' snapshots from target interaction

### API Endpoint
```
POST /api/interactions/{id}/rollback
    → Restore files to state before this interaction
```

### UI: Rollback Button
- Add "↩ Undo" button to each InteractionCard
- Confirmation modal: "This will revert X files to their state before this interaction"
- Show affected files list

---

## Implementation Order

### Week 1: Core Infrastructure
1. Database schema migrations
2. Interaction capture in buffer.rs
3. File snapshot system with deduplication
4. Tool invocation logging

### Week 2: Diff Engine & API
5. Diff computation module
6. Git integration helpers
7. REST API endpoints for interactions/diffs
8. WebSocket events for real-time updates

### Week 3: Frontend Timeline & Diffs
9. Timeline view with interaction cards
10. Diff viewer component
11. Compare selector for any-to-any diffs
12. File change summaries

### Week 4: Search, Analytics & Rollback
13. FTS5 search implementation
14. Search modal UI
15. Analytics queries and dashboard
16. Rollback feature

---

## Critical Files Summary

### Backend (Rust)
| File | Changes |
|------|---------|
| `crates/clauset-core/src/db.rs` | New tables, migrations, FTS |
| `crates/clauset-core/src/buffer.rs` | Interaction detection, tool capture |
| `crates/clauset-core/src/interaction.rs` | **NEW** - Interaction tracker |
| `crates/clauset-core/src/diff.rs` | **NEW** - Diff computation |
| `crates/clauset-core/src/analytics.rs` | **NEW** - Cost analytics |
| `crates/clauset-core/src/search.rs` | **NEW** - FTS search |
| `crates/clauset-types/src/lib.rs` | New structs |
| `crates/clauset-types/src/ws.rs` | New WebSocket messages |
| `crates/clauset-server/src/main.rs` | New API endpoints |

### Frontend (TypeScript/Solid.js)
| File | Changes |
|------|---------|
| `frontend/src/pages/SessionTimeline.tsx` | **NEW** - Timeline view |
| `frontend/src/pages/Analytics.tsx` | **NEW** - Cost dashboard |
| `frontend/src/components/InteractionCard.tsx` | **NEW** - Interaction display |
| `frontend/src/components/diff/DiffViewer.tsx` | **NEW** - Mobile diff UI |
| `frontend/src/components/diff/CompareModal.tsx` | **NEW** - Comparison picker |
| `frontend/src/components/SearchModal.tsx` | **NEW** - Search UI |
| `frontend/src/stores/interactions.ts` | **NEW** - Interaction state |
| `frontend/src/lib/api.ts` | New API methods |

---

## Verification Plan

After each phase:
1. Run existing tests to ensure no regressions
2. Manual testing of new features on mobile Safari
3. Check WebSocket real-time updates work correctly
4. Verify database migrations run cleanly

Final verification:
- Create a session, send 3-4 prompts that edit files
- View timeline with all interactions
- Compare diffs between interaction #1 and #3
- Search for a term in one of the prompts
- View cost analytics
- Rollback to before interaction #2
