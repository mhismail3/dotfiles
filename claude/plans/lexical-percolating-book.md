# Plan: Chat Persistence, UI Fixes, and Cleanup

## Overview
Five issues to address:
1. Chat history doesn't persist when reopening sessions
2. Make Chat view the default mode and reorder toggle tabs
3. Remove "Chat Mode" toggle from New Session modal
4. Fix keyboard overlap in New Session modal
5. Make chat textbox grow upwards (max 10 lines)

---

## Issue 1: Chat History Persistence (Database + localStorage)

### Root Cause
- **Terminal**: Server buffers data + client uses localStorage cache
- **Chat messages**: In-memory only (both server ChatProcessor and client messages.ts)

When user reopens a session, terminal history loads from server buffer/localStorage, but chat messages are lost.

### Solution: Hybrid Approach (Database + localStorage)
**Database** = source of truth (survives uninstalls, queryable)
**localStorage** = fast cache (instant load while fetching from DB)

---

### Part A: Backend - Database Storage

**1. Add chat_messages table** (`crates/clauset-core/src/interaction_store.rs`)
```sql
CREATE TABLE IF NOT EXISTS chat_messages (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    interaction_id TEXT,
    sequence_number INTEGER NOT NULL,
    role TEXT NOT NULL,  -- 'user' | 'assistant'
    content TEXT NOT NULL,
    is_complete INTEGER NOT NULL DEFAULT 1,
    timestamp INTEGER NOT NULL,
    FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE,
    FOREIGN KEY (interaction_id) REFERENCES interactions(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_chat_messages_session_id ON chat_messages(session_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_session_seq ON chat_messages(session_id, sequence_number);

CREATE TABLE IF NOT EXISTS chat_tool_calls (
    id TEXT PRIMARY KEY,
    message_id TEXT NOT NULL,
    sequence_number INTEGER NOT NULL,
    tool_name TEXT NOT NULL,
    tool_input TEXT,  -- JSON
    tool_output TEXT,
    is_error INTEGER NOT NULL DEFAULT 0,
    is_complete INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (message_id) REFERENCES chat_messages(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_chat_tool_calls_message_id ON chat_tool_calls(message_id);
```

**2. Add InteractionStore methods**
```rust
// Save a chat message
pub fn save_chat_message(&self, msg: &ChatMessage) -> Result<()>

// Save/update a tool call
pub fn save_chat_tool_call(&self, message_id: &str, tool_call: &ChatToolCall) -> Result<()>

// Get all messages for a session (ordered by sequence)
pub fn get_chat_messages(&self, session_id: &str) -> Result<Vec<ChatMessage>>

// Delete messages for a session
pub fn delete_chat_messages(&self, session_id: &str) -> Result<()>
```

**3. Modify ChatProcessor** (`crates/clauset-core/src/chat_processor.rs`)
- Inject `InteractionStore` reference
- Call `save_chat_message()` when creating/updating messages
- Call `save_chat_tool_call()` when tool calls start/complete

**4. Add WebSocket endpoint** (`crates/clauset-server/src/websocket.rs`)
- On client connect, send `chat_history` message with all messages for session
- Similar to how terminal buffer is sent on connect

**5. Add REST endpoint** (optional, for explicit fetch)
- `GET /api/sessions/{id}/chat-history` → returns all chat messages

---

### Part B: Frontend - localStorage Cache + Backend Sync

**1. Add localStorage persistence** (`frontend/src/stores/messages.ts`)
```typescript
const STORAGE_KEY_PREFIX = 'clauset_messages_';
const MAX_STORAGE_SIZE = 500000; // 500KB

// Load from localStorage (instant, for fast startup)
function loadFromStorage(sessionId: string): Message[]

// Save to localStorage (debounced)
function saveToStorage(sessionId: string, messages: Message[]): void

// Modified getMessagesForSession: load from storage if not in memory
export function getMessagesForSession(sessionId: string): Message[]
```

**2. Handle backend sync** (`frontend/src/pages/Session.tsx`)
- On WebSocket connect, receive `chat_history` message from backend
- Replace localStorage/memory with backend data (source of truth)
- Save to localStorage for next fast load

**3. Flow on session open:**
```
1. getMessagesForSession() → load from localStorage (instant UI)
2. WebSocket connects
3. Server sends chat_history with all messages
4. Client replaces in-memory + localStorage with server data
5. UI updates with complete history
```

---

### Files to Modify

**Backend:**
- `crates/clauset-core/src/interaction_store.rs` - Add tables + methods
- `crates/clauset-core/src/chat_processor.rs` - Persist messages to DB
- `crates/clauset-server/src/websocket.rs` - Send chat history on connect
- `crates/clauset-types/src/chat.rs` - Add ChatHistoryResponse type

**Frontend:**
- `frontend/src/stores/messages.ts` - Add localStorage persistence
- `frontend/src/pages/Session.tsx` - Handle chat_history WebSocket message
- `frontend/src/lib/api.ts` - Add ChatHistoryResponse type (if needed)

---

## Issue 2: Chat View as Default Mode

### Current State
- Line 116: `const [currentView, setCurrentView] = createSignal<'term' | 'chat' | 'history'>('term')`
- Line 666: `{(['term', 'chat', 'history'] as const).map(...)}`
- Display shows "term" literal

