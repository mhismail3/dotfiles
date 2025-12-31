# Clauset Chat Mode - Feature Gap Analysis & Implementation Plan

## Goal
Identify and implement missing UI affordances to bring Clauset's chat mode into full parity with Claude Code CLI, ensuring users can intuitively access all features without switching to terminal mode.

## Feature Gaps Identified

### Critical Gaps (Must Have)

#### 1. Permission Approval/Deny UI
**CLI Behavior**: When Claude requests permission for a tool, user can approve/deny interactively
**Current Status**: Permission requests display as purple system pills with 🔐 icon, but **NO WAY TO INTERACT**
**Gap**: Users must switch to terminal to approve/deny permissions
**Files Involved**:
- `frontend/src/components/chat/MessageBubble.tsx` (displays permission_request)
- `frontend/src/pages/Session.tsx` (handles permission_request WS message)
- `crates/clauset-types/src/ws.rs` (PermissionRequest message type)

**Implementation**:
- Add "Allow" / "Deny" / "Allow All" buttons to permission request system message
- Send approval/denial back via WebSocket → PTY (send 'y'/'n'/'a' keystrokes)
- Show visual feedback on button press

#### 2. Mode Indicator & Switching (Plan Mode)
**CLI Behavior**: Clear indicator when in Plan Mode, with EnterPlanMode/ExitPlanMode tools
**Current Status**: `session?.mode` exists in placeholder but never populated; no visual indicator
**Gap**: Users can't see if they're in Plan Mode and can't toggle it from chat
**Files Involved**:
- `frontend/src/pages/Session.tsx` (status header area)
- `crates/clauset-types/src/hooks.rs` (could capture mode from hooks)
- `crates/clauset-server/src/routes/hooks.rs` (broadcast mode changes)

**Implementation**:
- Add mode indicator badge in session header (e.g., "PLAN MODE" badge)
- Capture mode state from EnterPlanMode/ExitPlanMode tool use events
- Add quick-toggle button or slash command `/plan` to enter plan mode
- Broadcast mode changes via WebSocket

#### 3. Interrupt/Cancel Button
**CLI Behavior**: Ctrl+C interrupts Claude mid-operation
**Current Status**: No interrupt capability in chat mode - Claude runs until completion
**Gap**: Can't stop Claude when it's stuck or going in wrong direction
**Files Involved**:
- `frontend/src/pages/Session.tsx` (chat view)
- `frontend/src/components/chat/InputBar.tsx` (could add stop button)
- `crates/clauset-core/src/session.rs` (needs interrupt signal handling)

**Implementation**:
- Show "Stop" button next to input when Claude is processing (streaming indicator active)
- Send Ctrl+C (SIGINT) signal to PTY via WebSocket message
- Visual feedback: change "Thinking..." to "Stopping..."
- Add backend handler for interrupt signal

### Important Gaps (Should Have)

#### 4. Allowed Tools Indicator
**CLI Behavior**: Shows which tools are auto-approved vs require permission
**Current Status**: No indication - users don't know what Claude can do freely
**Gap**: Users surprised by permission prompts; can't configure allowlist
**Files Involved**:
- `crates/clauset-types/src/hooks.rs` (has allowedTools in ContextWindow)
- Frontend (needs new component)

**Implementation**:
- Add "Allowed Tools" expandable section in session header or info drawer
- Parse and display from ContextWindow hook data
- Group by category (always allowed, session-allowed, needs permission)

#### 5. Context Window / Token Display
**CLI Behavior**: Status line shows model, cost, input/output tokens, context %
**Current Status**: Extracted via fragile regex from terminal output; not always accurate
**Gap**: Missing cache token breakdown; context % not visible
**Files Involved**:
- `frontend/src/pages/Session.tsx` (has `statusInfo` signal from regex parsing)
- `crates/clauset-server/src/routes/hooks.rs` (receives ContextUpdate events)
- `crates/clauset-types/src/ws.rs` (ContextUpdate message type exists)

