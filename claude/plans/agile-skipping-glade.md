# Chat Mode Implementation Plan

## Overview

Replace terminal view with a chat interface using stream-JSON mode. Claude's text responses appear as chat bubbles, tool calls appear as inline collapsible cards, and user messages appear as right-aligned bubbles.

**Key Decisions:**
- Chat-only view (no terminal toggle)
- Stream-JSON mode for structured data
- Inline collapsed tool calls within assistant messages
- Hooks continue working for dashboard activity

---

## Architecture Summary

```
Claude CLI (stream-json)
        │
        ├── stdout (JSON lines) ─────────────────────┐
        │                                            │
        └── hooks (HTTP POST) ───────────────────────┼──────────────┐
                                                     │              │
                                                     ▼              ▼
                                              ChatEventProcessor   HookProcessor
                                              (chat text/tools)    (activity/status)
                                                     │              │
                                                     └──────┬───────┘
                                                            │
                                                     WebSocket
                                                            │
                                                     Frontend (ChatView)
```

---

## Phase 1: Backend - WebSocket Message Types

### Files to Modify

**`crates/clauset-types/src/ws.rs`** - Add new message types:

```rust
// Server → Client
TextChunk { message_id, delta, is_final, seq }
ToolUseStart { message_id, tool_use_id, tool_name, input }
ToolUseResult { tool_use_id, output_preview, is_error }
MessageDone { message_id, stop_reason, usage }
UserMessageAck { client_id, message_id }
MetricsUpdate { total_cost_usd, input_tokens, output_tokens, context_percent, model }

// Client → Server
ChatInput { content, client_id }
SyncMessages { last_message_id }
```

**`crates/clauset-types/src/lib.rs`** - Add chat module export

---

## Phase 2: Backend - Chat Event Processor

### New File

**`crates/clauset-server/src/chat_processor.rs`**

Transforms `ClaudeEvent` from stream-JSON into WebSocket chat messages:

- `ClaudeEvent::Assistant` → Extract `ContentBlock::Text`, `ContentBlock::ToolUse`, `ContentBlock::ToolResult`
- `ClaudeEvent::Result` → Extract cost/usage for `MetricsUpdate`
- Track message state for streaming accumulation

### Files to Modify

**`crates/clauset-server/src/event_processor.rs`**

Add handling for `ProcessEvent::Claude(ClaudeEvent)`:
- Route to chat processor for stream-JSON sessions
- Extract cost/usage from Result events

**`crates/clauset-server/src/websocket.rs`**

- Handle new `WsClientMessage::ChatInput` → call `session_manager.send_input()`
- Handle `WsClientMessage::SyncMessages` → return message history
- Forward chat events to WebSocket

**`crates/clauset-server/src/routes/sessions.rs`**

- Default new sessions to `SessionMode::StreamJson` (chat mode)
- Add `chat_mode: bool` option to `CreateSessionRequest`

---

## Phase 3: Frontend - Chat Components

### New Files

**`frontend/src/components/chat/ChatView.tsx`**
- Main container replacing TerminalView
- iOS keyboard handling via `useKeyboard()`
- Scroll management with auto-scroll and position preservation

**`frontend/src/components/chat/ChatMessages.tsx`**
- Scrollable message list
- Groups messages by role
- Shows streaming indicator

**`frontend/src/components/chat/MessageGroup.tsx`**
- Groups assistant message with its tool calls
- Renders: tool calls first, then text content

**`frontend/src/components/chat/ToolCallCard.tsx`**
- Collapsible card for tool invocations
- Shows: icon, name, summary (collapsed)
- Expands to show input/output
- States: pending, complete, error

**`frontend/src/components/chat/StreamingIndicator.tsx`**
- Animated typing indicator (three dots)
- Shows when Claude is generating

### Files to Modify

**`frontend/src/pages/Session.tsx`**
- Remove TerminalView for stream-JSON sessions
- Add ChatView as primary view
- Handle new WS message types (TextChunk, ToolUse, etc.)
- Wire up send handler for ChatInput

**`frontend/src/stores/messages.ts`**
- Add `status: 'pending' | 'complete' | 'error'` to ToolCall
- Add `getOrCreateStreamingMessage()` for incremental updates
- Add `markMessageComplete()`