### Solution
```
1. Change default: 'term' → 'chat'
2. Update type: 'term' | 'chat' | 'history' → 'chat' | 'terminal' | 'history'
3. Reorder array: ['chat', 'terminal', 'history']
4. Update display label mapping:
   - 'chat' → 'chat'
   - 'terminal' → 'terminal'
   - 'history' → 'history'
5. Update all currentView() === 'term' checks → 'terminal'
```

### Files to Modify
- `frontend/src/pages/Session.tsx` (lines 116, 666-685, plus any conditional render checks)

---

## Issue 3: Remove Chat Mode Toggle

### Current State
- Line 21: `const [chatMode, setChatMode] = createSignal(false)`
- Line 121: `terminal_mode: !chatMode()`
- Lines 520-562: Chat Mode toggle UI

### Solution
```
1. Remove signal: chatMode, setChatMode (line 21)
2. Remove from API call: terminal_mode: !chatMode() (line 121)
   - Just don't send terminal_mode at all (backend ignores it)
3. Remove entire toggle UI (lines 520-562)
```

### Files to Modify
- `frontend/src/components/chat/NewSessionModal.tsx`

---

## Issue 4: Keyboard Overlap in Modal

### Problem
When keyboard appears for project field, the "Create Session" button is hidden behind it.

### Solution
```
1. Import useKeyboard hook in NewSessionModal
2. Track keyboard visibility and viewport height
3. When keyboard visible:
   - Reduce modal max-height to fit available viewport
   - Ensure form content is scrollable
   - The form already has overflow-y: auto, so just need to constrain max-height
4. Adjust backdrop positioning to account for keyboard
```

### Implementation
```tsx
const { isVisible: keyboardVisible, viewportHeight } = useKeyboard();

// Modal container:
style={{
  "max-height": keyboardVisible()
    ? `${viewportHeight() - 32}px`  // Available viewport minus padding
    : 'calc(100dvh - 32px)',
}}
```

### Files to Modify
- `frontend/src/components/chat/NewSessionModal.tsx`

---

## Issue 5: Chat Textbox Multi-line Expansion

### Current State
- Line 56: `rows={1}` (fixed single row)
- Line 66: `resize: 'none'`
- No auto-expansion logic

### Solution
```
1. Add ref to textarea
2. Add createEffect to calculate row count on input
3. Calculate rows from content:
   - Count newlines in message
   - Also check scrollHeight vs lineHeight for wrapped lines
   - rows = Math.min(Math.max(1, calculatedRows), 10)
4. When rows >= 10:
   - Set overflow-y: 'auto' (enable scroll)
5. Otherwise:
   - Set overflow-y: 'hidden' (no scroll, natural height)
6. Reset to 1 row after send
```

### Implementation
```tsx
let textareaRef: HTMLTextAreaElement | undefined;

const calculateRows = () => {
  if (!textareaRef) return 1;
  const text = message();
  const lineBreaks = (text.match(/\n/g) || []).length + 1;

  // Also check for wrapped lines
  textareaRef.style.height = 'auto';
  const lineHeight = 20; // ~14px font * 1.4 line-height
  const scrollRows = Math.ceil(textareaRef.scrollHeight / lineHeight);

  return Math.min(Math.max(lineBreaks, scrollRows), 10);
};

const rows = () => calculateRows();
const shouldScroll = () => rows() >= 10;
```

### Files to Modify
- `frontend/src/components/chat/InputBar.tsx`

---

## Execution Order

### Phase 1: Frontend-only changes (quick wins)
1. **Issue 3**: Remove Chat Mode toggle (simplest, reduces code)
2. **Issue 4**: Fix keyboard overlap in modal (builds on removal of toggle)
3. **Issue 2**: Change default view to chat + rename tabs
4. **Issue 5**: Implement chat textbox expansion

### Phase 2: Chat persistence (backend + frontend)
5. **Issue 1A**: Backend - Add database tables + methods
6. **Issue 1B**: Backend - Modify ChatProcessor to persist messages
7. **Issue 1C**: Backend - Send chat history on WebSocket connect
8. **Issue 1D**: Frontend - Add localStorage cache
9. **Issue 1E**: Frontend - Handle chat_history sync from backend

---

## Testing Checklist

### Frontend Changes
- [ ] Create new session → modal has no Chat Mode toggle
- [ ] Type in project field → keyboard doesn't overlap Create button
- [ ] Open any session → defaults to Chat tab
- [ ] Toggle shows: chat | terminal | history (left to right)
- [ ] Terminal view still works when selecting "terminal"
- [ ] Type multi-line in chat input → grows up to 10 lines
- [ ] Type 11+ lines → scrollbar appears, stays at 10 rows
- [ ] Send message → input resets to 1 row

### Chat Persistence
- [ ] Send messages in session → messages saved to database
- [ ] Close session page → reopen → chat history loads instantly (localStorage)
- [ ] Kill app completely → reopen session → full history from database
- [ ] Terminal history still persists (no regression)
- [ ] Uninstall/reinstall PWA → chat history still there (database)
- [ ] Delete session → chat messages also deleted (CASCADE)
