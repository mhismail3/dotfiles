# Chat Mode Implementation Plan

## Goal
Implement a chat mode that displays Claude's messages as chat bubbles while maintaining a 1-to-1 mapping with terminal sessions. The terminal remains the source of truth - chat mode is a view layer that parses and presents terminal data in a chat-like format.

## Critical Constraints
- **No API/SDK usage**: All interactions via terminal sessions with max plan (no `claude -p`)
- **1-to-1 session mapping**: Same session, different views (term/chat toggle)
- **No regressions**: Terminal mode must continue to work exactly as before
- **Hybrid text extraction**: Real-time terminal parsing + transcript file verification

---

## Architecture Overview

```
Terminal PTY (source of truth)
        │
        ├──────────────────────────────────────┐
        │                                      │
        ▼                                      ▼
   Hook Events                          Terminal Output
   (HTTP → /api/hooks)                  (WebSocket → client)
        │                                      │
        │                                      │
        ├─ UserPromptSubmit → User message     ├─ ANSI parsing
        ├─ PreToolUse → Tool start             ├─ Text extraction
        ├─ PostToolUse → Tool result           └─ Real-time streaming
        └─ Stop → Response complete                    │
                │                                      │
                └──────────────┬───────────────────────┘
                               │
                               ▼
                       ChatMessageProcessor
                               │
                               ▼
                       WebSocket broadcast
                       (ChatMessage events)
                               │
                               ▼
                       Frontend messages store
                               │
                       ┌───────┴───────┐
                       ▼               ▼
                  Chat View       Terminal View
                (MessageBubble)     (xterm.js)
```

---

## Phase 1: Backend Message Extraction

### 1.1 New ChatMessage Types
**File**: `crates/clauset-types/src/chat.rs` (new)

```rust
pub struct ChatMessage {
    pub id: String,           // Unique message ID
    pub session_id: Uuid,
    pub role: MessageRole,    // User | Assistant
    pub content: String,      // Message text (may be partial)
    pub tool_calls: Vec<ChatToolCall>,
    pub is_streaming: bool,
    pub is_complete: bool,
    pub timestamp: u64,
}

pub struct ChatToolCall {
    pub id: String,
    pub name: String,
    pub input: Value,
    pub output: Option<String>,
    pub is_error: bool,
    pub is_complete: bool,
}

pub enum MessageRole { User, Assistant }
```

### 1.2 Chat Message Processor
**File**: `crates/clauset-core/src/chat_processor.rs` (new)

Responsibilities:
1. **State machine** per session tracking current message being built
2. **Hook event handler**: Convert hooks to chat message updates
3. **Terminal text parser**: Extract Claude's prose from PTY output
4. **Broadcast**: Send `ChatMessage` updates via WebSocket

State machine:
```
Idle → [UserPromptSubmit] → BuildingUserMessage → [TerminalOutput starts] →
       BuildingAssistantMessage → [PreToolUse] → ToolInProgress →
       [PostToolUse] → BuildingAssistantMessage → [Stop] → Idle
```

### 1.3 Terminal Text Extraction
**File**: `crates/clauset-core/src/chat_processor.rs`

Strategy:
1. Strip ANSI escape codes from terminal chunks
2. Detect Claude's text blocks using pattern matching:
   - Text after prompt submission
   - Text between tool outputs
   - Text before/after tool calls
3. Buffer text, emit as streaming content
4. Use transcript file (`transcript_path` from hooks) for verification on `Stop`

Key patterns to detect:
- Claude's thinking/planning indicators (status line changes)
- Tool invocation patterns (tool name headers in output)
- End of response markers (status line returning to "Ready")

### 1.4 Integration with SessionManager
**File**: `crates/clauset-core/src/session.rs`

- Add `ChatMessageProcessor` to `SessionBuffers`
- Feed terminal output to processor
- Feed hook events to processor
- Processor broadcasts `ChatMessage` events via same event bus

---

## Phase 2: WebSocket Protocol Extension

### 2.1 New WebSocket Message Types
**File**: `crates/clauset-server/src/ws/messages.rs`

```rust
enum WsServerMessage {
    // Existing...
    ChatMessage(ChatMessageEvent),      // New assistant/user message
    ChatMessageUpdate(ChatUpdateEvent), // Streaming content update
    ChatToolCall(ChatToolCallEvent),    // Tool started
    ChatToolResult(ChatToolResultEvent),// Tool completed
}

struct ChatMessageEvent {
    session_id: Uuid,
    message: ChatMessage,
}

struct ChatUpdateEvent {
    session_id: Uuid,
    message_id: String,
    content_delta: String,  // Append to existing content
    is_complete: bool,
}
```

### 2.2 Broadcast Integration
**File**: `crates/clauset-server/src/ws/session.rs`

- Subscribe to `ProcessEvent::ChatMessage` variants
- Forward to connected WebSocket clients
- Include in session WebSocket and global WebSocket (for dashboard)

---

## Phase 3: Frontend Message Display

### 3.1 Messages Store Enhancement
**File**: `frontend/src/stores/messages.ts`

Add handlers for new WebSocket message types:
```typescript
export function handleChatMessage(event: ChatMessageEvent) {
  // Add or update message in store
}

export function handleChatMessageUpdate(event: ChatUpdateEvent) {
  // Append content delta to existing message
}

export function handleChatToolCall(event: ChatToolCallEvent) {
  // Add tool call to current assistant message
}

export function handleChatToolResult(event: ChatToolResultEvent) {
  // Update tool call with result
}
```

