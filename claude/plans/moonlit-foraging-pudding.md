# Interactive Slash Command Support for Chat Mode

## Goal
Enable complete one-to-one parity between chat mode and terminal mode for all slash command workflows, with native chat UI (cards, buttons, selections) instead of glitchy ANSI terminal rendering.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│  Claude Code                                                 │
│  ┌──────────────────┐    ┌───────────────────────────────┐  │
│  │  /model command  │───▶│  AskUserQuestion tool call    │  │
│  │  /config command │    │  (questions + options JSON)   │  │
│  │  Custom commands │    └──────────────┬────────────────┘  │
│  └──────────────────┘                   │                    │
└─────────────────────────────────────────│────────────────────┘
                                          │ PreToolUse hook
                                          ▼
┌─────────────────────────────────────────────────────────────┐
│  Clauset Backend                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  hooks.rs: Intercept AskUserQuestion tool_input      │   │
│  │  → Parse questions array                              │   │
│  │  → Create InteractiveQuestion structs                 │   │
│  │  → Broadcast InteractiveEvent via WebSocket           │   │
│  └────────────────────────────────┬─────────────────────┘   │
│                                   │                          │
│  ┌────────────────────────────────▼─────────────────────┐   │
│  │  websocket.rs: Handle InteractiveChoice messages     │   │
│  │  → Validate selection                                 │   │
│  │  → Convert to PTY input (number + Enter)              │   │
│  │  → Send to session PTY                                │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                                          │
                                          ▼ WebSocket
┌─────────────────────────────────────────────────────────────┐
│  Clauset Frontend (Chat Mode)                                │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  QuestionCard.tsx: Native UI for selections          │   │
│  │  - Radio buttons for single-select                    │   │
│  │  - Checkboxes for multi-select                        │   │
│  │  - Submit/Cancel buttons                              │   │
│  └──────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  TextPromptCard.tsx: Native UI for text input        │   │
│  │  - Textarea with submit                               │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Implementation Steps

### Step 1: Type Definitions
**Files to create/modify:**
- `crates/clauset-types/src/interactive.rs` (new)
- `crates/clauset-types/src/lib.rs` (add export)
- `crates/clauset-types/src/ws.rs` (add message types)

```rust
// interactive.rs - Core types
pub struct InteractiveQuestion {
    pub id: String,
    pub header: String,           // Short label (e.g., "Model")
    pub question: String,         // Full question text
    pub options: Vec<QuestionOption>,
    pub multi_select: bool,
}

pub struct QuestionOption {
    pub index: usize,             // 1-based for PTY response
    pub label: String,
    pub description: Option<String>,
}

pub enum InteractiveEvent {
    QuestionPresented { session_id: Uuid, question: InteractiveQuestion },
    InteractionComplete { session_id: Uuid },
}

// ws.rs additions
pub enum WsClientMessage {
    // ... existing
    InteractiveChoice { question_id: String, selected_indices: Vec<usize> },
    InteractiveText { response: String },
    InteractiveCancel,
}

pub enum WsServerMessage {
    // ... existing
    Interactive { event: InteractiveEvent },
}
```

### Step 2: Backend Hook Integration
**Files to modify:**
- `crates/clauset-server/src/routes/hooks.rs`

