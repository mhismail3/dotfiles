# Agent Ledger System Implementation Plan

## Goal
Create a persistent cross-session memory system at `~/.claude/` that:
1. Stores session records in `LEDGER.jsonl` with frontmatter/details separation
2. Uses `ledger-context/` folder for supplementary data (sessions, indexes)
3. Supports fuzzy project matching for retrieval
4. Enables minimal frontmatter queries at session start (like Skills pattern)
5. Provides tight AGENTS.md instructions for CLAUDE.md integration

## Files to Create

### 1. `/Users/moose/.claude/LEDGER.jsonl`
Empty file to start; records appended per session.

### 2. `/Users/moose/.claude/ledger-context/`
Directory structure:
```
ledger-context/
├── sessions/           # Chat history files for long sessions
├── projects.json       # Project name aliases for fuzzy matching
└── index.md            # Human-curated semantic index
```

### 3. `/Users/moose/.claude/AGENTS.md`
Revised instructions for Claude Code integration.

---

## Schema Design (Frontmatter-First)

Each JSONL record has two tiers:

```json
{
  "_meta": {
    "id": "uuid-v4",
    "ts": "ISO-8601 timestamp",
    "v": 1
  },
  "front": {
    "project": "normalized-name",
    "path": "/absolute/path",
    "title": "Brief task description",
    "type": "feature|bugfix|refactor|docs|config|research",
    "status": "completed|partial|failed|abandoned",
    "tags": ["searchable", "keywords"]
  },
  "body": {
    "agent": { "model": "string", "provider": "string", "tool": "string" },
    "git": { "branch": "string", "commit": "string" },
    "input": "Original user request",
    "context": { "prior_state": "string", "dependencies": ["strings"] },
    "actions": ["Step 1", "Step 2"],
    "files": [{ "path": "string", "op": "C|M|D", "lines": "+/-N", "why": "string" }],
    "decisions": [{ "choice": "string", "alts": ["strings"], "reason": "string" }],
    "outcome": { "verification": "string", "issues": "string", "followup": "string|null" },
    "lessons": ["Primary retrieval target - patterns for future"]
  },
  "history": {
    "embedded": true,
    "content": "Full transcript if short",
    "ref": "ledger-context/sessions/filename.md if long"
  }
}
```

**Key Design Choice:** The `front` object is the "frontmatter" - always retrieved first. The `body` and `history` are pulled on-demand.

---

## Retrieval Patterns

### Session Start (Lightweight)
```bash
# Get frontmatter for matching projects (fuzzy)
jq -c '{_meta, front}' ~/.claude/LEDGER.jsonl | grep -i "$PROJECT"
```

### On-Demand Details
```bash
# Get full record by ID
jq -c 'select(._meta.id == "TARGET_ID")' ~/.claude/LEDGER.jsonl

# Get lessons for project
jq -r 'select(.front.project | test("PROJECT"; "i")) | .body.lessons[]' ~/.claude/LEDGER.jsonl
```

### Fuzzy Project Matching
- Normalize: lowercase, strip common suffixes (-main, -dev), collapse whitespace
- Match on: exact, contains, Levenshtein distance < 3
- Use `ledger-context/projects.json` for explicit aliases:
```json
{
  "dotfiles": ["dotfiles", ".dotfiles", "dotfiles-main"],
  "agent-ledger": ["agent-ledger", "ledger", "claude-ledger"]
}
```

---

## Decisions Made

1. **Auto-query**: Always query ledger at session start - no exceptions
2. **Consolidation**: Replace CONTINUITY.md with LEDGER system entirely
3. **Matching**: Path-based fuzzy matching (full path + basename)

---

## Final AGENTS.md Content

```markdown
# Agent Ledger

Cross-session memory at `~/.claude/LEDGER.jsonl`. Query on start. Write on end.

## Session Start (MANDATORY)

Run immediately at every session start:

```bash
PROJECT_PATH=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
PROJECT=$(basename "$PROJECT_PATH")

