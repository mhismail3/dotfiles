# Native TUI Menu Support for Clauset Chat Mode

## Problem Statement

When users type `/model` (or other built-in commands) in chat mode:
1. Command appears as a user bubble ✅
2. **NO response/interactive UI appears** - menu only renders in terminal ❌
3. User must switch to terminal tab to interact with selection menus

This breaks chat mode feature parity with Claude Code CLI.

## Root Cause Analysis

**Two separate interactive systems exist in Claude Code:**

| System | How it works | Clauset Support |
|--------|--------------|-----------------|
| `AskUserQuestion` tool | Hook-based (PreToolUse) | ✅ InteractiveCarousel |
| Built-in TUI menus (`/model`, `/config`) | Direct ANSI terminal render | ❌ **Not captured** |

Built-in menus bypass the hook system entirely - they render directly to terminal stdout as ANSI escape sequences. Clauset never "sees" them as structured data.

## Solution Architecture

**Parse terminal output to detect menu patterns, then render native UI:**

```
Terminal PTY Output → ProcessEvent::TerminalOutput → event_processor.rs
  ↓
TuiMenuParser (NEW) - detects patterns like "Select model", "Enter to confirm"
  ↓
ProcessEvent::TuiMenu { MenuPresented { menu } }
  ↓
WsServerMessage::TuiMenu → Frontend
  ↓
TuiMenuOverlay component (native selection UI)
  ↓
User clicks option → WsClientMessage::TuiMenuSelect
  ↓
Backend sends arrow key sequences + Enter to PTY
```

---

## Implementation Plan

### Phase 1: Types Module
**New file**: `crates/clauset-types/src/tui_menu.rs`

```rust
pub struct TuiMenuOption {
    pub index: usize,
    pub label: String,
    pub description: Option<String>,
    pub is_selected: bool,
}

pub enum TuiMenuType { ModelSelect, Config, Permissions, Mode, Generic }

pub struct TuiMenu {
    pub id: String,
    pub title: String,
    pub description: Option<String>,
    pub options: Vec<TuiMenuOption>,
    pub menu_type: TuiMenuType,
    pub highlighted_index: usize,
}

pub enum TuiMenuEvent {
    MenuPresented { session_id, menu },
    MenuDismissed { session_id, menu_id },
}
```

**Modify**:
- `crates/clauset-types/src/lib.rs` - export tui_menu module
- `crates/clauset-types/src/ws.rs` - add `TuiMenu { event }` to WsServerMessage, add `TuiMenuSelect`/`TuiMenuCancel` to WsClientMessage
- `crates/clauset-core/src/process.rs` - add `TuiMenu(TuiMenuEvent)` to ProcessEvent

### Phase 2: Menu Parser (Generic Detection)
**New file**: `crates/clauset-core/src/tui_menu_parser.rs`

**Goal**: Detect ANY TUI selection menu, not just specific commands.

State machine with three states:
1. **Idle** - waiting for menu patterns
2. **Accumulating** - collecting lines until complete menu detected
3. **MenuActive** - menu detected and broadcast, waiting for dismissal

**Generic detection patterns** (works for all Claude Code menus):
- **Numbered options**: Lines matching `\d+\.\s+\w+` (e.g., "1. Default", "2. Sonnet")
- **Selection indicators**: `▸` (highlighted), `✓` or `✔` (selected)
- **Footer instructions**: `"Enter to confirm"`, `"Esc to exit"`, `"↑/↓ to navigate"`
- **Consistent structure**: Title line, optional description, numbered options, footer

**Heuristic approach**:
1. Detect 2+ consecutive numbered option lines
2. Confirm with footer pattern ("Enter to confirm")
3. Extract title from line(s) before first option
4. Parse each option for label, description, selected state

Features:
- Timeout-based accumulation (menus may arrive in chunks)
- Strip ANSI codes for parsing, keep raw for reference
- Track highlighted index from `▸` marker
- Auto-detect menu type from title keywords (model/config/etc.) or mark as Generic

### Phase 3: Backend Integration

**Modify** `crates/clauset-server/src/event_processor.rs`:
```rust
ProcessEvent::TerminalOutput { session_id, ref data } => {
    // Existing buffer logic...

    // NEW: Check for TUI menu
    if let Some(menu) = state.session_manager
        .process_terminal_for_menu(session_id, data).await
    {
        state.session_manager.event_sender().send(
            ProcessEvent::TuiMenu(TuiMenuEvent::MenuPresented { session_id, menu })
        );
    }
}
```

**Modify** `crates/clauset-server/src/websocket.rs`:
- Forward `ProcessEvent::TuiMenu` as `WsServerMessage::TuiMenu`
- Handle `WsClientMessage::TuiMenuSelect` → send arrow keys + Enter to PTY
- Handle `WsClientMessage::TuiMenuCancel` → send ESC to PTY

### Phase 4: Frontend

**New file**: `frontend/src/stores/tui_menu.ts`
- State: `idle | { type: 'active', menu: TuiMenu }`
- Functions: `handleTuiMenuEvent()`, `getTuiMenuState()`, `clearTuiMenuState()`

**New file**: `frontend/src/components/interactive/TuiMenuOverlay.tsx`
- Modal overlay with menu title, options list
- Keyboard navigation (↑/↓/Enter/Escape)
- Click to select option
- Styling matching existing retro theme

**Modify** `frontend/src/pages/Session.tsx`:
- Handle `tui_menu` WebSocket messages
- Render `<TuiMenuOverlay>` when menu is active
- Send `tui_menu_select` / `tui_menu_cancel` messages

### Phase 5: Testing