In `receive()` function, after parsing HookEvent:
```rust
// Intercept AskUserQuestion tool
if let HookEvent::PreToolUse { tool_name, tool_input, session_id, .. } = &event {
    if tool_name == "AskUserQuestion" {
        if let Some(questions) = parse_ask_user_question(tool_input) {
            for q in questions {
                let event = InteractiveEvent::QuestionPresented {
                    session_id: *session_id,
                    question: q,
                };
                let _ = state.session_manager.broadcast_event(
                    ProcessEvent::Interactive(event)
                );
            }
        }
    }
}

fn parse_ask_user_question(input: &Value) -> Option<Vec<InteractiveQuestion>> {
    let questions = input.get("questions")?.as_array()?;
    questions.iter().filter_map(|q| {
        Some(InteractiveQuestion {
            id: uuid::Uuid::new_v4().to_string(),
            header: q.get("header")?.as_str()?.to_string(),
            question: q.get("question")?.as_str()?.to_string(),
            multi_select: q.get("multiSelect").and_then(|v| v.as_bool()).unwrap_or(false),
            options: q.get("options")?.as_array()?.iter().enumerate().filter_map(|(i, opt)| {
                Some(QuestionOption {
                    index: i + 1,
                    label: opt.get("label")?.as_str()?.to_string(),
                    description: opt.get("description").and_then(|v| v.as_str()).map(String::from),
                })
            }).collect(),
        })
    }).collect::<Vec<_>>().into()
}
```

### Step 3: WebSocket Handler
**Files to modify:**
- `crates/clauset-server/src/websocket.rs`

Add handling for interactive messages in recv_task:
```rust
WsClientMessage::InteractiveChoice { question_id, selected_indices } => {
    // Generate PTY input: "1" for single, "1,2,3" for multi
    let input = if selected_indices.len() == 1 {
        format!("{}\r", selected_indices[0])
    } else {
        format!("{}\r", selected_indices.iter().map(|i| i.to_string()).collect::<Vec<_>>().join(","))
    };
    let _ = state_clone.session_manager.send_input(session_id, &input).await;
}

WsClientMessage::InteractiveCancel => {
    // Send Ctrl+C (ETX)
    let _ = state_clone.session_manager.send_terminal_input(session_id, &[0x03]).await;
}
```

### Step 4: Frontend Store
**Files to create:**
- `frontend/src/stores/interactive.ts`

```typescript
import { createStore } from 'solid-js/store';

export interface InteractiveQuestion {
  id: string;
  header: string;
  question: string;
  options: Array<{ index: number; label: string; description?: string }>;
  multiSelect: boolean;
}

type InteractiveState =
  | { type: 'idle' }
  | { type: 'question'; question: InteractiveQuestion };

const [state, setState] = createStore<{ sessions: Map<string, InteractiveState> }>({
  sessions: new Map(),
});

export function getInteractiveState(sessionId: string): InteractiveState {
  return state.sessions.get(sessionId) ?? { type: 'idle' };
}

export function handleInteractiveEvent(event: any) {
  if (event.type === 'question_presented') {
    setState('sessions', prev => {
      const next = new Map(prev);
      next.set(event.session_id, { type: 'question', question: event.question });
      return next;
    });
  } else if (event.type === 'interaction_complete') {
    clearInteractiveState(event.session_id);
  }
}

export function clearInteractiveState(sessionId: string) {
  setState('sessions', prev => {
    const next = new Map(prev);
    next.set(sessionId, { type: 'idle' });
    return next;
  });
}
```

### Step 5: Frontend Components
**Files to create:**
- `frontend/src/components/interactive/QuestionCard.tsx`

```tsx
interface QuestionCardProps {
  question: InteractiveQuestion;
  onSelect: (indices: number[]) => void;
  onCancel: () => void;
}

export function QuestionCard(props: QuestionCardProps) {
  const [selected, setSelected] = createSignal<number[]>([]);

  return (
    <div class="interactive-card">
      <header class="card-header">{props.question.header}</header>
      <p class="question-text">{props.question.question}</p>

      <div class="options">
        <For each={props.question.options}>
          {(option) => (
            <button
              class={`option-btn ${selected().includes(option.index) ? 'selected' : ''}`}
              onClick={() => {
                if (props.question.multiSelect) {
                  setSelected(prev => prev.includes(option.index)
                    ? prev.filter(i => i !== option.index)
                    : [...prev, option.index]);
                } else {
                  props.onSelect([option.index]);
                }
              }}
            >
              <span class="label">{option.label}</span>
              <Show when={option.description}>
                <span class="desc">{option.description}</span>
              </Show>
            </button>
          )}
        </For>
      </div>

      <Show when={props.question.multiSelect}>
        <button class="submit-btn" onClick={() => props.onSelect(selected())}>
          Submit ({selected().length} selected)
        </button>
      </Show>

      <button class="cancel-btn" onClick={props.onCancel}>Cancel</button>
    </div>
  );
}
```

