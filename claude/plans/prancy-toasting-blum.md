# Claude Code Hooks Integration for Clauset

## Overview

Replace fragile regex-based terminal output parsing with Claude Code hooks for accurate, real-time session activity tracking. Hooks provide structured JSON events for every tool use, prompt submission, and state transition.

## Architecture

```
Claude Code CLI
     |
     +-- [Hook Events] --> clauset-hook.sh --> HTTP POST /api/hooks --> Clauset Server
     |                                                                      |
     +-- [PTY Output] --> buffer.rs (regex fallback for cost/tokens) -------+
                                                                            |
                                                                    SessionActivity
                                                                            |
                                                                    WebSocket broadcast
                                                                            |
                                                                    SessionCard.tsx
```

## Implementation Phases

### Phase 1: Hook Script & Configuration

**1.1 Create hook script** - `scripts/clauset-hook.sh`
```bash
#!/bin/bash
# Lightweight hook - only active when CLAUSET_SESSION_ID is set
INPUT=$(cat)
[[ -z "${CLAUSET_SESSION_ID:-}" ]] && exit 0
CLAUSET_URL="${CLAUSET_URL:-http://localhost:8080}"
PAYLOAD=$(echo "$INPUT" | jq -c --arg sid "$CLAUSET_SESSION_ID" '. + {clauset_session_id: $sid}')
curl -s -X POST "$CLAUSET_URL/api/hooks" -H "Content-Type: application/json" -d "$PAYLOAD" --max-time 0.5 &>/dev/null &
exit 0
```

**1.2 Create settings template** - `scripts/clauset-hooks-settings.json`
```json
{
  "hooks": {
    "SessionStart": [{"hooks": [{"type": "command", "command": "~/.claude/hooks/clauset-hook.sh", "timeout": 2}]}],
    "SessionEnd": [{"hooks": [{"type": "command", "command": "~/.claude/hooks/clauset-hook.sh", "timeout": 2}]}],
    "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "~/.claude/hooks/clauset-hook.sh", "timeout": 2}]}],
    "PreToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "~/.claude/hooks/clauset-hook.sh", "timeout": 2}]}],
    "PostToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "~/.claude/hooks/clauset-hook.sh", "timeout": 2}]}],
    "Stop": [{"hooks": [{"type": "command", "command": "~/.claude/hooks/clauset-hook.sh", "timeout": 2}]}],
    "SubagentStop": [{"hooks": [{"type": "command", "command": "~/.claude/hooks/clauset-hook.sh", "timeout": 2}]}],
    "Notification": [{"hooks": [{"type": "command", "command": "~/.claude/hooks/clauset-hook.sh", "timeout": 2}]}],
    "PreCompact": [{"hooks": [{"type": "command", "command": "~/.claude/hooks/clauset-hook.sh", "timeout": 2}]}]
  }
}
```

**1.3 Create setup script** - `scripts/setup-hooks.sh`
- Copies clauset-hook.sh to ~/.claude/hooks/
- Merges hook settings into ~/.claude/settings.json (preserving existing settings)
- Makes hook script executable

---

### Phase 2: Backend API Endpoint

**2.1 Create hook types** - `crates/clauset-types/src/hooks.rs` (NEW)
```rust
pub struct HookEventPayload {
    pub clauset_session_id: Uuid,
    pub session_id: String,  // Claude's session ID
    pub hook_event_name: String,
    pub tool_name: Option<String>,
    pub tool_input: Option<Value>,
    pub tool_response: Option<Value>,
    pub prompt: Option<String>,
    pub source: Option<String>,  // SessionStart
    pub reason: Option<String>,  // SessionEnd
    pub stop_hook_active: Option<bool>,
}

pub enum HookEventType {
    SessionStart, SessionEnd, UserPromptSubmit,
    PreToolUse, PostToolUse, Stop, SubagentStop,
    Notification, PreCompact
}
```

**2.2 Create hooks route** - `crates/clauset-server/src/routes/hooks.rs` (NEW)
- `POST /api/hooks` - Receive and process hook events
- Parse `HookEventPayload` from JSON
- Dispatch to appropriate handler based on `hook_event_name`

**2.3 Register route** - `crates/clauset-server/src/main.rs`
```rust
.route("/hooks", post(routes::hooks::receive))
```

---

### Phase 3: Activity Update from Hooks

**3.1 Add hook-based activity tracking** - `crates/clauset-core/src/buffer.rs`

Add new struct and method:
```rust
pub struct HookActivityUpdate {
    pub event_type: HookEventType,
    pub tool_name: Option<String>,
    pub tool_input: Option<Value>,
}

impl SessionBuffers {
    pub async fn update_from_hook(&self, session_id: Uuid, update: HookActivityUpdate) -> Option<SessionActivity>
}
```

