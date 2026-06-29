---
name: personal-os
description: Maintain the user's private Personal OS at ~/.codex/personal-os for journal entries, explicit episodes, daily Chronicle-assisted reflections, profile synthesis, reversible Things task creation, and opt-in automation.
---

# Personal OS

Personal OS is the private personal-memory layer. It is separate from the
external-source LLM wiki and separate from Codex operational memory.

Use `scripts/personal.py` for deterministic operations. Do not write directly to
`~/.codex/wiki`, `~/.codex/memories`, Calendar, Things, or LaunchAgents unless
the user explicitly asks for the matching command.

## Paths

| Alias | Path | Purpose |
| --- | --- | --- |
| `PERSONAL_ROOT` | `~/.codex/personal-os` | Private personal memory root |
| `PERSONAL_RULES` | `~/.codex/personal-os/rules.md` | Maintenance rules |
| `PERSONAL_JOURNAL` | `~/.codex/personal-os/journal` | Raw user-authored daily entries |
| `PERSONAL_EPISODES` | `~/.codex/personal-os/episodes` | Explicit session or Chronicle distillations |
| `PERSONAL_REFLECTIONS` | `~/.codex/personal-os/reflections` | Generated reflection drafts |
| `PERSONAL_PROFILE` | `~/.codex/personal-os/profile` | Durable synthesized personal notes |
| `PERSONAL_LOGS` | `~/.codex/personal-os/_logs/runs` | Side-effect run logs |

## Operating Rules

- Raw journal and episode content is private by default.
- Keep raw personal material out of `~/.codex/wiki`.
- Do not write to `~/.codex/memories`; that is Codex operational memory.
- Calendar writes are not allowed in v1. Generate candidates only.
- Personal files are not bulk-indexed in v1. Add them only when the user gives
  a specific file or folder.
- Side effects must be explicit: `--write`, `--apply`, `install`, `enable`,
  `disable`, or `uninstall`.
- Every side-effecting command writes a JSON run log and commits local Personal
  OS file changes unless `--no-commit` is passed before the subcommand.
- Things writeback goes to Inbox with a `Personal OS` tag and source note.
- Things rollback uses recorded Things IDs and cancels only tasks created by
  Personal OS.

## Common Tasks

### Bootstrap

```bash
~/.codex/skills/personal-os/scripts/personal.py bootstrap
~/.codex/skills/personal-os/scripts/personal.py verify
```

Bootstrap writes only inside `~/.codex/personal-os`, initializes a private local
git repo, and creates an uninstalled LaunchAgent template.

### Capture Journal Or Episode Text

```bash
printf '%s\n' "Today I noticed..." | \
  ~/.codex/skills/personal-os/scripts/personal.py capture journal --title "Evening note" --stdin

printf '%s\n' "Session summary..." | \
  ~/.codex/skills/personal-os/scripts/personal.py capture episode --source codex --title "Setup session" --stdin
```

### Daily Reflection

```bash
~/.codex/skills/personal-os/scripts/personal.py reflect daily --date today
~/.codex/skills/personal-os/scripts/personal.py reflect daily --date today --write
```

Without `--write`, this previews the reflection. With `--write`, it writes a
daily reflection and logs/commits the run.

### Profile Updates

```bash
~/.codex/skills/personal-os/scripts/personal.py profile update --from-reflection PATH
~/.codex/skills/personal-os/scripts/personal.py profile update --from-reflection PATH --apply
```

Profile updates only use explicit lines such as `preference: ...`,
`pattern: ...`, `routine: ...`, or `value: ...` from a reflection, and every
written line cites the source reflection path.

### Things Actions

```bash
~/.codex/skills/personal-os/scripts/personal.py actions plan --from-reflection PATH
~/.codex/skills/personal-os/scripts/personal.py actions plan --from-reflection PATH --write
~/.codex/skills/personal-os/scripts/personal.py actions apply --plan PATH
~/.codex/skills/personal-os/scripts/personal.py actions rollback --run-id RUN_ID
```

Only explicit action lines are used, such as `ACTION: ...`, `TODO: ...`,
`NEXT: ...`, `FOLLOW UP: ...`, or Markdown unchecked checkboxes.

### Automation

```bash
~/.codex/skills/personal-os/scripts/personal.py automation install
~/.codex/skills/personal-os/scripts/personal.py automation enable
~/.codex/skills/personal-os/scripts/personal.py automation disable
~/.codex/skills/personal-os/scripts/personal.py automation uninstall
```

Automation is opt-in. Bootstrap does not install or enable the LaunchAgent.

### Inspect

```bash
~/.codex/skills/personal-os/scripts/personal.py scan recent --limit 30
~/.codex/skills/personal-os/scripts/personal.py index
~/.codex/skills/personal-os/scripts/personal.py verify
```

Use these before making changes when you need current state.