### Step 6: Session Page Integration
**Files to modify:**
- `frontend/src/pages/Session.tsx`

Add to WebSocket message handler:
```typescript
case 'interactive':
  handleInteractiveEvent(msg.event);
  break;
```

Add to chat view JSX (before InputBar):
```tsx
<Show when={getInteractiveState(params.id).type === 'question'}>
  <QuestionCard
    question={(getInteractiveState(params.id) as { question: InteractiveQuestion }).question}
    onSelect={(indices) => {
      wsManager?.send({
        type: 'interactive_choice',
        question_id: q.id,
        selected_indices: indices,
      });
      clearInteractiveState(params.id);
    }}
    onCancel={() => {
      wsManager?.send({ type: 'interactive_cancel' });
      clearInteractiveState(params.id);
    }}
  />
</Show>
```

### Step 7: CSS Styling
**Files to modify:**
- `frontend/src/index.css`

```css
.interactive-card {
  background: var(--surface);
  border: 2px solid var(--border);
  border-radius: 8px;
  padding: 16px;
  margin: 12px;
  box-shadow: 4px 4px 0 var(--shadow);
}

.interactive-card .card-header {
  font-family: 'JetBrains Mono', monospace;
  font-size: 12px;
  text-transform: uppercase;
  color: var(--accent);
  margin-bottom: 8px;
}

.interactive-card .option-btn {
  display: flex;
  flex-direction: column;
  width: 100%;
  padding: 12px;
  margin: 8px 0;
  border: 2px solid var(--border);
  border-radius: 6px;
  background: var(--bg);
  cursor: pointer;
  text-align: left;
}

.interactive-card .option-btn.selected {
  border-color: var(--accent);
  background: var(--accent-bg);
}

.interactive-card .option-btn .label {
  font-weight: 600;
}

.interactive-card .option-btn .desc {
  font-size: 13px;
  color: var(--text-muted);
  margin-top: 4px;
}
```

## File Summary

| File | Action | Description |
|------|--------|-------------|
| `crates/clauset-types/src/interactive.rs` | Create | Type definitions |
| `crates/clauset-types/src/lib.rs` | Modify | Export interactive module |
| `crates/clauset-types/src/ws.rs` | Modify | Add message variants |
| `crates/clauset-core/src/process.rs` | Modify | Add ProcessEvent::Interactive |
| `crates/clauset-server/src/routes/hooks.rs` | Modify | Intercept AskUserQuestion |
| `crates/clauset-server/src/websocket.rs` | Modify | Handle interactive messages |
| `frontend/src/stores/interactive.ts` | Create | State management |
| `frontend/src/components/interactive/QuestionCard.tsx` | Create | Question UI |
| `frontend/src/pages/Session.tsx` | Modify | Integrate components |
| `frontend/src/index.css` | Modify | Styling |

## Testing Plan

1. **AskUserQuestion via custom command** - Create test command that uses AskUserQuestion
2. **Built-in /model command** - Verify model selection renders as native UI
3. **Multi-select questions** - Test checkbox behavior
4. **Cancel flow** - Verify Ctrl+C sent to PTY
5. **Timeout handling** - Questions auto-dismiss after 60s
6. **WebSocket reconnect** - State cleared on reconnect

## Risk Mitigations

1. **AskUserQuestion schema changes** - Parse defensively with Option types
2. **PTY timing** - Add 50ms delay before sending selection
3. **State sync issues** - Backend is source of truth, frontend resets on reconnect