Event handling logic:
| Event | Action |
|-------|--------|
| UserPromptSubmit | `is_busy=true`, `current_step="Thinking"` |
| PreToolUse | `current_step=tool_name`, add to `recent_actions` |
| PostToolUse | Update action with success/failure |
| Stop | `is_busy=false`, `current_step="Ready"` |
| SessionEnd | Mark session stopped |

**3.2 Add hook update methods** - `crates/clauset-core/src/session.rs`
```rust
impl SessionManager {
    pub async fn update_activity_from_hook(&self, session_id: Uuid, update: HookActivityUpdate) -> Result<()>
    pub async fn mark_session_ready(&self, session_id: Uuid) -> Result<()>
}
```

---

### Phase 4: Environment Variable Injection

**4.1 Modify process spawning** - `crates/clauset-core/src/process.rs`

In `spawn_terminal()`, before spawning Claude:
```rust
cmd.env("CLAUSET_SESSION_ID", opts.session_id.to_string());
cmd.env("CLAUSET_URL", format!("http://localhost:{}", config.port));
```

This allows the hook script to know:
- Which Clauset session this is (for mapping hook events)
- Where to send hook events

---

### Phase 5: Frontend Enhancements (Optional)

**5.1 Richer tool display** - `frontend/src/components/SessionCard.tsx`
- Show tool inputs (file paths, commands) from hook data
- Add visual indicators for tool success/failure
- Show subagent progress

---

## File Changes Summary

| File | Action | Description |
|------|--------|-------------|
| `scripts/clauset-hook.sh` | CREATE | Lightweight bash hook script |
| `scripts/clauset-hooks-settings.json` | CREATE | Hook configuration template |
| `scripts/setup-hooks.sh` | CREATE | One-time setup script |
| `crates/clauset-types/src/hooks.rs` | CREATE | Hook event type definitions |
| `crates/clauset-types/src/lib.rs` | MODIFY | Export hooks module |
| `crates/clauset-server/src/routes/hooks.rs` | CREATE | HTTP endpoint for hooks |
| `crates/clauset-server/src/routes/mod.rs` | MODIFY | Add hooks module |
| `crates/clauset-server/src/main.rs` | MODIFY | Register /api/hooks route |
| `crates/clauset-core/src/buffer.rs` | MODIFY | Add `update_from_hook()` method |
| `crates/clauset-core/src/session.rs` | MODIFY | Add hook update methods |
| `crates/clauset-core/src/process.rs` | MODIFY | Inject CLAUSET_* env vars |

---

## Hook Event Data Flow

### UserPromptSubmit (user sends input)
```
User types in terminal → Claude receives → UserPromptSubmit hook fires
→ POST /api/hooks {hook_event_name: "UserPromptSubmit", prompt: "..."}
→ SessionActivity.is_busy = true, current_step = "Thinking"
→ WebSocket broadcast → SessionCard shows "Thinking..."
```

### PreToolUse (tool starting)
```
Claude decides to use tool → PreToolUse hook fires
→ POST /api/hooks {hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "git status"}}
→ Add to recent_actions, current_step = "Bash"
→ WebSocket broadcast → SessionCard shows "● Bash: git status"
```

### Stop (Claude finished)
```
Claude finishes responding → Stop hook fires
→ POST /api/hooks {hook_event_name: "Stop", stop_hook_active: false}
→ is_busy = false, current_step = "Ready"
→ WebSocket broadcast → SessionCard shows "✓ Ready"
```

---

## Fallback Strategy

Keep regex parsing in `buffer.rs` for:
1. **Cost/Token/Model parsing** - Hooks don't provide this; parse from status line
2. **Non-Clauset sessions** - Hook script exits immediately if `CLAUSET_SESSION_ID` not set
3. **Hook delivery failures** - Network issues won't break activity tracking

Priority: Hook events override regex-parsed `current_step` and `is_busy` when available.

---

## User Setup Requirements

One-time setup (run `scripts/setup-hooks.sh`):
1. Creates `~/.claude/hooks/clauset-hook.sh`
2. Merges hook config into `~/.claude/settings.json`

Prerequisites:
- `jq` installed (for JSON processing in hook script)
- `curl` installed (for HTTP POST)

---

## Testing Plan

1. **Hook script isolation test**: Run `echo '{}' | CLAUSET_SESSION_ID=test ./clauset-hook.sh` - should exit 0, no output
2. **Endpoint test**: `curl -X POST localhost:8080/api/hooks -d '{"clauset_session_id":"...", "hook_event_name":"Stop"}'`
3. **Integration test**: Start session via Clauset, verify hook events update SessionCard in real-time
4. **Fallback test**: Disable hooks, verify regex parsing still works