**Implementation**:
- Use ContextUpdate WebSocket events instead of regex parsing
- Display in session header: Model | $0.68 | 29K/22K | Cache: 15K read, 5K write | 45%
- Add progress bar for context usage percentage
- Show cost accumulation during session

#### 6. Keyboard Shortcut Reference
**CLI Behavior**: Various shortcuts documented (Esc, Ctrl+C, etc.)
**Current Status**: Terminal toolbar has keys but no documentation
**Gap**: Users don't know available shortcuts in chat mode

**Implementation**:
- Add "?" button or `/shortcuts` command to show reference modal
- Document: Esc (cancel), / (commands), arrows (navigate), Enter (send)
- Consider Ctrl+Enter for multi-line, Shift+Enter for newline

### Nice to Have Gaps

#### 7. Session Settings Quick Access
**CLI Behavior**: Various settings via /config, /model, etc.
**Current Status**: Command picker works but requires knowing commands
**Gap**: No visual settings UI

**Implementation**:
- Add settings gear icon in session header
- Quick access to: model selection, permission mode, compact context
- Show current settings state

#### 8. Todo List Visibility
**CLI Behavior**: TodoWrite tool shows task progress in terminal
**Current Status**: TodoWrite renders in tool calls but not prominently displayed
**Gap**: Task progress not visible at a glance

**Implementation**:
- Add sticky todo panel or floating widget when tasks exist
- Show: pending/in-progress/completed counts
- Collapse/expand individual tasks

#### 9. Subagent/Task Progress
**CLI Behavior**: Shows when Task tool launches subagents
**Current Status**: SubagentStarted/Stopped show as blue/green system pills
**Gap**: No progress indication or way to see what subagent is doing

**Implementation**:
- Add expandable subagent panel showing active tasks
- Show agent type, status, and summary when complete

## Implementation Priority

### Phase 1: Critical Affordances (MVP)
1. **Permission Approval UI** - Without this, chat mode is incomplete
2. **Interrupt/Cancel Button** - Essential for control
3. **Mode Indicator** - Users need to know current state

### Phase 2: Information Display
4. **Context Window Display** - Replace regex with hook data
5. **Allowed Tools Indicator** - Transparency about capabilities

### Phase 3: Polish
6. **Keyboard Shortcuts Reference**
7. **Session Settings Quick Access**
8. **Todo List Widget**
9. **Subagent Progress Panel**

## Critical Files to Modify

### Backend
- `crates/clauset-types/src/ws.rs` - Add new message types (Interrupt, PermissionResponse)
- `crates/clauset-server/src/websocket.rs` - Handle interrupt/permission messages
- `crates/clauset-core/src/session.rs` - Add interrupt signal handling
- `crates/clauset-server/src/routes/hooks.rs` - Capture and broadcast mode changes

### Frontend
- `frontend/src/pages/Session.tsx` - Status header, mode indicator, interrupt button
- `frontend/src/components/chat/MessageBubble.tsx` - Permission approval buttons
- `frontend/src/components/chat/InputBar.tsx` - Stop button during processing
- `frontend/src/stores/messages.ts` - Handle permission responses
- New: `frontend/src/components/session/StatusBar.tsx` - Context/token display
- New: `frontend/src/components/session/ModeIndicator.tsx` - Plan mode badge

## Success Criteria
- [ ] Can approve/deny permissions from chat mode without switching to terminal
- [ ] Can see when Plan Mode is active
- [ ] Can interrupt Claude mid-operation
- [ ] Can see accurate token/cost/context information
- [ ] Can see what tools are auto-allowed vs need permission

## User Decisions

1. **Permission UI Style**: Inline buttons in the permission request message bubble
2. **Interrupt Behavior**: Replace send button with stop button during processing
3. **Priority**: All 3 critical gaps together (Permission + Interrupt + Mode Indicator)

---

## Detailed Implementation Plan

### Task 1: Permission Approval UI (Inline Buttons)

**Frontend Changes:**

