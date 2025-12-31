# Session Persistence & Recovery Plan

## Problem Summary

Sessions don't survive backend restarts because:
1. **Wrong session ID**: Clauset generates random UUIDs for `claude_session_id` that Claude CLI doesn't recognize
2. **No capture**: Claude's real session ID isn't stored to database
3. **Isolated from Claude's storage**: Clauset doesn't use `~/.claude` as source of truth

## Enhanced Solution: Use ~/.claude as Source of Truth

Claude Code stores ALL session data in `~/.claude/`:
- `~/.claude/history.jsonl` - All sessions with ID, project path, timestamp, preview
- `~/.claude/projects/<path>/<session-id>.jsonl` - Full conversation history

**Benefits of using ~/.claude:**
1. Resume sessions started in terminal (not Clauset)
2. Sessions started in Clauset can be resumed in terminal
3. Single source of truth across all Claude usage
4. Super robust - any session is resumable anywhere

## Solution Overview

1. **Capture and store Claude's real session ID** (existing issue)
2. **Add "Import Session" feature** - bring terminal sessions into Clauset
3. **List sessions from ~/.claude** - see all sessions for a project
4. **Persist terminal buffer** - see history after resume

---

## Implementation Steps

### Phase 1: Capture Claude's Real Session ID (Core Fix)

**Files to modify:**
- `crates/clauset-core/src/db.rs`
- `crates/clauset-core/src/session.rs`
- `crates/clauset-server/src/websocket.rs`

**Changes:**

1. **Add `update_claude_session_id()`** in `db.rs`
2. **Add `set_claude_session_id()`** in `session.rs`
3. **Capture on System init event** in `websocket.rs:91`
4. **Use `Uuid::nil()` initially** in `session.rs:116`

### Phase 2: Read Sessions from ~/.claude (New Feature)

**Files to add/modify:**
- `crates/clauset-core/src/claude_sessions.rs` - NEW: Parse ~/.claude data
- `crates/clauset-server/src/routes/sessions.rs` - Add endpoint
- `frontend/src/pages/Sessions.tsx` - Show external sessions

**Claude's storage structure:**
```
~/.claude/
├── history.jsonl                    # Session metadata (ID, project, timestamp, preview)
└── projects/
    └── -Users-moose-project/        # URL-encoded project path
        └── <session-id>.jsonl       # Full conversation
```

**Changes:**

1. **Create ClaudeSessionReader** (`claude_sessions.rs`):
   ```rust
   pub struct ClaudeSession {
       pub session_id: String,      // UUID
       pub project_path: PathBuf,
       pub timestamp: DateTime<Utc>,
       pub preview: String,         // First prompt/display text
   }

   impl ClaudeSessionReader {
       /// List all sessions from ~/.claude/history.jsonl for a project
       pub fn list_sessions(project_path: &Path) -> Result<Vec<ClaudeSession>>;

       /// Check if a session exists and is valid
       pub fn session_exists(session_id: &str) -> bool;
   }
   ```

2. **Add API endpoint** (`routes/sessions.rs`):
   ```
   GET /api/claude-sessions?project_path=/Users/moose/project
   ```
   Returns all Claude sessions for that project (including ones not in Clauset DB)

3. **Import session endpoint**:
   ```
   POST /api/sessions/import
   { claude_session_id: "uuid", project_path: "/path" }
   ```
   Creates a Clauset session from an external Claude session

4. **Frontend: Show importable sessions**
   - On Sessions page, show "Import from Terminal" option
   - List sessions from ~/.claude that aren't in Clauset
   - Click to import and resume

### Phase 3: Validate & Handle Resume Errors

**Files to modify:**
- `crates/clauset-core/src/session.rs`
- `crates/clauset-core/src/error.rs`

**Changes:**

1. **Add `SessionNotResumable` error** in `error.rs`
2. **Validate claude_session_id before resume** in `session.rs`
3. **Cross-reference with ~/.claude** - verify session exists before spawning

### Phase 4: Persist Terminal Buffer

**Problem**: Terminal buffer is in-memory only (500KB ring buffer). Lost on server restart or session stop.

**Current state**:
- Chat history: ✅ Persisted to SQLite immediately
- Terminal buffer: ❌ In-memory, lost on stop/restart
- Claude context: ✅ Managed by Claude CLI in ~/.claude

