---
name: things-3
description: Work with Things 3 task data on this Mac. Use when Codex needs to read, search, summarize, understand, create, schedule, move, complete, cancel, show, or edit Things 3 to-dos, projects, areas, tags, or next actions through the local Things app.
---

# Things 3

Use Things' supported AppleScript automation for normal read/write work. Prefer
`scripts/things.py` because it returns JSON and avoids brittle UI automation.

## Quick Start

```bash
~/.codex/skills/things-3/scripts/things.py snapshot --open-only
~/.codex/skills/things-3/scripts/things.py search "call"
~/.codex/skills/things-3/scripts/things.py add "Review Q3 plan" --notes "Draft first" --when tomorrow --tag Work
~/.codex/skills/things-3/scripts/things.py complete <things-id>
```

Read `references/automation.md` when adding new operations, debugging Things
automation, or inspecting local storage.

## Operating Rules

- Use AppleScript/Things commands for writes.
- Treat the local Things SQLite database as private and read-only. Never write to
  it directly.
- Prefer `complete` or `cancel` over `delete`. Use delete only when the user
  explicitly asks or the script is deleting a temporary item it created.
- Before large writes, run a read/search first and identify target item IDs.
- After writes, run `snapshot`, `search`, or `show` to verify the result.
- Do not commit task data, Things Cloud credentials, or local Things databases.

## Common Tasks

### Understand the System

Run `snapshot --open-only`, then group by `areaName`, `projectName`, `tagNames`,
`status`, deadlines, and scheduled dates. Use this for planning, reviews, and
finding stale tasks.

### Create Tasks

Use `add`. Target a project, area, or built-in list with `--list` when known.
Use `--when` for scheduled dates and `--deadline` for due dates.

### Update Tasks

Use `search` to find IDs, then call:

- `complete <id>`
- `cancel <id>`
- `schedule <id> YYYY-MM-DD`
- `deadline <id> YYYY-MM-DD`
- `move <id> "<list name>"`
- `show <id>` or `edit <id>` for user-visible review

### User-Facing Reviews

When summarizing Things, include concrete task names, projects/areas, and dates.
Avoid dumping raw JSON unless the user asks for it.