`frontend/src/components/chat/MessageBubble.tsx`:
```tsx
// In the permission_request system message rendering:
// Add buttons below the permission text
<div class="permission-actions">
  <button class="permission-btn allow" onClick={() => sendPermissionResponse('y')}>
    Allow
  </button>
  <button class="permission-btn deny" onClick={() => sendPermissionResponse('n')}>
    Deny
  </button>
  <button class="permission-btn allow-all" onClick={() => sendPermissionResponse('a')}>
    Allow All Session
  </button>
</div>
```

`frontend/src/pages/Session.tsx`:
- Add `sendPermissionResponse(response: 'y' | 'n' | 'a')` function
- Send keystroke to PTY via WebSocket (reuse `sendInput` pattern)
- Mark permission message as "responded" to disable buttons

`frontend/src/stores/messages.ts`:
- Add `responded?: boolean` field to system messages
- Add `markPermissionResponded(messageId)` action

**Styling** (in index.css):
```css
.permission-actions {
  display: flex;
  gap: 8px;
  margin-top: 8px;
}
.permission-btn {
  padding: 6px 12px;
  border-radius: 4px;
  font-size: 12px;
  font-weight: 500;
}
.permission-btn.allow { background: #22c55e; color: white; }
.permission-btn.deny { background: #ef4444; color: white; }
.permission-btn.allow-all { background: #3b82f6; color: white; }
```

### Task 2: Stop/Interrupt Button (Replace Send)

**Frontend Changes:**

`frontend/src/components/chat/InputBar.tsx`:
- Add `isProcessing` prop (passed from Session.tsx)
- When `isProcessing && !hasText`:
  - Show stop button (square icon) instead of send button (arrow icon)
  - onClick sends interrupt signal

```tsx
<button
  class={isProcessing ? "stop-btn" : "send-btn"}
  onClick={isProcessing ? handleInterrupt : handleSend}
  disabled={!isProcessing && !hasText}
>
  {isProcessing ? '■' : '↑'}
</button>
```

**Backend Changes:**

`crates/clauset-types/src/ws.rs`:
```rust
// Add new client message variant
pub enum WsClientMessage {
    // ... existing variants
    Interrupt,
}
```

`crates/clauset-server/src/websocket.rs`:
- Handle `WsClientMessage::Interrupt`
- Send SIGINT to PTY process OR send Ctrl+C character (\x03)

`crates/clauset-core/src/session.rs`:
- Add `interrupt()` method that writes `\x03` to PTY

### Task 3: Mode Indicator (Plan Mode Badge)

**Data Flow:**
1. Capture from PreToolUse/PostToolUse when tool is `EnterPlanMode` or `ExitPlanMode`
2. Broadcast mode change via WebSocket
3. Display badge in session header

**Backend Changes:**

`crates/clauset-types/src/ws.rs`:
```rust
pub enum WsServerMessage {
    // ... existing
    ModeChange { mode: SessionMode },
}

pub enum SessionMode {
    Normal,
    Plan,
}
```

`crates/clauset-server/src/routes/hooks.rs`:
- In PreToolUse handler, check if tool_name is "EnterPlanMode"
- In PostToolUse handler, check if tool_name is "ExitPlanMode"
- Broadcast ModeChange event

**Frontend Changes:**

`frontend/src/pages/Session.tsx`:
- Add `mode` signal: `const [mode, setMode] = createSignal<'normal' | 'plan'>('normal')`
- Handle `mode_change` WebSocket message
- Display mode badge in header:

```tsx
{mode() === 'plan' && (
  <span class="mode-badge plan">PLAN MODE</span>
)}
```

**Styling:**
```css
.mode-badge.plan {
  background: #8b5cf6;
  color: white;
  padding: 2px 8px;
  border-radius: 4px;
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;
}
```

---

## Files to Modify (Summary)

### Backend
| File | Changes |
|------|---------|
| `crates/clauset-types/src/ws.rs` | Add `Interrupt` client msg, `ModeChange` server msg, `SessionMode` enum |
| `crates/clauset-server/src/websocket.rs` | Handle Interrupt message, send \x03 to PTY |
| `crates/clauset-server/src/routes/hooks.rs` | Detect EnterPlanMode/ExitPlanMode, broadcast ModeChange |
| `crates/clauset-core/src/session.rs` | Add `interrupt()` method |

