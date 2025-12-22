# Plan: Telegram Bot Output Quality Overhaul

## Problem Summary

The Telegram bot output is extremely noisy and poorly formatted. Based on screenshots and code analysis, the following issues need to be fixed:

### Critical Issues Identified:

| Issue | Example from Screenshots | Root Cause |
|-------|--------------------------|------------|
| 1. Repeated status lines | "Next: Fix identified bug" appears 50+ times | Missing skip pattern for todo status |
| 2. Running indicators shown | "Running..." everywhere | Pattern doesn't match `⎿  Running…` format |
| 3. Garbage characters | "(B" at end of lines like "Read 121 lines(B" | ANSI `\x1B(B` not being cleaned |
| 4. Tool headers shown | "Search(pattern: ..." | Missing pattern for Search/Update tools |
| 5. File names as links | "logging.py" becomes clickable | Telegram auto-linking |
| 6. Link previews | Claude.com shows embedded card | `disable_web_page_preview` not set |
| 7. "copy" text leaking | Literal "copy" appears | Code block copy button text |
| 8. Code not formatted | JS/JSX code as plain text | Code detection too narrow |
| 9. Fragmented messages | Many tiny messages | Batching too aggressive |
| 10. No content distinction | Tool output mixed with explanations | Everything sent identically |

---

## Implementation Plan

### File to Modify
`/Users/moose/Downloads/projects/claude-moose/claude_telegram_agent.py`

---

### Phase 1: Fix ANSI/Terminal Garbage (Issues 3, 7)

**Location:** Lines 95-109

**Changes:**

1. **Expand ANSI_ESCAPE pattern** to catch single-character escapes:
   ```python
   # Add pattern for \x1B(B, \x1B(0, etc (character set selection)
   ANSI_CHARSET = re.compile(r"\x1B[\(\)][A-Za-z0-9]")
   ```

2. **Add pattern for "(B" remnants** that survive initial cleaning:
   ```python
   ANSI_REMNANTS_EXTRA = re.compile(r"\(B(?=\s|$|\n)")
   ```

3. **Add "copy" button text filter**:
   ```python
   # In skip patterns or as direct removal
   re.compile(r"^\s*copy\s*$", re.I)
   ```

---

### Phase 2: Comprehensive Skip Patterns (Issues 1, 2, 4)

**Location:** Lines 112-182 (SKIP_LINE_PATTERNS)

**Add these patterns:**

```python
# Claude Code tree/status indicators (⎿ character)
re.compile(r"^\s*⎿"),  # Any line starting with tree char
re.compile(r"^\s*\|?\s*⎿"),  # With optional pipe

# TODO status lines
re.compile(r"^\s*Next:\s", re.I),
re.compile(r"^\s*Pending:\s", re.I),
re.compile(r"^\s*Completed:\s", re.I),
re.compile(r"^\s*In Progress:\s", re.I),

# More tool invocations (Search, Update, NotebookEdit, etc)
re.compile(r"^\s*(Search|Update|NotebookEdit|TodoWrite|AskUserQuestion)\s*\(", re.I),
re.compile(r"^\s*(Search|Update|NotebookEdit|TodoWrite|AskUserQuestion)\s*$", re.I),

# Tool output patterns
re.compile(r"^\s*Found\s+\d+\s+files?\s*$", re.I),
re.compile(r"^\s*Read\s+\d+\s+lines?\s*$", re.I),
re.compile(r"^\s*\(No content\)\s*$", re.I),

# Running with various formats
re.compile(r"running\.*$", re.I),
re.compile(r"^\s*⎿?\s*Running", re.I),

# Ctrl hints
re.compile(r"ctrl\+[a-z]", re.I),
re.compile(r"press ctrl", re.I),

# Token/timing info
re.compile(r"\d+\s*tokens?\s*\)", re.I),
re.compile(r"\d+(?:\.\d+)?\s*[ms]?\s*·", re.I),  # "50s · 1.5k tokens"

# Error patterns that are just status
re.compile(r"^\s*Error:\s*File does not exist\.?\s*$", re.I),

# Git branch lines shown as status
re.compile(r"^\s*On branch\s+\S+\s*$", re.I),

# Untracked files header
re.compile(r"^\s*Untracked files:\s*$", re.I),
re.compile(r"^\s*Changes not staged", re.I),
re.compile(r'^\s*\(use "git', re.I),
re.compile(r"^\s*nothing added to commit", re.I),
```

