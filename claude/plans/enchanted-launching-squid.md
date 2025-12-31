# Prompt Library Implementation Plan

## Overview
Add a "Prompt Library" feature that indexes and displays every prompt ever sent to Claude Code on this machine, with chronological sorting, expandable entries, copy functionality, and real-time updates from active sessions.

**UI Placement**: FAB menu (bottom-right) - convert existing single FAB to a menu with "New Session" and "Prompt Library" options.

---

## Architecture Summary

```
~/.claude/history.jsonl          →  Backfill on startup
~/.claude/projects/*/*.jsonl     →  Parse user prompts
        ↓
   [prompts table]  ←────────────  UserPromptSubmit hook (real-time)
        ↓
   GET /api/prompts  →  Frontend store  →  PromptLibraryModal
```

---

## Phase 1: Backend - Database Schema

### File: `crates/clauset-core/src/interaction_store.rs`

Add `prompts` table to `initialize_tables()`:

```sql
CREATE TABLE IF NOT EXISTS prompts (
    id TEXT PRIMARY KEY,
    claude_session_id TEXT NOT NULL,
    project_path TEXT NOT NULL,
    content TEXT NOT NULL,
    preview TEXT NOT NULL,          -- First 200 chars
    timestamp INTEGER NOT NULL,     -- Unix ms
    word_count INTEGER NOT NULL,
    char_count INTEGER NOT NULL,
    content_hash TEXT NOT NULL      -- For deduplication
);

CREATE INDEX IF NOT EXISTS idx_prompts_timestamp ON prompts(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_prompts_session ON prompts(claude_session_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_prompts_dedup ON prompts(claude_session_id, content_hash);
```

Add methods:
- `insert_prompt(&self, prompt: &Prompt) -> Result<()>`
- `list_prompts(&self, limit: u32, offset: u32) -> Result<Vec<PromptSummary>>`
- `get_prompt(&self, id: Uuid) -> Result<Option<Prompt>>`
- `get_prompt_count(&self) -> Result<u64>`

---

## Phase 2: Backend - Types

### File: `crates/clauset-types/src/lib.rs`

