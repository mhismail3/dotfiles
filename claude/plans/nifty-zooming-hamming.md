# Implementation Plan: Streaming Intermediate Output (Clean Architecture)

## Problem Statement
Currently, Clauset's chat mode shows tool calls as they happen but doesn't display Claude's intermediate thinking/reasoning text. The user only sees tool call badges (Bash, Read, etc.) with the final response appearing at the end.

## Confirmed Requirements
- **UI Design**: Collapsible with preview (truncated ~60 chars, expandable to full)
- **Timing**: Real-time streaming as Claude writes to transcript
- **Scope**: All content blocks - thinking, text deltas, tool_use, tool_result (full Claude2Stream parity)

---

## First Principles Architecture Analysis

### Current System: Dual Data Sources with Overlap

| Data | Hooks | JSONL Transcript |
|------|-------|------------------|
| **Thinking content** | ❌ No | ✅ Yes |
| **Text deltas** | ❌ No | ✅ Yes |
| **Tool use/result** | ✅ PreToolUse/PostToolUse | ✅ tool_use/tool_result blocks |
| **User prompts** | ✅ UserPromptSubmit | ✅ user message entry |
| **Token counts** | ✅ context_window | ❌ No |
| **Model info** | ✅ model | ❌ No |
| **Permissions** | ✅ PermissionRequest (interactive) | ❌ No |
| **Subagent events** | ✅ SubagentStart/Stop | ❌ No |
| **Session lifecycle** | ✅ SessionStart/End/PreCompact | ❌ No |

### The Problem: Adding JSONL watching would create duplication
- Hooks already create `ToolCallStart`/`ToolCallComplete` events
- JSONL watcher would create the same from `tool_use`/`tool_result` blocks
- Two code paths doing the same thing = bugs, race conditions, inconsistency

---

## Clean Architecture: Single Source of Truth for Each Concern

### JSONL Transcript (PRIMARY for content streaming)
**Use for ALL conversation content:**
- User messages
- Assistant text responses
- Thinking blocks
- Tool use blocks
- Tool result blocks

### Hooks (METADATA and LIFECYCLE only)
**Keep only for data JSONL doesn't provide:**
- Session lifecycle (SessionStart, SessionEnd)
- Token/cost metrics (context_window) → StatusBar, ActivityUpdate
- Permission interception (PermissionRequest) → Interactive approval UI
- Subagent events (SubagentStart/Stop) → Not in transcript
- Model information → Display in header
- Compaction events (PreCompact)

### Remove from Hook Processing:
- ❌ `UserPromptSubmit` → No longer creates user message (JSONL does)
- ❌ `PreToolUse` → No longer creates ToolCallStart (JSONL does)
- ❌ `PostToolUse` → No longer creates ToolCallComplete (JSONL does)
- ❌ `Stop` transcript reading → TranscriptWatcher handles this continuously

---

## Implementation Steps

### Phase 1: Backend - Transcript Watcher Module (NEW)

**File: `crates/clauset-core/src/transcript_watcher.rs`**

```rust
/// Watches a Claude Code JSONL transcript file and emits content events in real-time.
pub struct TranscriptWatcher {
    path: PathBuf,
    file_position: u64,           // Track where we left off
    watcher: RecommendedWatcher,  // notify crate file watcher
    event_tx: mpsc::Sender<TranscriptEvent>,
}

pub enum TranscriptEvent {
    /// User submitted a message
    UserMessage { id: String, content: String },

    /// Assistant started a new turn
    AssistantTurnStart { message_id: String },

    /// Thinking content block
    Thinking { message_id: String, content: String },

    /// Text content block
    Text { message_id: String, content: String },

    /// Tool use block (Claude decided to use a tool)
    ToolUse { message_id: String, id: String, name: String, input: Value },

    /// Tool result block
    ToolResult { message_id: String, tool_use_id: String, content: Value, is_error: bool },

    /// End of assistant turn
    AssistantTurnEnd { message_id: String },
}

impl TranscriptWatcher {
    /// Start watching a transcript file. Called when SessionStart provides transcript_path.
    pub fn new(path: PathBuf, event_tx: mpsc::Sender<TranscriptEvent>) -> Result<Self>;

    /// Process new content added to the file (called on file change events)
    async fn process_new_content(&mut self) -> Result<()>;

    /// Parse a JSONL line into transcript events
    fn parse_line(&self, line: &str) -> Option<Vec<TranscriptEvent>>;
}
```

Key implementation details:
- Uses `notify` crate for cross-platform file watching
- Handles partial lines (file being written mid-line)
- Tracks byte position to only read new content
- Parses all content block types from assistant messages

### Phase 2: Backend - Add Thinking ContentBlock Type

**File: `crates/clauset-types/src/claude.rs`**