### Frontend
| File | Changes |
|------|---------|
| `frontend/src/components/chat/MessageBubble.tsx` | Permission buttons in system message |
| `frontend/src/components/chat/InputBar.tsx` | Stop button replaces send when processing |
| `frontend/src/pages/Session.tsx` | Mode indicator, permission response handler, interrupt handler |
| `frontend/src/stores/messages.ts` | Add `responded` field, permission handling |
| `frontend/src/index.css` | Permission button styles, mode badge styles |

---

## Test-Driven Development Plan

### TDD Approach (Per Project Rules)
1. Write failing tests FIRST
2. Implement the feature to make tests pass
3. Refactor while keeping tests green

---

### Task 1: Permission Approval - Tests First

**Backend Tests** (`crates/clauset-server/tests/permission_response.rs`):
```rust
#[tokio::test]
async fn test_permission_response_y_sends_to_pty() {
    // Given: A session with active PTY
    // When: WsClientMessage::PermissionResponse { response: 'y' } received
    // Then: 'y' character written to PTY stdin
}

#[tokio::test]
async fn test_permission_response_n_sends_to_pty() {
    // Given: A session with active PTY
    // When: WsClientMessage::PermissionResponse { response: 'n' } received
    // Then: 'n' character written to PTY stdin
}

#[tokio::test]
async fn test_permission_response_a_sends_to_pty() {
    // Given: A session with active PTY
    // When: WsClientMessage::PermissionResponse { response: 'a' } received
    // Then: 'a' character written to PTY stdin
}
```

**Frontend Tests** (`frontend/src/components/chat/__tests__/PermissionButtons.test.ts`):
```typescript
describe('Permission Request Buttons', () => {
  it('renders Allow, Deny, Allow All buttons for permission_request message', () => {
    // Given: A system message with systemType='permission_request'
    // Then: 3 buttons visible with correct labels
  });

  it('calls sendPermissionResponse with "y" when Allow clicked', () => {
    // Given: Permission request message
    // When: Allow button clicked
    // Then: sendPermissionResponse('y') called
  });

  it('disables buttons after response sent', () => {
    // Given: Permission request message
    // When: Any button clicked
    // Then: All buttons disabled, message marked as responded
  });
});
```

---

### Task 2: Stop/Interrupt Button - Tests First

**Backend Tests** (`crates/clauset-server/tests/interrupt.rs`):
```rust
#[tokio::test]
async fn test_interrupt_sends_ctrl_c_to_pty() {
    // Given: A session with running process
    // When: WsClientMessage::Interrupt received
    // Then: \x03 (Ctrl+C) written to PTY stdin
}

#[tokio::test]
async fn test_interrupt_on_inactive_session_is_noop() {
    // Given: A stopped session
    // When: WsClientMessage::Interrupt received
    // Then: No error, graceful no-op
}
```

**Frontend Tests** (`frontend/src/components/chat/__tests__/InputBar.test.ts`):
```typescript
describe('InputBar Stop Button', () => {
  it('shows send button (↑) when not processing', () => {
    // Given: isProcessing=false
    // Then: Button shows ↑ icon
  });

  it('shows stop button (■) when processing and no text', () => {
    // Given: isProcessing=true, text=""
    // Then: Button shows ■ icon
  });

  it('shows send button when processing but has text', () => {
    // Given: isProcessing=true, text="hello"
    // Then: Button shows ↑ icon (user can still send)
  });

  it('calls onInterrupt when stop button clicked', () => {
    // Given: isProcessing=true
    // When: Stop button clicked
    // Then: onInterrupt callback invoked
  });
});
```

---

### Task 3: Mode Indicator - Tests First

**Backend Tests** (`crates/clauset-server/tests/mode_indicator.rs`):
```rust
#[tokio::test]
async fn test_enter_plan_mode_broadcasts_mode_change() {
    // Given: A session processing hooks
    // When: PreToolUse hook with tool_name="EnterPlanMode" received
    // Then: WsServerMessage::ModeChange { mode: Plan } broadcast
}

#[tokio::test]
async fn test_exit_plan_mode_broadcasts_mode_change() {
    // Given: A session in plan mode
    // When: PostToolUse hook with tool_name="ExitPlanMode" received
    // Then: WsServerMessage::ModeChange { mode: Normal } broadcast
}
```