### 3.2 Session Page Updates
**File**: `frontend/src/pages/Session.tsx`

1. Remove "Terminal mode active" notice in chat view
2. Wire up new WebSocket message handlers
3. Messages populate automatically from backend
4. Keep existing InputBar for sending messages

### 3.3 MessageBubble Enhancement
**File**: `frontend/src/components/chat/MessageBubble.tsx`

Current component already handles:
- User/assistant styling
- Tool calls (collapsible)
- Streaming indicator
- Markdown rendering

Enhancements needed:
- Handle streaming content updates smoothly
- Show "Claude is thinking..." state between user message and first content
- Improve tool call grouping (multiple sequential tool calls)

---

## Phase 4: Transcript File Integration (Verification)

### 4.1 Transcript Parser
**File**: `crates/clauset-core/src/transcript.rs` (new)

- Parse Claude's `transcript.jsonl` file
- Extract structured conversation history
- Used on `Stop` hook to verify/correct extracted messages
- Handle recovery if terminal parsing missed content

### 4.2 Session End Processing
- On `SessionEnd` or periodic checkpoints:
  - Read transcript file
  - Compare with extracted messages
  - Reconcile any discrepancies
  - Persist final message history

---

## Phase 5: Hook Enhancements

### 5.1 Hook Data Enrichment
No new hooks needed - existing hooks provide:
- `UserPromptSubmit.prompt` → Full user message text
- `PreToolUse.tool_*` → Tool invocation details
- `PostToolUse.tool_response` → Tool output
- `Stop.stop_hook_active` → Response completion

### 5.2 Forward User Prompt to ChatProcessor
**File**: `crates/clauset-server/src/routes/hooks.rs`

On `UserPromptSubmit`:
1. Create user `ChatMessage`
2. Broadcast immediately
3. Start building assistant message

---

## Implementation Order

### Step 1: Types & Processor Skeleton
1. Create `crates/clauset-types/src/chat.rs` with message types
2. Create `crates/clauset-core/src/chat_processor.rs` skeleton
3. Add `ProcessEvent::ChatMessage` variants

### Step 2: Hook-based Messages
1. Wire `UserPromptSubmit` → User message creation
2. Wire `PreToolUse`/`PostToolUse` → Tool call tracking
3. Wire `Stop` → Message completion
4. Test: Verify hooks create messages (without text content)

### Step 3: Terminal Text Extraction
1. Implement ANSI stripping
2. Implement text block detection
3. Wire terminal output → ChatProcessor
4. Implement streaming content emission
5. Test: Verify Claude's text appears in chat

### Step 4: WebSocket Integration
1. Add new WS message types
2. Subscribe to ChatMessage events in session WS handler
3. Broadcast to clients
4. Test: Verify messages reach frontend

### Step 5: Frontend Integration
1. Add WS message handlers to Session.tsx
2. Update messages store with new handlers
3. Remove "Terminal mode active" notice
4. Test: End-to-end chat display

### Step 6: Polish & Edge Cases
1. Handle rapid tool sequences
2. Handle context compaction (`PreCompact`)
3. Transcript verification integration
4. Error recovery (reconnect, missed messages)
5. Persistence (optional - currently ephemeral)

---

## Files to Modify

### New Files
- `crates/clauset-types/src/chat.rs` - Chat message types
- `crates/clauset-core/src/chat_processor.rs` - Message extraction logic
- `crates/clauset-core/src/transcript.rs` - Transcript file parser

### Modified Files
- `crates/clauset-types/src/lib.rs` - Export chat module
- `crates/clauset-core/src/lib.rs` - Export chat_processor
- `crates/clauset-core/src/session.rs` - Add ChatProcessor to SessionBuffers
- `crates/clauset-core/src/buffer.rs` - Feed output to ChatProcessor
- `crates/clauset-core/src/process.rs` - Event variants for chat messages
- `crates/clauset-server/src/routes/hooks.rs` - Forward events to ChatProcessor
- `crates/clauset-server/src/ws/messages.rs` - New WS message types
- `crates/clauset-server/src/ws/session.rs` - Broadcast chat messages
- `frontend/src/stores/messages.ts` - New message handlers
- `frontend/src/pages/Session.tsx` - Wire up handlers, remove notice
- `frontend/src/lib/ws.ts` - Handle new message types

---

## Testing Strategy

1. **Unit tests**: ChatProcessor state machine, ANSI stripping, text extraction
2. **Integration tests**: Hook → ChatMessage flow
3. **Manual testing**:
   - Create session, send prompts via terminal
   - Verify chat view shows messages
   - Toggle between term/chat views
   - Test tool-heavy conversations
   - Test long conversations
   - Test reconnection/recovery

---

## Non-Goals (Explicit Exclusions)
- Chat-only sessions (no terminal) - NOT implementing
- API/SDK usage - NOT using
- Message persistence to DB - Can add later if needed
- Chat input bypassing terminal - Messages still go through terminal

---

## Risk Mitigation

1. **Terminal parsing fragility**: Use transcript file as verification backup
2. **Performance**: ChatProcessor runs in parallel, doesn't block terminal
3. **State desync**: Transcript reconciliation on Stop hook
4. **Regression risk**: Chat mode is additive - terminal view unchanged