# 1. Get frontmatter for matching sessions
jq -c '{id:._meta.id, ts:._meta.ts, project:.front.project, path:.front.path, title:.front.title, status:.front.status, tags:.front.tags}' ~/.claude/LEDGER.jsonl 2>/dev/null | grep -iE "$PROJECT|$PROJECT_PATH" | tail -10

# 2. Extract lessons (your accumulated knowledge)
jq -r 'select(.front.path | test("'"$PROJECT_PATH"'"; "i")) | .body.lessons[]' ~/.claude/LEDGER.jsonl 2>/dev/null | sort -u
```

If matches found: scan frontmatter, inject relevant lessons into your context. Pull full record details when you need specific implementation context:

```bash
jq 'select(._meta.id == "RECORD_ID")' ~/.claude/LEDGER.jsonl
```

## Session End (MANDATORY)

Append ONE complete JSON record before session closes:

```bash
cat >> ~/.claude/LEDGER.jsonl << 'RECORD'
{"_meta":{"id":"<uuid>","ts":"<iso-8601>","v":1},"front":{"project":"<name>","path":"<abs-path>","title":"<one-line>","type":"<feature|bugfix|refactor|docs|config|research>","status":"<completed|partial|failed>","tags":["<keywords>"]},"body":{"agent":{"model":"<model>","tool":"claude-code"},"git":{"branch":"<branch>","commit":"<sha>"},"input":"<original-request>","actions":["<step1>","<step2>"],"files":[{"path":"<file>","op":"<C|M|D>","lines":"<+/-N>","why":"<purpose>"}],"decisions":[{"choice":"<what>","alts":["<other-options>"],"reason":"<why>"}],"lessons":["<patterns-for-future>"]},"history":{"embedded":<true|false>,"content":"<transcript-if-short>","ref":"<ledger-context/sessions/file.md-if-long>"}}
RECORD
```

### Field Requirements

| Field | What to capture |
|-------|-----------------|
| `front.project` | Normalized name (lowercase) |
| `front.path` | Absolute path - primary matching key |
| `front.title` | One-line summary |
| `body.actions` | Every significant step |
| `body.files` | All changes with op/lines/purpose |
| `body.decisions` | Choices + alternatives + reasoning |
| `body.lessons` | **MOST IMPORTANT** - patterns for future sessions |

**Never skip fields.** Your future self retrieves these records.

## Why This Protocol Exists

Each session's lessons become the next session's context. Quality records compound into project expertise. This is not external compliance - this is how you accumulate knowledge across context boundaries.

Long sessions (>50 messages): write history to `~/.claude/ledger-context/sessions/<date>_<project>_<slug>.md`, set `embedded: false`, add `ref` path.
```

---

## Files to Create/Modify

| Path | Action |
|------|--------|
| `~/.claude/LEDGER.jsonl` | Create (empty) |
| `~/.claude/ledger-context/` | Create directory |
| `~/.claude/ledger-context/sessions/` | Create directory |
| `~/.claude/ledger-context/index.md` | Create (template) |
| `~/.claude/AGENTS.md` | Create with above content |
| `~/.claude/CLAUDE.md` | Remove "Continuity Ledger" section, add `## Agent Ledger\nSee AGENTS.md` |

---

## Supplementary File Content

### `ledger-context/index.md`

```markdown
# Agent Ledger Index

Human-curated semantic index. Update as patterns emerge.

## Projects

<!-- Add entries as projects accumulate sessions -->

## Cross-Project Patterns

<!-- Document recurring patterns -->

## Known Gotchas

<!-- Traps to avoid -->
```

---

## Implementation Sequence

1. `touch ~/.claude/LEDGER.jsonl`
2. `mkdir -p ~/.claude/ledger-context/sessions`
3. Write `~/.claude/ledger-context/index.md` (template above)
4. Write `~/.claude/AGENTS.md` (final content above)
5. Edit `~/.claude/CLAUDE.md`:
   - Remove lines 8-33 ("Continuity Ledger" section)
   - Add: `## Agent Ledger\n\nSee [AGENTS.md](AGENTS.md) for cross-session memory protocol.`
