# Permission Mode & Session Log Enhancement Plan

## Problem Statement
When clicking the mode quick action to cycle permission modes, the mode doesn't update in the status bar in the chat window, even though it changes in the terminal tab.

## User Requirements
1. **Mode Source**: Focus on hook events only (hooks already contain permission_mode)
2. **Entry Types**: Process ALL transcript entry types (compact_boundary, stop_hook_summary, file-history-snapshot)
3. **Priority**: Fix mode issue FIRST, then enhance transcript watcher

## Root Cause Analysis

### Current Architecture
1. **Hook Events (HTTP POST)** - Contain `permission_mode` field, processed in `hooks.rs:71-75`
2. **Transcript JSONL Files** - Contain `user`, `assistant`, `system`, `file-history-snapshot` entry types (NO direct permission_mode)
3. **WebSocket** - Sends `ModeChange` event to frontend when mode changes

### Key Insight
The Claude JSONL transcript files do **NOT** contain `permission_mode` directly - it only comes through the HTTP hook events. The `system` entries have subtypes like `stop_hook_summary` and `compact_boundary`.

### Potential Issues Identified
1. **Mode only sent on CHANGE**: `buffer.rs:1066-1068` - if `permission_mode == Some(mode)`, returns false (no event sent)
2. **Initial mode timing**: WebSocket sends initial mode on connect (`websocket.rs:48-57`), but only if activity exists AND permission_mode is already set
3. **Frontend state**: First mode_change is silently accepted without showing change notification (`Session.tsx:586-590`)

## Implementation Plan

### PART A: Fix Permission Mode (Priority 1)

#### Phase 1: Add Tests (TDD)

**Backend Tests** - `crates/clauset-server/tests/permission_mode.rs` (new)
- [ ] Hook event with permission_mode correctly updates session activity
- [ ] ModeChange event is broadcast when mode changes
- [ ] ModeChange event is NOT broadcast when mode is same
- [ ] WebSocket sends initial mode on connect
- [ ] Mode normalization (`from_hook_value`) handles all Claude Code values

**Frontend Tests** - `frontend/src/lib/__tests__/format.test.ts` (extend existing)
- [ ] `normalizePermissionMode` handles all known values including camelCase

#### Phase 2: Fix Permission Mode Reliability

**2.1 Hook Processing** - `crates/clauset-server/src/routes/hooks.rs`
- Modify to ALWAYS send mode on first hook (even if `default`)
- Add debug logging for mode processing path

**2.2 WebSocket Initial State** - `crates/clauset-server/src/websocket.rs`
- Change line 49: Send mode even for `default` value
- Currently: `if let Some(mode) = activity.permission_mode`
- Fix: Send `ModeChange` with `Default` if no mode set

**2.3 Buffer Update Logic** - `crates/clauset-core/src/buffer.rs:1062-1073`
- Review `update_permission_mode` - ensure first mode update always triggers event
- Current issue: `None != Some(Default)` should return true (it does), but verify the mode is being set

**2.4 Frontend Initialization** - `frontend/src/pages/Session.tsx`
- Verify mode signal is initialized correctly
- Add debug logging in development

---

### PART B: Extend Transcript Watcher (Priority 2)

#### Phase 3: Add New Entry Types

**File**: `crates/clauset-core/src/transcript_watcher.rs`

Current entry types: `user`, `assistant` (lines 362-373)
Add processing for: `system`, `file-history-snapshot`

**3.1 New TranscriptEvent Variants**
```rust
// Add to TranscriptEvent enum
SystemEvent {
    message_id: String,
    subtype: String,  // "stop_hook_summary", "compact_boundary", etc.
    content: Option<String>,
    metadata: Option<Value>,
    timestamp: u64,
},
FileSnapshot {
    message_id: String,
    file_path: String,
    timestamp: u64,
},
```

**3.2 Process System Entries**
- Parse `subtype` field from system entries
- Extract relevant fields: content, hookCount, hookInfos, compactMetadata, etc.
- Emit `TranscriptEvent::SystemEvent`

**3.3 Process File History Snapshots**
- Parse file-history-snapshot entries
- Extract file paths and timestamps
- Emit `TranscriptEvent::FileSnapshot`

#### Phase 4: Handle New Events

**File**: `crates/clauset-server/src/routes/hooks.rs` (transcript event loop)

Add handlers for new event types:
- `SystemEvent` with subtype `compact_boundary` → broadcast context compaction notification
- `FileSnapshot` → could track file modifications (future enhancement)

---

## Critical Files Summary

| File | Changes |
|------|---------|
| `crates/clauset-server/tests/permission_mode.rs` | New test file |
| `crates/clauset-server/src/routes/hooks.rs` | Mode logging, ensure mode sent |
| `crates/clauset-server/src/websocket.rs:48-57` | Send default mode on connect |
| `crates/clauset-core/src/buffer.rs:1062-1073` | Verify mode update logic |
| `crates/clauset-core/src/transcript_watcher.rs:362-373` | Add system/file-history-snapshot processing |
| `frontend/src/pages/Session.tsx:581-599` | Mode handling verification |
| `frontend/src/lib/__tests__/format.test.ts` | Mode normalization tests |

## Execution Order
1. Write failing backend tests for permission mode
2. Fix hook + websocket mode handling
3. Verify tests pass
4. Write tests for transcript watcher enhancement
5. Implement new entry type processing
6. Integration testing

## Success Criteria
- [ ] Mode changes from quick action reflected in status bar
- [ ] All backend tests pass (`cargo test --workspace`)
- [ ] All frontend tests pass (`cd frontend && npm test`)
- [ ] System entries from transcript processed
- [ ] No regression in existing functionality