**`frontend/src/components/chat/MessageBubble.tsx`**
- Remove inline tool call rendering (moved to MessageGroup)
- Enhanced markdown support

**`frontend/src/components/chat/InputBar.tsx`**
- Always visible at bottom (iMessage style)
- User types message, clicks Send → WebSocket ChatInput → stdin to Claude
- Add loading state during send
- Disable Send button while Claude is responding (but keep input enabled for typing)

---

## Phase 4: Hooks Integration

### No Hook Modifications Required

Hooks and stream-JSON are complementary:

| Source | Provides |
|--------|----------|
| Hooks | RecentActions, status transitions, interaction persistence |
| Stream-JSON | Chat text, tool use blocks, cost/usage stats |

### Verification

Confirm hooks fire in stream-JSON mode:
```bash
claude -p --output-format stream-json "test"
# Hooks should still POST to /api/hooks
```

If hooks don't fire, fallback: synthesize events from stream-JSON parsing.

---

## Phase 5: Scroll Behavior

Implement scroll state machine:
- `AUTO_SCROLL`: User at bottom, auto-scroll on new content
- `USER_SCROLLED`: User scrolled up, preserve position
- Show "scroll to bottom" FAB when scrolled up + new content

---

## Phase 6: Message Persistence

**`crates/clauset-server/src/routes/sessions.rs`**

Add REST endpoint for message history:
```
GET /api/sessions/{id}/messages → { messages: Message[] }
```

On reconnect:
1. Client connects to WebSocket
2. Client fetches message history via REST
3. Client renders cached messages
4. Client subscribes to new WS events

---

## Implementation Order

### Sprint 1: Core Types (Backend)
1. Add WS message types to `ws.rs`
2. Create `chat_processor.rs` skeleton
3. Wire up `ProcessEvent::Claude` in `event_processor.rs`

### Sprint 2: Input Pipeline (Backend)
1. Add `ChatInput` handler to WebSocket
2. Implement user message acking
3. Verify stdin communication works

### Sprint 3: Chat UI (Frontend)
1. Create `ChatView.tsx` with layout
2. Create `ChatMessages.tsx` with scroll
3. Handle Text/ToolUse/ToolResult WS events
4. Wire up InputBar send

### Sprint 4: Tool Cards (Frontend)
1. Create `ToolCallCard.tsx` with collapse/expand
2. Create `MessageGroup.tsx` for grouping
3. Add pending/complete/error states

### Sprint 5: Polish
1. Add StreamingIndicator
2. Implement scroll-to-bottom FAB
3. iOS keyboard handling
4. Error states and loading states

### Sprint 6: Persistence
1. Add message history endpoint
2. Implement reconnection loading
3. Test full flow

---

## Critical Files Summary

### Backend (Rust)
- `crates/clauset-types/src/ws.rs` - Add chat message types
- `crates/clauset-server/src/chat_processor.rs` - NEW: Transform ClaudeEvent → WS messages
- `crates/clauset-server/src/event_processor.rs` - Handle ProcessEvent::Claude
- `crates/clauset-server/src/websocket.rs` - Chat message handling
- `crates/clauset-server/src/routes/sessions.rs` - Default to chat mode

### Frontend (TypeScript/SolidJS)
- `frontend/src/pages/Session.tsx` - Swap in ChatView, handle new WS types
- `frontend/src/stores/messages.ts` - Add streaming/status tracking
- `frontend/src/components/chat/ChatView.tsx` - NEW: Main chat container
- `frontend/src/components/chat/ChatMessages.tsx` - NEW: Message list
- `frontend/src/components/chat/MessageGroup.tsx` - NEW: Message+tools grouping
- `frontend/src/components/chat/ToolCallCard.tsx` - NEW: Collapsible tool card
- `frontend/src/components/chat/StreamingIndicator.tsx` - NEW: Typing indicator
- `frontend/src/components/chat/MessageBubble.tsx` - Remove tool rendering
- `frontend/src/components/chat/InputBar.tsx` - Add loading state

---

## Risk Mitigation

1. **Hooks not firing in stream-JSON**: Test early. Fallback: synthesize from ClaudeEvent parsing.

2. **Streaming text gaps**: Use sequence numbers. Client detects gaps, requests resync.

3. **Performance with long conversations**: Virtualize message list if >100 messages.

4. **iOS keyboard issues**: Reuse proven patterns from TerminalView keyboard handling.