---

### Phase 3: Disable Link Previews (Issue 6)

**Location:** Lines 534-556 (`_send_message` method)

**Change:**
```python
await app.bot.send_message(
    chat_id=self.chat_id,
    text=text,
    parse_mode=parse_mode,
    disable_web_page_preview=True  # ADD THIS
)
```

Also add to fallback plain text send.

---

### Phase 4: Prevent Auto-linking (Issue 5)

**Location:** Lines 293-346 (`format_for_telegram` function)

**Strategy:** Wrap file paths and potential auto-link triggers in `<code>` tags

**Changes:**
1. Detect file extensions (`.py`, `.js`, `.jsx`, `.ts`, etc) and wrap in `<code>`
2. Detect Unix paths starting with `/` or `~/` and wrap in `<code>`
3. Detect `filename.ext` patterns and wrap in `<code>`

```python
# After HTML escaping, before code block detection:
# Wrap standalone filenames to prevent auto-linking
text = re.sub(
    r'(?<![/\w])(\w+\.(py|js|jsx|ts|tsx|json|md|txt|yml|yaml|sh|css|html))\b',
    r'<code>\1</code>',
    text
)
```

---

### Phase 5: Improve Code Block Detection (Issue 8)

**Location:** Lines 307-339 (`format_for_telegram` function)

**Expand code detection to include:**

```python
looks_like_code = (
    line.startswith("  ") or
    line.startswith("\t") or
    # Existing patterns
    re.match(r"^(\/[\w\/\-\.]+|~\/|\$\s|git\s|cd\s|ls\s)", line) or
    re.match(r"^\s*(def |class |import |from |function |const |let |var |export |return )", line) or
    # NEW: More code patterns
    re.match(r"^\s*(if |else |elif |for |while |try:|except|catch|switch|case )", line) or
    re.match(r"^\s*[}\]);]", line) or  # Closing brackets
    re.match(r"^\s*[\w]+\s*[=:]\s*[\[\{]", line) or  # Assignments
    re.match(r"^\s*\w+\(", line) and not re.match(r"^\s*(I|You|The|This|It|Let|Here)\s", line) or  # Function calls (but not prose)
    re.search(r"[{}()\[\]];?\s*$", line) or  # Lines ending with brackets
    re.match(r"^\s*//|^\s*#(?!\s)", line) or  # Comments
    re.match(r"^\s*@\w+", line) or  # Decorators
    "=>" in line or  # Arrow functions
    re.search(r"\.\w+\(", line)  # Method calls
)
```

---

### Phase 6: Smarter Message Batching (Issue 9)

**Location:** Lines 452-470 (`_read_output` method)

**Changes:**

1. **Increase minimum send interval** from 8s to 15s
2. **Increase silence threshold** from 3s to 6s
3. **Add content completeness check** - only send when content looks like a complete thought

```python
# Change batching logic
should_check = accumulated and (
    time_since_send > 15.0 or  # Was 8 - much longer for fewer messages
    (time_since_data > 6.0 and len(accumulated) > 300) or  # Was 3s/100
    len(accumulated) > 20000  # Was 10000
)
```

Also add: Don't send if content is mostly status/noise after filtering.

---

### Phase 7: Content Categorization + Condensed Status (Issue 10)

**Location:** New function + modifications to `_send_output` and `_read_output`

**User Preference:** Show condensed status summary + show errors when tools fail

**Strategy:**

1. **Claude's explanations** → Send as normal messages (priority)
2. **Code/diffs** → Send in `<pre>` monospace blocks
3. **Status updates** → Consolidate into brief summary line
4. **Errors** → Send prominently, never suppress

**Implementation:**