**Backend tests** (`crates/clauset-core/src/tui_menu_parser/tests.rs`):
- Menu detection from raw ANSI output
- Option parsing (label, description, selected state)
- Highlighted index detection
- Chunked output handling
- Timeout behavior

**Frontend tests** (`frontend/src/stores/__tests__/tui_menu.test.ts`):
- State transitions (idle → active → idle)
- Event handling
- Store cleanup

**Fixtures**: `tests/fixtures/tui_menus/*.txt` - raw terminal output samples

---

## Critical Files

| File | Action | Purpose |
|------|--------|---------|
| `crates/clauset-types/src/tui_menu.rs` | NEW | Type definitions |
| `crates/clauset-core/src/tui_menu_parser.rs` | NEW | Menu detection state machine |
| `crates/clauset-types/src/ws.rs` | MODIFY | WS message types |
| `crates/clauset-core/src/process.rs` | MODIFY | ProcessEvent variant |
| `crates/clauset-server/src/event_processor.rs` | MODIFY | Integration point |
| `crates/clauset-server/src/websocket.rs` | MODIFY | WS handlers |
| `frontend/src/stores/tui_menu.ts` | NEW | Frontend state |
| `frontend/src/components/interactive/TuiMenuOverlay.tsx` | NEW | UI component |
| `frontend/src/pages/Session.tsx` | MODIFY | Integration |

---

## Design Decisions (Confirmed)

1. **New TuiMenuOverlay component** - separate from InteractiveCarousel for cleaner separation
2. **Generic parser for ALL TUI menus** - detect any selection menu pattern, not just specific commands
3. **Defer custom text input** - focus on selection-based menus first, add text input support later

---

## Implementation Status: ✅ COMPLETE

All phases implemented. See CONTINUITY.md for full details.

---

## Bug Fix: TUI Menu Parser Not Detecting Menus

### Problem

The TUI menu overlay appears but shows incorrect data:
1. Unicode escape sequences displayed as literal text (`\u25B8`, `\u2191\u2193`, `\u00B7`)
2. Raw ANSI codes leaking through (`☒[?2026H`)
3. Only 2 model options showing instead of all models
4. Footer shows literal `\u2191\u2193 Navigate` instead of `↑↓ Navigate`

### Root Cause (Investigation Complete)

**Critical insight**: Claude Code outputs literal escape sequence TEXT, not Unicode characters.

The screenshot shows the footer as:
```
\u2191\u2193 Navigate \u00B7 Enter Select \u00B7 Esc Cancel
```

This is the LITERAL string `\u2191\u2193` (backslash-u-2-1-9-1...), NOT the Unicode character `↑`.

**But the parser's footer patterns expect actual Unicode:**
```rust
static FOOTER_PATTERNS: Lazy<Vec<&'static str>> = Lazy::new(|| {
    vec![
        "Enter to confirm",
        "Esc to exit",
        "↑/↓ to navigate",  // Actual Unicode - DOESN'T MATCH
        // ...
    ]
});
```

Since footer detection fails, menu detection fails → parser doesn't emit a complete menu.

### Fix Plan

#### 1. Update Footer Patterns (`tui_menu_parser.rs`)

Add literal escape sequence patterns to `FOOTER_PATTERNS`:
```rust
static FOOTER_PATTERNS: Lazy<Vec<&'static str>> = Lazy::new(|| {
    vec![
        // Existing patterns
        "Enter to confirm",
        "Esc to exit",
        "↑/↓ to navigate",

        // NEW: Literal escape sequence patterns (what Claude Code actually outputs)
        r"\u2191\u2193",      // Literal "\u2191\u2193" for ↑↓
        "Navigate",           // Simplified - just match "Navigate"
        "Enter Select",       // Match "Enter Select"
        "Esc Cancel",         // Match "Esc Cancel"
    ]
});
```

#### 2. Add Escape Sequence Normalization

Create helper to convert literal `\u` sequences to actual Unicode before pattern matching:
```rust
fn normalize_unicode_escapes(text: &str) -> String {
    // Convert "\u2191" literal to actual "↑" character
    let re = Regex::new(r"\\u([0-9a-fA-F]{4})").unwrap();
    re.replace_all(text, |caps: &Captures| {
        let code = u32::from_str_radix(&caps[1], 16).unwrap_or(0);
        char::from_u32(code).unwrap_or('?').to_string()
    }).into_owned()
}
```

Apply this normalization in `strip_ansi_codes()` or as a separate step.

#### 3. Improve ANSI Stripping

Current regex may miss some sequences. Expand to handle:
```rust
// Current
r"\x1b\[[0-9;]*[a-zA-Z]|\x1b\]8;;[^\x07]*\x07|\x1b\]8;;\x07"

// Improved
r"\x1b\[[0-9;?]*[a-zA-Z]|"  // CSI sequences (added ? for DEC private)
r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|"  // OSC sequences
r"\x1b[()][AB012]|"  // Charset switching
r"\x1b[=>]|"  // Keypad mode
r"\x1b[78]"  // Save/restore cursor
```

#### 4. Frontend Unicode Escapes

The `TuiMenuOverlay.tsx` correctly uses JavaScript Unicode escapes (`'\u25B8'`) which render fine. The issue is purely in the parser not detecting menus correctly. Once the parser is fixed, the frontend will receive proper menu data.

### Files to Modify

1. `crates/clauset-core/src/tui_menu_parser.rs`
   - Add literal escape sequence footer patterns
   - Add `normalize_unicode_escapes()` helper
   - Improve ANSI stripping regex

2. Tests for the new normalization function

### Verification

After fix:
1. Type `/model` in chat mode
2. TUI menu overlay should appear with ALL model options
3. Footer should show `↑↓ Navigate · Enter Select · Esc Cancel` (proper Unicode)
4. No ANSI code leakage