```rust
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ContentBlock {
    Text { text: String },
    Thinking { thinking: String },  // ADD - Claude's reasoning
    ToolUse { id: String, name: String, input: Value },
    ToolResult { tool_use_id: String, content: Value, is_error: bool },
}
```

### Phase 3: Backend - Extend Chat Events

**File: `crates/clauset-types/src/chat.rs`**

```rust
pub enum ChatEvent {
    Message { session_id: Uuid, message: ChatMessage },
    ContentDelta { session_id: Uuid, message_id: String, delta: String },
    ThinkingDelta { session_id: Uuid, message_id: String, delta: String },  // ADD
    ToolCallStart { session_id: Uuid, message_id: String, tool_call: ChatToolCall },
    ToolCallComplete { session_id: Uuid, message_id: String, tool_call_id: String, output: String, is_error: bool },
    MessageComplete { session_id: Uuid, message_id: String },
}
```

### Phase 4: Backend - Refactor ChatProcessor

**File: `crates/clauset-core/src/chat_processor.rs`**

Major refactor to use TranscriptWatcher as primary content source:

```rust
pub struct ChatProcessor {
    sessions: Arc<RwLock<HashMap<Uuid, SessionChatState>>>,
    transcript_watchers: Arc<RwLock<HashMap<Uuid, TranscriptWatcher>>>,  // ADD
    store: Option<Arc<InteractionStore>>,
}

impl ChatProcessor {
    /// Start watching transcript when SessionStart provides path
    pub async fn start_transcript_watcher(&self, session_id: Uuid, transcript_path: &str);

    /// Convert TranscriptEvents to ChatEvents
    async fn handle_transcript_event(&self, session_id: Uuid, event: TranscriptEvent) -> Vec<ChatEvent>;

    /// Process hook event - NOW ONLY handles metadata/lifecycle
    pub async fn process_hook_event(&self, event: &HookEvent) -> Vec<ChatEvent> {
        match event {
            // Keep: Session lifecycle, permissions, subagents, metrics
            HookEvent::SessionStart { transcript_path, .. } => {
                self.start_transcript_watcher(session_id, transcript_path).await;
                vec![]  // No chat events from this
            }
            HookEvent::PermissionRequest { .. } => {
                // Still handle permission UI
            }
            HookEvent::SubagentStart { .. } | HookEvent::SubagentStop { .. } => {
                // Still handle subagent events (not in transcript)
            }
            // REMOVE: No longer process these for chat messages
            HookEvent::UserPromptSubmit { .. } => vec![],  // TranscriptWatcher handles
            HookEvent::PreToolUse { .. } => vec![],        // TranscriptWatcher handles
            HookEvent::PostToolUse { .. } => vec![],       // TranscriptWatcher handles
            HookEvent::Stop { .. } => vec![],              // TranscriptWatcher handles turn end
            _ => vec![],
        }
    }
}
```

### Phase 5: Backend - WebSocket Message Types

**File: `crates/clauset-types/src/ws.rs`**

```rust
pub enum WsServerMessage {
    // Existing...
    ChatEvent { event: ChatEvent },  // Already handles all ChatEvent variants
    // ThinkingDelta will flow through ChatEvent
}
```

**File: `crates/clauset-server/src/websocket.rs`**

Update to broadcast TranscriptWatcher events:
- Hook route continues broadcasting activity/metrics updates
- TranscriptWatcher events flow through ChatProcessor → broadcast

### Phase 6: Frontend - Message Store Updates

**File: `frontend/src/stores/messages.ts`**

```typescript
export interface Message {
  id: string;
  role: 'user' | 'assistant' | 'system';
  content: string;
  thinkingContent?: string;      // ADD - Accumulated thinking text
  thinkingBlocks?: ThinkingBlock[];  // ADD - Multiple thinking blocks per message
  toolCalls?: ToolCall[];
  timestamp: number;
  isStreaming?: boolean;
  // ... existing fields
}

interface ThinkingBlock {
  content: string;
  timestamp: number;
}

// Update handler
export function handleChatEvent(event: ChatEvent) {
  switch (event.type) {
    // ... existing cases

    case 'thinking_delta':
      setMessages(prev => {
        const msgs = prev.get(event.session_id) ?? [];
        return new Map(prev).set(
          event.session_id,
          msgs.map(m => m.id === event.message_id
            ? { ...m, thinkingContent: (m.thinkingContent ?? '') + event.delta }
            : m
          )
        );
      });
      break;
  }
}
```

### Phase 7: Frontend - Thinking Block UI

**File: `frontend/src/components/chat/MessageBubble.tsx`**