```python
class ContentType(Enum):
    EXPLANATION = "explanation"  # Claude's prose - always show
    CODE = "code"               # Code blocks - show in <pre>
    STATUS = "status"           # Tool status - consolidate
    ERROR = "error"             # Errors - always show prominently

# Track current activity for condensed status
class ActivityTracker:
    def __init__(self):
        self.files_read = 0
        self.commands_run = 0
        self.searches_done = 0
        self.current_task = ""
        self.last_status_sent = None

    def parse_status(self, raw_text: str):
        """Parse raw output to track activity."""
        # Count "Read X lines" occurrences
        self.files_read += len(re.findall(r"Read \d+ lines", raw_text))
        # Count "Running" occurrences
        self.commands_run += len(re.findall(r"Running\.*", raw_text, re.I))
        # Count searches
        self.searches_done += len(re.findall(r"Search\(", raw_text))
        # Extract current task from "Next: X"
        task_match = re.search(r"Next:\s*(.+?)(?:\n|$)", raw_text)
        if task_match:
            self.current_task = task_match.group(1).strip()

    def get_condensed_status(self) -> str:
        """Generate condensed status line."""
        parts = []
        if self.current_task:
            parts.append(f"📋 {self.current_task}")
        activity = []
        if self.files_read:
            activity.append(f"{self.files_read} files read")
        if self.commands_run:
            activity.append(f"{self.commands_run} commands")
        if self.searches_done:
            activity.append(f"{self.searches_done} searches")
        if activity:
            parts.append(f"({', '.join(activity)})")
        return " ".join(parts) if parts else ""

    def reset(self):
        """Reset counters after sending status."""
        self.files_read = 0
        self.commands_run = 0
        self.searches_done = 0

def categorize_content(text: str) -> ContentType:
    """Categorize content for appropriate handling."""
    # Errors always get priority
    if re.search(r"(error|fatal|exception|failed|Error:):", text, re.I):
        return ContentType.ERROR
    # Claude's actual prose responses
    if is_claude_response(text):
        return ContentType.EXPLANATION
    # Code-like content
    if re.search(r"(def |class |function |const |import |from )", text):
        return ContentType.CODE
    # Everything else is status
    return ContentType.STATUS
```

**Status Display Logic:**

- Only send condensed status every 30+ seconds (not every message)
- Format: `📋 Current task (X files read, Y commands, Z searches)`
- When Claude sends actual explanation, clear/reset status counters
- Always show errors immediately, even if filtering status

---

### Phase 8: UI Character Cleanup Enhancement

**Location:** Line 109 (UI_CHARS pattern)

**Add missing characters:**
```python
# Add these to UI_CHARS:
"⎿"  # Claude's tree character
"⏺⏹⏵⏴"  # More media controls
```

---

## User Preferences (from clarification)

- **Status messages:** Condensed summary + show errors
- **Code formatting:** Monospace `<pre>` blocks
- **Message frequency:** Fewer, larger messages (15s intervals)

---

## Summary of All Changes

| Phase | File Location | What Changes |
|-------|---------------|--------------|
| 1 | Lines 95-109 | Add ANSI charset pattern, (B remnant filter |
| 2 | Lines 112-182 | Add ~25 new skip patterns for status/tools |
| 3 | Lines 540-543 | Add `disable_web_page_preview=True` |
| 4 | Lines 293-346 | Wrap filenames in `<code>` tags |
| 5 | Lines 307-339 | Expand code detection patterns |
| 6 | Lines 455-462 | Increase batching to 15s intervals |
| 7 | New code (~100 lines) | ActivityTracker class, content categorization, condensed status |
| 8 | Line 109 | Expand UI_CHARS with ⎿ and others |

---

## Testing Verification

After implementation:
1. Send a complex prompt that triggers many tool uses
2. Verify: No "(B" characters appear
3. Verify: No "Next: X" status lines appear
4. Verify: No link previews for URLs
5. Verify: File names don't become clickable links
6. Verify: Code appears in monospace blocks
7. Verify: Messages are consolidated, not fragmented
8. Verify: Only Claude's actual explanations are prominent

---

## Risk Assessment

- **Low risk:** ANSI cleaning, link preview disable, UI chars
- **Medium risk:** Skip patterns (might filter too much)
- **Medium risk:** Code detection (might wrap non-code as code)
- **Testing approach:** Be conservative with patterns, iterate based on real output