**Files to modify:**
- `crates/clauset-core/src/db.rs` - Add terminal_buffer table and methods
- `crates/clauset-core/src/buffer.rs` - Add persistence hooks
- `crates/clauset-core/src/session.rs` - Load buffer on resume

**Changes:**

1. **Add terminal buffer table** (`db.rs`):
   ```sql
   CREATE TABLE IF NOT EXISTS terminal_buffers (
       session_id TEXT PRIMARY KEY,
       data BLOB NOT NULL,
       start_seq INTEGER NOT NULL,
       end_seq INTEGER NOT NULL,
       updated_at TEXT NOT NULL
   );
   ```

2. **Persist buffer on-demand** (`session.rs`):
   - Save on session stop (`terminate_session()`)
   - Save on process exit event (in `websocket.rs` when `ProcessEvent::Exited`)
   - Save on graceful server shutdown (SIGTERM handler)
   - Keep only most recent buffer state (replace, not append)
   - Note: Unexpected crash may lose recent output (acceptable tradeoff for less I/O)

3. **Load buffer on resume** (`session.rs:resume_session`):
   ```rust
   // After spawning process, load persisted buffer into memory
   if let Some(buffer_data) = self.db.get_terminal_buffer(session_id)? {
       self.buffers.restore_buffer(session_id, buffer_data).await;
   }
   ```

4. **Load buffer on reconnection** (for server restart recovery):
   - In `websocket.rs` SyncRequest handler, if buffer is empty but DB has data
   - Load from DB and serve to client

### Phase 5: Frontend - Better Errors & UX

**Files to modify:**
- `crates/clauset-types/src/session.rs` - Add `is_resumable()` helper
- `frontend/src/pages/Session.tsx` - Better error handling

**Changes:**

1. **Add resumable helper** (`types/session.rs`):
   ```rust
   impl Session {
       pub fn is_resumable(&self) -> bool {
           !self.claude_session_id.is_nil()
       }
   }
   ```

2. **Better resume error handling** (`Session.tsx:handleResume`):
   - Parse error message from backend
   - Show specific message for "not resumable" vs other errors
   - Suggest "Start New Session" when not resumable

3. **Optional: Add resumable indicator to session list**
   - Show different icon/text for stopped sessions based on resumability
   - Gray out Resume button for non-resumable sessions

---

## Files to Modify (Summary)

| File | Change |
|------|--------|
| `crates/clauset-core/src/claude_sessions.rs` | **NEW**: Parse ~/.claude/history.jsonl and list sessions |
| `crates/clauset-core/src/db.rs` | Add `update_claude_session_id()`, `terminal_buffers` table |
| `crates/clauset-core/src/session.rs` | Add `set_claude_session_id()`, validate, persist buffer |
| `crates/clauset-core/src/buffer.rs` | Add `restore_buffer()` |
| `crates/clauset-core/src/error.rs` | Add `SessionNotResumable` error |
| `crates/clauset-server/src/routes/sessions.rs` | Add `/api/claude-sessions` and `/api/sessions/import` |
| `crates/clauset-server/src/websocket.rs` | Capture Claude's session ID, load buffer from DB |
| `frontend/src/pages/Sessions.tsx` | Show "Import from Terminal" option |
| `frontend/src/pages/Session.tsx` | Better error messages |

---

## Testing Scenarios

1. **Clauset session → exit → resume**:
   - Claude's session ID captured and stored ✓
   - Resume works with real session ID ✓

2. **Terminal session → import into Clauset**:
   - List sessions from ~/.claude ✓
   - Import creates Clauset session ✓
   - Resume works in Clauset ✓

3. **Backend restart mid-session**:
   - Session marked stopped, still resumable ✓
   - Terminal buffer preserved in DB ✓

4. **Resume after restart**:
   - Terminal history visible and scrollable ✓
   - Chat history fully restored ✓

5. **Cross-validate with ~/.claude**:
   - Before resume, verify session exists in ~/.claude ✓
   - Clear error if session is stale/deleted ✓

---

## Success Criteria

- [ ] `claude_session_id` captured from Claude's System init event
- [ ] Resume uses the real Claude session ID
- [ ] Sessions survive backend restarts
- [ ] **Import terminal sessions into Clauset** (new!)
- [ ] **List all sessions from ~/.claude for a project** (new!)
- [ ] Terminal history visible and scrollable after resume
- [ ] Chat history visible after resume
- [ ] Clear error when session cannot be resumed
