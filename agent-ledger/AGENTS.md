# Agent Ledger Protocol

Persistent memory at `~/.agent-ledger/`. Read on start, write on end.

## Session Start

```bash
PROJECT=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")

# Recent history
grep "\"name\":\"$PROJECT\"" ~/.agent-ledger/ledger.jsonl | tail -5

# Accumulated lessons
grep "\"name\":\"$PROJECT\"" ~/.agent-ledger/ledger.jsonl | jq -r '.lessons[]' 2>/dev/null | sort -u
```

Inject relevant findings into context before proceeding.

---

## Session End

Append ONE JSON line to `~/.agent-ledger/ledger.jsonl`. Include ALL fields.

```bash
echo '{ ... complete record ... }' >> ~/.agent-ledger/ledger.jsonl
```

### Record Schema

```json
{
  "id": "uuid",
  "ts": "2025-12-15T10:30:00Z",
  "agent": { "model": "claude-sonnet-4", "provider": "anthropic", "tool": "cursor" },
  "project": { "name": "dotfiles", "path": "/Users/moose/.dotfiles", "git_branch": "main", "git_commit": "abc1234" },
  "task": {
    "title": "Add SSH key generation script",
    "type": "feature|bugfix|refactor|docs|config",
    "input": "User's original request",
    "trigger": "What prompted this"
  },
  "context": {
    "prior_state": "State before this task",
    "dependencies": ["patterns/code this builds on"]
  },
  "execution": {
    "actions": ["Step 1", "Step 2", "Step 3"],
    "files_changed": [
      { "path": "setup/ssh.sh", "change": "created|modified|deleted", "lines": "+45", "purpose": "Why" }
    ],
    "commands_run": ["significant commands"]
  },
  "decisions": [
    { "choice": "What was decided", "alternatives": ["other options"], "reason": "Why this choice" }
  ],
  "outcome": {
    "status": "completed|partial|failed",
    "verification": "How validated",
    "issues": "Problems encountered",
    "follow_up": null
  },
  "lessons": [
    "Pattern or preference learned for future sessions",
    "These are the PRIMARY retrieval target"
  ],
  "chat_history": {
    "embedded": true,
    "content": "**User:** ...\n\n**Assistant:** ..."
  },
  "tags": ["searchable", "keywords"]
}
```

### Chat History

- **Short sessions (<50 messages):** Embed in `chat_history.content`
- **Long sessions:** Write to `~/.agent-ledger/sessions/<date>_<project>_<slug>.md`, set `embedded: false`, add `location` field

---

## Field Requirements

| Field | Critical Content |
|-------|------------------|
| `execution.actions` | Detailed step-by-step of what was done |
| `execution.files_changed` | Every file with change type, lines, purpose |
| `decisions` | Each choice with reasoning and alternatives |
| `lessons` | Patterns that should inform future sessions |
| `chat_history` | Full transcript or link to session file |

**Never skip fields.** Incomplete records break retrieval.
