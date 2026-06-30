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
| `PERSONAL_FILES` | `~/.codex/personal-os/files` | Private important files, manifests, extracts, summaries, and indexes |
| `PERSONAL_BUTLER` | `~/.codex/personal-os/_views/butlers-book.md` | Main private context entrypoint for agents |
| `PERSONAL_LOGS` | `~/.codex/personal-os/_logs/runs` | Side-effect run logs |

## Operating Rules

- Raw journal and episode content is private by default.
- Keep raw personal material out of `~/.codex/wiki`.
- Do not write to `~/.codex/memories`; that is Codex operational memory.
- Calendar writes are not allowed in v1. Generate candidates only.
- Personal files are added only when the user gives a specific file or folder.
  Raw copies live under `files/originals/` by default and are committed to the
  private Personal OS git repo.
- Use `files/manifests/` as the source of truth for document provenance,
  extraction state, duplicate state, and review state.
- Use `_views/butlers-book.md` as the first read for private personal context.
- Side effects must be explicit: `--write`, `--apply`, `install`, `enable`,
  `disable`, or `uninstall`.
- Every side-effecting command writes a JSON run log and commits local Personal
  OS file changes unless `--no-commit` is passed before the subcommand.
- Things writeback goes to the `🤖 Agent Tasks` project with a `Personal OS`
  marker and source note.
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

### Files And Butler's Book

```bash
~/.codex/skills/personal-os/scripts/personal.py file add ~/Documents/example.pdf --kind reference
~/.codex/skills/personal-os/scripts/personal.py file add-folder ~/Documents/Important --recursive --dry-run
~/.codex/skills/personal-os/scripts/personal.py file add-folder ~/Documents/Important --recursive --write
~/.codex/skills/personal-os/scripts/personal.py file extract --file-id FILE_ID --write
~/.codex/skills/personal-os/scripts/personal.py file summarize --file-id FILE_ID --write
~/.codex/skills/personal-os/scripts/personal.py file search "insurance"
~/.codex/skills/personal-os/scripts/personal.py file verify
~/.codex/skills/personal-os/scripts/personal.py file recheck --write
~/.codex/skills/personal-os/scripts/personal.py butler rebuild --write
```

`file add` copies the raw file into `files/originals/` by default and creates a
JSON manifest in `files/manifests/`. Bulk folder intake is dry-run by default
and needs `--write` to copy files. Local extraction uses deterministic tools
first; missing OCR/model synthesis is surfaced as `needs_ocr` or
`pending_agent` instead of being hidden.

### Daily Gardening

```bash
~/.codex/skills/personal-os/scripts/personal.py garden daily --date today
~/.codex/skills/personal-os/scripts/personal.py garden daily --date today --write
```

The garden rechecks file hashes, extracts pending files, writes deterministic
intake summaries/outlines, rebuilds `_views/`, writes a garden report, and
creates deduped Things follow-ups in `🤖 Agent Tasks` for concrete maintenance
queues.

### Automation

```bash
~/.codex/skills/personal-os/scripts/personal.py automation install
~/.codex/skills/personal-os/scripts/personal.py automation enable
~/.codex/skills/personal-os/scripts/personal.py automation disable
~/.codex/skills/personal-os/scripts/personal.py automation uninstall
```

Automation is opt-in. Bootstrap does not install or enable the LaunchAgent.
When installed and enabled, the LaunchAgent runs `garden daily --date today
--write` at 10:30 PM local time.

### Inspect

```bash
~/.codex/skills/personal-os/scripts/personal.py scan recent --limit 30
~/.codex/skills/personal-os/scripts/personal.py index
~/.codex/skills/personal-os/scripts/personal.py verify
```

Use these before making changes when you need current state.