Add to exports and create types:

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Prompt {
    pub id: Uuid,
    pub claude_session_id: String,
    pub project_path: PathBuf,
    pub content: String,
    pub preview: String,
    pub timestamp: u64,
    pub word_count: u32,
    pub char_count: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PromptSummary {
    pub id: Uuid,
    pub preview: String,
    pub project_name: String,
    pub timestamp: u64,
    pub word_count: u32,
}
```

---

## Phase 3: Backend - Backfill Indexer

### New File: `crates/clauset-core/src/prompt_indexer.rs`

Indexes historical prompts from `~/.claude/` on first run:

```rust
pub struct PromptIndexer { /* claude_dir, store */ }

impl PromptIndexer {
    pub async fn backfill_if_needed(&self) -> Result<BackfillStats>
    pub fn parse_transcript(&self, path: &Path) -> Result<Vec<Prompt>>
}
```

**Logic:**
1. Check if `prompts` table is empty
2. List all `~/.claude/projects/*/*.jsonl` files
3. Parse each JSONL, extract entries with `type: "user"` and text content
4. Insert with deduplication via `content_hash`
5. Run async on server startup (don't block)

---

## Phase 4: Backend - Real-time Hook Integration

### File: `crates/clauset-server/src/routes/hooks.rs`

In `HookEvent::UserPromptSubmit` handler (line ~107):

```rust
HookEvent::UserPromptSubmit { session_id, prompt, cwd, .. } => {
    // Existing code...

    // NEW: Index prompt for Prompt Library
    let prompt_entry = Prompt {
        id: Uuid::new_v4(),
        claude_session_id: extract_claude_session_id(&event),
        project_path: PathBuf::from(cwd),
        content: prompt.clone(),
        preview: truncate(&prompt, 200),
        timestamp: now_ms(),
        word_count: prompt.split_whitespace().count() as u32,
        char_count: prompt.len() as u32,
    };

    if let Err(e) = state.interaction_processor.store().insert_prompt(&prompt_entry) {
        warn!("Failed to index prompt: {}", e);
    }

    // Broadcast for real-time UI update
    let _ = state.session_manager.broadcast_event(ProcessEvent::NewPrompt(prompt_entry.into()));
}
```

---

## Phase 5: Backend - API Routes

### New File: `crates/clauset-server/src/routes/prompts.rs`

```rust
// GET /api/prompts?limit=50&offset=0
pub async fn list_prompts(...) -> Result<Json<PromptsListResponse>>

// GET /api/prompts/{id}
pub async fn get_prompt(...) -> Result<Json<Prompt>>
```

### File: `crates/clauset-server/src/main.rs`

Add routes:
```rust
.route("/prompts", get(routes::prompts::list_prompts))
.route("/prompts/{id}", get(routes::prompts::get_prompt))
```

---

## Phase 6: Frontend - API Types

### File: `frontend/src/lib/api.ts`

```typescript
export interface Prompt {
  id: string;
  claude_session_id: string;
  project_path: string;
  content: string;
  preview: string;
  timestamp: number;
  word_count: number;
  char_count: number;
}

export interface PromptSummary {
  id: string;
  preview: string;
  project_name: string;
  timestamp: number;
  word_count: number;
}

export interface PromptsListResponse {
  prompts: PromptSummary[];
  total_count: number;
  has_more: boolean;
}

// Add to api object:
prompts: {
  list: (limit?: number, offset?: number) => fetchJSON<PromptsListResponse>(`/prompts?limit=${limit}&offset=${offset}`),
  get: (id: string) => fetchJSON<Prompt>(`/prompts/${id}`),
}
```

---

## Phase 7: Frontend - Store

### New File: `frontend/src/stores/prompts.ts`

```typescript
const [promptsStore, setPromptsStore] = createStore<{
  prompts: PromptSummary[];
  totalCount: number;
  hasMore: boolean;
  expandedId: string | null;
  expandedContent: string | null;
}>();

export async function fetchPrompts(reset = false);
export async function loadMore();
export async function expandPrompt(id: string);
export async function copyPrompt(content: string);
export function addNewPrompt(prompt: PromptSummary);  // For WebSocket
```

---

## Phase 8: Frontend - FAB Menu

### File: `frontend/src/pages/Sessions.tsx`

Convert single FAB to expandable menu:

```tsx
const [fabOpen, setFabOpen] = createSignal(false);
const [showPromptLibrary, setShowPromptLibrary] = createSignal(false);

// In render:
<div class="fab-menu">
  <Show when={fabOpen()}>
    <button onClick={() => { setShowPromptLibrary(true); setFabOpen(false); }}>
      <BookIcon /> Prompt Library
    </button>
    <button onClick={() => { setShowNewSession(true); setFabOpen(false); }}>
      <PlusIcon /> New Session
    </button>
  </Show>
  <button class="fab-main" onClick={() => setFabOpen(!fabOpen())}>
    <Show when={fabOpen()} fallback={<PlusIcon />}>
      <CloseIcon />
    </Show>
  </button>
</div>

<PromptLibraryModal
  isOpen={showPromptLibrary()}
  onClose={() => setShowPromptLibrary(false)}
/>
```

---

## Phase 9: Frontend - Modal Component

### New File: `frontend/src/components/prompts/PromptLibraryModal.tsx`

Structure:
```
PromptLibraryModal
├── Backdrop (blur)
├── Header: "Prompt Library" + count badge + close button
├── Prompt list (scrollable, infinite scroll)
│   └── PromptItem (for each)
│       ├── Preview text (truncated)
│       ├── Project name + timestamp
│       ├── Word count badge
│       ├── Copy button (icon)
│       └── Expanded content (when clicked)
└── "Load more" or loading spinner
```

Styling follows existing modal patterns (SearchModal, NewSessionModal):
- Backdrop: `rgba(0,0,0,0.6)` with blur
- Card: `var(--color-bg-elevated)`, retro shadow
- List items: expandable with animation

---

## Phase 10: WebSocket Integration

### File: `frontend/src/lib/ws.ts`

Add handler for real-time updates:
```typescript
case 'new_prompt':
  addNewPrompt(msg.prompt);
  break;
```

### File: `crates/clauset-types/src/ws.rs`

Add message variant:
```rust
NewPrompt { prompt: PromptSummary },
```

---

## Files to Create
1. `crates/clauset-core/src/prompt_indexer.rs`
2. `crates/clauset-server/src/routes/prompts.rs`
3. `frontend/src/stores/prompts.ts`
4. `frontend/src/components/prompts/PromptLibraryModal.tsx`

## Files to Modify
1. `crates/clauset-core/src/interaction_store.rs` - Add prompts table + CRUD
2. `crates/clauset-core/src/lib.rs` - Export prompt_indexer
3. `crates/clauset-types/src/lib.rs` - Add Prompt types
4. `crates/clauset-types/src/ws.rs` - Add NewPrompt message
5. `crates/clauset-server/src/routes/hooks.rs` - Index prompts on UserPromptSubmit
6. `crates/clauset-server/src/routes/mod.rs` - Export prompts module
7. `crates/clauset-server/src/main.rs` - Add routes, run backfill on startup
8. `frontend/src/lib/api.ts` - Add prompts API methods
9. `frontend/src/lib/ws.ts` - Handle NewPrompt events
10. `frontend/src/pages/Sessions.tsx` - Convert FAB to menu, add modal

---

## Implementation Order

1. Database schema + types (interaction_store.rs, types)
2. Store CRUD methods
3. API routes (prompts.rs)
4. Backfill indexer (prompt_indexer.rs)
5. Hook integration for real-time capture
6. Frontend API types + store
7. PromptLibraryModal component
8. FAB menu conversion
9. WebSocket real-time updates
10. Test end-to-end