```tsx
function ThinkingBlock(props: { content: string }) {
  const [expanded, setExpanded] = createSignal(false);

  const preview = () => {
    const text = props.content.replace(/\n/g, ' ').trim();
    return text.length > 60 ? text.slice(0, 60) + '...' : text;
  };

  return (
    <div style={{
      "border-radius": '8px',
      border: '1px solid var(--color-bg-overlay)',
      background: 'var(--color-bg-surface)',
      overflow: 'hidden',
      "border-left": '3px solid var(--color-text-muted)',
      "margin-bottom": '8px',
    }}>
      <button
        onClick={() => setExpanded(!expanded())}
        style={{
          width: '100%',
          display: 'flex',
          "align-items": 'center',
          gap: '8px',
          padding: '6px 10px',
          background: 'transparent',
          border: 'none',
          cursor: 'pointer',
        }}
      >
        <span style={{ color: 'var(--color-text-muted)', "font-size": '12px' }}>💭</span>
        <span class="text-mono" style={{
          color: 'var(--color-text-muted)',
          "font-size": '11px',
          "font-style": 'italic',
        }}>
          thinking
        </span>
        <span style={{
          flex: 1,
          overflow: 'hidden',
          "text-overflow": 'ellipsis',
          "white-space": 'nowrap',
          color: 'var(--color-text-muted)',
          "font-size": '12px',
          "font-style": 'italic',
        }}>
          {preview()}
        </span>
        <ChevronIcon expanded={expanded()} />
      </button>

      <Show when={expanded()}>
        <pre style={{
          padding: '8px 10px',
          "border-top": '1px solid var(--color-bg-overlay)',
          "font-size": '12px',
          color: 'var(--color-text-secondary)',
          "white-space": 'pre-wrap',
          "word-break": 'break-word',
          margin: 0,
        }}>
          {props.content}
        </pre>
      </Show>
    </div>
  );
}

// In MessageBubble component, add before content:
<Show when={props.message.thinkingContent}>
  <ThinkingBlock content={props.message.thinkingContent!} />
</Show>
```

---

## Critical Files Summary

| File | Change Type | Purpose |
|------|-------------|---------|
| `crates/clauset-core/src/transcript_watcher.rs` | **NEW** | Real-time JSONL file watching |
| `crates/clauset-core/src/lib.rs` | Modify | Export transcript_watcher module |
| `crates/clauset-core/Cargo.toml` | Modify | Add `notify = "6.1"` |
| `crates/clauset-types/src/claude.rs` | Modify | Add `Thinking` ContentBlock variant |
| `crates/clauset-types/src/chat.rs` | Modify | Add `ThinkingDelta` ChatEvent |
| `crates/clauset-core/src/chat_processor.rs` | **Refactor** | Integrate TranscriptWatcher, remove hook content handling |
| `crates/clauset-server/src/routes/hooks.rs` | Modify | Remove content processing, keep metadata |
| `frontend/src/stores/messages.ts` | Modify | Add thinkingContent, handle new event |
| `frontend/src/components/chat/MessageBubble.tsx` | Modify | Add ThinkingBlock component |

---

## What Hooks Still Provide (Unique Value)

| Hook | Kept | Reason |
|------|------|--------|
| SessionStart | ✅ | Provides transcript_path to start watcher, model info |
| SessionEnd | ✅ | Session cleanup, stop watcher |
| PermissionRequest | ✅ | Interactive permission UI (not in transcript) |
| SubagentStart/Stop | ✅ | Task agent lifecycle (not in transcript) |
| PreCompact | ✅ | Context compaction notification |
| context_window | ✅ | Token/cost metrics for ActivityUpdate |
| UserPromptSubmit | ⚠️ Partial | Only for context_window update, not message creation |
| PreToolUse | ❌ Remove | TranscriptWatcher handles |
| PostToolUse | ❌ Remove | TranscriptWatcher handles |
| Stop | ⚠️ Partial | Only for context_window update |

---

## Migration Path

1. **Phase 1**: Add TranscriptWatcher module (additive, no breaking changes)
2. **Phase 2**: Wire up TranscriptWatcher events to WebSocket
3. **Phase 3**: Add frontend ThinkingBlock UI
4. **Phase 4**: Gradually disable hook content processing (behind feature flag)
5. **Phase 5**: Remove legacy hook content code once stable

---

## Testing Strategy

1. **Unit tests** for TranscriptWatcher:
   - Parse all content block types
   - Handle partial lines
   - Track file position correctly
   - Handle file truncation (new session)

2. **Integration test**:
   - Start session → hook provides transcript_path
   - User sends prompt → appears via JSONL
   - Claude thinks → thinking blocks appear
   - Claude uses tool → tool_use/tool_result appear
   - Response completes → all content visible

3. **Edge cases**:
   - Session resume (existing transcript file)
   - Rapid file updates
   - Large thinking blocks
   - Network reconnection during streaming

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| File locking by Claude Code | Use read-only access, handle EACCES gracefully |
| Performance with large files | Track position, only read new content |
| Partial lines during write | Buffer incomplete lines until newline |
| Race condition: hook vs JSONL | JSONL is authoritative for content, hooks for metadata |
| Session cleanup | Stop watcher on SessionEnd, timeout, or session removal |