**Frontend Tests** (`frontend/src/pages/__tests__/Session.mode.test.ts`):
```typescript
describe('Session Mode Indicator', () => {
  it('shows no badge in normal mode', () => {
    // Given: mode='normal'
    // Then: No mode badge visible
  });

  it('shows PLAN MODE badge when in plan mode', () => {
    // Given: mode='plan'
    // Then: Purple "PLAN MODE" badge visible in header
  });

  it('updates mode when mode_change message received', () => {
    // Given: mode='normal'
    // When: WebSocket receives { type: 'mode_change', mode: 'plan' }
    // Then: Mode signal updates to 'plan'
  });
});
```

---

## Test File Locations Summary

### Backend (New Integration Tests)
| File | Purpose |
|------|---------|
| `crates/clauset-server/tests/permission_response.rs` | Permission approval flow |
| `crates/clauset-server/tests/interrupt.rs` | Interrupt/Ctrl+C handling |
| `crates/clauset-server/tests/mode_indicator.rs` | Plan mode detection & broadcast |

### Frontend (New Unit Tests)
| File | Purpose |
|------|---------|
| `frontend/src/components/chat/__tests__/PermissionButtons.test.ts` | Permission button rendering & clicks |
| `frontend/src/components/chat/__tests__/InputBar.test.ts` | Stop/send button toggle |
| `frontend/src/pages/__tests__/Session.mode.test.ts` | Mode indicator display |

### Test Fixtures (Hook Events)
| File | Purpose |
|------|---------|
| `tests/fixtures/hook_events/enter_plan_mode.json` | Sample EnterPlanMode PreToolUse |
| `tests/fixtures/hook_events/exit_plan_mode.json` | Sample ExitPlanMode PostToolUse |
| `tests/fixtures/hook_events/permission_request.json` | Sample permission prompt |

---

## Implementation Order (TDD)

### Phase 1: Permission Approval
1. Write `permission_response.rs` backend tests → run, see fail
2. Add `WsClientMessage::PermissionResponse` type
3. Implement handler in `websocket.rs` → tests pass
4. Write `PermissionButtons.test.ts` frontend tests → run, see fail
5. Add buttons to `MessageBubble.tsx` → tests pass

### Phase 2: Stop/Interrupt
1. Write `interrupt.rs` backend tests → run, see fail
2. Add `WsClientMessage::Interrupt` type
3. Add `interrupt()` method to `session.rs` → tests pass
4. Write `InputBar.test.ts` frontend tests → run, see fail
5. Add stop button logic to `InputBar.tsx` → tests pass

### Phase 3: Mode Indicator
1. Write `mode_indicator.rs` backend tests → run, see fail
2. Add `WsServerMessage::ModeChange` type
3. Add detection in `hooks.rs` → tests pass
4. Write `Session.mode.test.ts` frontend tests → run, see fail
5. Add mode badge to `Session.tsx` → tests pass

---

## Manual Testing Checklist (After Unit Tests Pass)

- [ ] Permission request appears → click Allow → Claude continues
- [ ] Permission request appears → click Deny → Claude stops/errors gracefully
- [ ] Click Allow All → subsequent permissions auto-approve
- [ ] Claude thinking → Stop button visible → click → Claude stops
- [ ] Enter plan mode via /plan → badge appears
- [ ] Exit plan mode → badge disappears
- [ ] Mode persists across page refresh (if session still in plan mode)

---

## Test Commands

```bash
# Run all backend tests
cargo test --workspace

# Run specific test file
cargo test --package clauset-server --test permission_response
cargo test --package clauset-server --test interrupt
cargo test --package clauset-server --test mode_indicator

# Run all frontend tests
cd frontend && npm test

# Run specific frontend test
cd frontend && npm test -- src/components/chat/__tests__/PermissionButtons.test.ts
```
