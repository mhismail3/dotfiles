# Slash Command Picker Implementation Plan

## Goal
Implement a Claude Code slash command picker for Clauset's chat interface that:
- Triggers on "/" keystroke or via a button
- Discovers all commands (built-in, user, skills, plugins)
- Executes through the active Claude PTY session
- Shows output streaming in chat view

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                         Frontend (SolidJS)                        │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │  InputBar.tsx ─────→ CommandPicker.tsx                      │  │
│  │     "/" trigger        Dropdown with search/filter          │  │
│  │                                                             │  │
│  │  Session.tsx ─────→ wsManager.send({ type: 'input',        │  │
│  │     onSend()           content: '/command args' })          │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                              ↕                                     │
│                    GET /api/commands                               │
└────────────────────────────────────────────────────────────────────┘
                               ↕
┌────────────────────────────────────────────────────────────────────┐
│                         Backend (Rust/Axum)                        │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │  CommandDiscovery                                           │  │
│  │    - Built-in commands (hardcoded ~40)                      │  │
│  │    - ~/.claude/commands/*.md                                │  │
│  │    - ~/.claude/skills/*/SKILL.md                            │  │
│  │    - ~/.claude/plugins/cache/*/commands/*.md                │  │
│  └─────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Backend - Command Discovery API

### 1.1 Type Definitions
**File:** `crates/clauset-types/src/command.rs` (new)

```rust
pub enum CommandCategory { BuiltIn, User, Skill, Plugin }

pub struct Command {
    name: String,            // "optimize"
    display_name: String,    // "/optimize"
    description: String,
    category: CommandCategory,
    argument_hint: Option<String>,  // "[file-path]"
    source: String,          // file path or "built-in"
    plugin_name: Option<String>,
}

pub struct CommandFrontmatter {
    name: Option<String>,
    description: Option<String>,
    argument_hint: Option<String>,
    allowed_tools: Option<String>,
}
```

### 1.2 Discovery Logic
**File:** `crates/clauset-core/src/command_discovery.rs` (new)

- `CommandDiscovery` struct with 30-second cache
- `discover_all()` → scans all sources, returns `CommandsResponse`
- `built_in_commands()` → hardcoded list of ~40 commands
- `discover_user_commands()` → scan `~/.claude/commands/*.md`
- `discover_skills()` → scan `~/.claude/skills/*/SKILL.md`
- `discover_plugin_commands()` → scan `~/.claude/plugins/cache/*/commands/*.md`
- `parse_markdown_file()` → extract YAML frontmatter

**Dependencies:** Add `serde_yaml = "0.9"` to Cargo.toml

### 1.3 API Route
**File:** `crates/clauset-server/src/routes/commands.rs` (new)

```rust
// GET /api/commands?category=user
pub async fn list_commands(...) -> Result<Json<CommandsResponse>, ...>
```

**Modify:**
- `crates/clauset-server/src/state.rs` - Add `CommandDiscovery` to `AppState`
- `crates/clauset-server/src/main.rs` - Register route `.route("/commands", get(...))`
- `crates/clauset-server/src/routes/mod.rs` - Export commands module

---

## Phase 2: Frontend - Commands Store

### 2.1 Store
**File:** `frontend/src/stores/commands.ts` (new)

```typescript
interface Command {
  name: string;
  displayName: string;
  description: string;
  category: 'built_in' | 'user' | 'skill' | 'plugin';
  argumentHint?: string;
}

// Signals
const [commands, setCommands] = createSignal<Command[]>([]);
const [filteredCommands, setFilteredCommands] = createSignal<Command[]>([]);
const [selectedIndex, setSelectedIndex] = createSignal(0);
const [loading, setLoading] = createSignal(false);

// Functions
fetchCommands()       // GET /api/commands, cache in-memory
filterCommands(query) // Filter by name/description match
selectNext()          // Arrow down
selectPrevious()      // Arrow up
getSelectedCommand()  // Current selection
getGroupedCommands()  // Group by category for display
```

### 2.2 API Types
**File:** `frontend/src/lib/api.ts` (modify)

```typescript
// Add to api object:
commands: {
  list: () => fetchJSON<CommandsResponse>('/commands'),
}
```

---

## Phase 3: Frontend - CommandPicker Component

### 3.1 Component Structure
**File:** `frontend/src/components/commands/CommandPicker.tsx` (new)

```tsx
interface CommandPickerProps {
  isOpen: boolean;
  query: string;
  onSelect: (command: Command) => void;
  onClose: () => void;
  anchorBottom: number;
}
```

**Features:**
- Positioned above input bar (fixed, anchored to bottom)
- Max-height 300px with overflow scroll
- Groups commands by category with colored headers
- Keyboard navigation (arrows highlight, Enter selects)
- Search/filter as user types after "/"
- Loading spinner while fetching
- "No matches" empty state

**Styling:** Retro theme (offset shadows, 1.5px borders, --color-accent for command names)

---

## Phase 4: Frontend - InputBar Integration

### 4.1 Trigger Mechanism
**File:** `frontend/src/components/chat/InputBar.tsx` (modify)

```tsx
// New state
const [showCommandPicker, setShowCommandPicker] = createSignal(false);
const [commandQuery, setCommandQuery] = createSignal('');

// Detect "/" trigger
createEffect(() => {
  const text = message();
  if (text.startsWith('/') && !text.includes(' ')) {
    setShowCommandPicker(true);
    setCommandQuery(text.slice(1));
  } else {
    setShowCommandPicker(false);
  }
});

// Keyboard handling when picker is open
function handleKeyDown(e: KeyboardEvent) {
  if (showCommandPicker()) {
    if (e.key === 'ArrowDown') { e.preventDefault(); selectNext(); }
    if (e.key === 'ArrowUp') { e.preventDefault(); selectPrevious(); }
    if (e.key === 'Enter') {
      e.preventDefault();
      handleCommandSelect(getSelectedCommand());
    }
    if (e.key === 'Escape') {
      e.preventDefault();
      setShowCommandPicker(false);
      setMessage('');
    }
  }
  // ... existing Enter handling
}

// Command selection
function handleCommandSelect(cmd: Command) {
  setShowCommandPicker(false);
  if (cmd.argumentHint) {
    setMessage(`/${cmd.name} `); // Let user add args
  } else {
    props.onSend(`/${cmd.name}`); // Send immediately
  }
}
```

### 4.2 Button Trigger (Optional)
**File:** `frontend/src/pages/Sessions.tsx` (modify)

Add "/" button to existing FAB menu (alongside "Prompt Library" and "New Session"):
- Opens command picker in a modal variant
- For use when not in an active session

---

## Phase 5: Execution & Output

**No changes needed!** Command execution already works:

1. `InputBar.onSend("/command")` → `Session.handleSendMessage()`
2. `wsManager.send({ type: 'input', content: '/command' })`
3. PTY receives command, Claude executes it
4. Output streams back via WebSocket → chat bubbles

---

## Files to Create

| File | Purpose |
|------|---------|
| `crates/clauset-types/src/command.rs` | Command types, frontmatter structs |
| `crates/clauset-core/src/command_discovery.rs` | Discovery logic with caching |
| `crates/clauset-server/src/routes/commands.rs` | GET /api/commands endpoint |
| `frontend/src/stores/commands.ts` | Commands state management |
| `frontend/src/components/commands/CommandPicker.tsx` | Picker UI component |

## Files to Modify

| File | Changes |
|------|---------|
| `crates/clauset-types/src/lib.rs` | Export command module |
| `crates/clauset-core/src/lib.rs` | Export CommandDiscovery |
| `crates/clauset-core/Cargo.toml` | Add serde_yaml dependency |
| `crates/clauset-server/src/state.rs` | Add CommandDiscovery to AppState |
| `crates/clauset-server/src/main.rs` | Register /api/commands route |
| `crates/clauset-server/src/routes/mod.rs` | Export commands module |
| `frontend/src/lib/api.ts` | Add commands API types |
| `frontend/src/components/chat/InputBar.tsx` | "/" trigger, keyboard nav, picker integration |

---

## Implementation Order

1. **Backend types** - command.rs
2. **Backend discovery** - command_discovery.rs with tests
3. **Backend route** - commands.rs + AppState + main.rs
4. **Frontend store** - commands.ts
5. **Frontend API** - api.ts additions
6. **Frontend picker** - CommandPicker.tsx
7. **Frontend integration** - InputBar.tsx modifications
8. **Testing** - Mobile keyboard, touch, streaming output

---

## Success Criteria

- [ ] Typing "/" in chat shows command picker
- [ ] Arrow keys navigate, Enter selects, Escape cancels
- [ ] Commands grouped by category (Built-in, User, Skills, Plugins)
- [ ] Search filters as you type (e.g., "/com" shows "/commit", "/compact")
- [ ] Commands with arguments insert + cursor for args
- [ ] Commands without arguments execute immediately
- [ ] Output streams in chat bubbles (already works)
- [ ] Works on mobile (touch, keyboard awareness)
