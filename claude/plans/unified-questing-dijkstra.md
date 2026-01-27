# Plan: Reorganize ~/.tron Folder Structure

## Overview
Reorganize the `~/.tron` folder from a flat structure to a hierarchical one with dedicated subfolders for databases, rules, and mods.

## Target Structure
```
~/.tron/
├── app/              # (keep) prod server configuration
├── notes/            # (keep) voice notes
├── skills/           # (keep) global skills
├── mods/             # (NEW) modifications/extensions
│   └── transcribe/   # (moved from root)
├── db/               # (NEW) all database files
│   ├── prod.db       # (renamed from events.db)
│   └── beta.db       # (renamed from events-beta.db)
├── rules/            # (NEW) markdown rules/prompts
│   ├── claude.md     # context rules (moved from root)
│   ├── system.md     # system prompt (moved from root)
│   └── TRON.md       # reference doc (moved from root, not auto-loaded)
├── auth.json         # (keep at root)
└── settings.json     # (keep at root)
```

## Code Changes Required

### 1. Database Path Updates (7 files)

**Naming changes:**
- `events.db` → `db/prod.db`
- `events-beta.db` → `db/beta.db`

| File | Line | Change |
|------|------|--------|
| `packages/server/src/index.ts` | 69 | `'events.db'` → `'db/prod.db'` |
| `packages/server/src/event-store-orchestrator.ts` | 176 | `'.tron', 'events.db'` → `'.tron', 'db', 'prod.db'` |
| `packages/tui/src/app.tsx` | 576 | `'events.db'` → `'db', 'prod.db'` |
| `packages/ios-app/Sources/Database/EventDatabase.swift` | 33 | `"events.db"` → `"db/prod.db"` (also create db/ directory) |
| `beta` | 39, 49 | `events-beta.db` → `db/beta.db` |
| `scripts/tron` | 301, 303, 436, 438 | `events.db` → `db/prod.db`, `events-beta.db` → `db/beta.db` |
| `scripts/event-tree` | 16, 70, 83 | `events.db` → `db/prod.db` |

### 2. Rules/Markdown Path Updates (2 files)

| File | Line | Change |
|------|------|--------|
| `packages/core/src/context/system-prompts.ts` | 109 | `'.tron', 'SYSTEM.md'` → `'.tron', 'rules', 'SYSTEM.md'` (also check `system.md` lowercase) |
| `packages/core/src/context/loader.ts` | 164 | `'.tron'` → `'.tron', 'rules'` |

**Changes to system-prompts.ts:**
- Update global path from `~/.tron/SYSTEM.md` to `~/.tron/rules/SYSTEM.md`
- Add fallback check for lowercase `system.md` (try SYSTEM.md first, then system.md)
- Keep project-level paths unchanged (`.tron/SYSTEM.md`)

**Note**: `TRON.md` is moved but not automatically loaded (just for manual reference)

### 3. Transcribe Path Updates (4 files)

| File | Line | Change |
|------|------|--------|
| `packages/server/src/transcription-sidecar.ts` | 83 | `'.tron', 'transcribe'` → `'.tron', 'mods', 'transcribe'` |
| `services/transcribe/config.py` | 9 | `~/.tron/transcribe` → `~/.tron/mods/transcribe` |
| `services/transcribe/write-config.sh` | 17, 71 | `~/.tron/transcribe` → `~/.tron/mods/transcribe` |
| `services/transcribe/README.md` | 38, 95-96 | Update doc paths |

### 4. Documentation Updates (2 files)

| File | Lines | Change |
|------|-------|--------|
| `docs/event-sourced-session-system.md` | 18, 379, 455, 510, 878, 889-890 | `events.db` → `db/prod.db` |
| `README.md` | 120-121 | Update database path table: `events.db` → `db/prod.db`, `events-beta.db` → `db/beta.db` |

## Physical File Moves
Execute after code changes are complete:
```bash
# Create new directories
mkdir -p ~/.tron/db ~/.tron/mods ~/.tron/rules

# Move and rename database files (including WAL/SHM)
mv ~/.tron/events.db ~/.tron/db/prod.db
mv ~/.tron/events.db-shm ~/.tron/db/prod.db-shm 2>/dev/null || true
mv ~/.tron/events.db-wal ~/.tron/db/prod.db-wal 2>/dev/null || true
mv ~/.tron/events-beta.db ~/.tron/db/beta.db
mv ~/.tron/events-beta.db-shm ~/.tron/db/beta.db-shm 2>/dev/null || true
mv ~/.tron/events-beta.db-wal ~/.tron/db/beta.db-wal 2>/dev/null || true

# Move transcribe to mods
mv ~/.tron/transcribe ~/.tron/mods/

# Move markdown rules files (keep original names)
mv ~/.tron/claude.md ~/.tron/rules/
mv ~/.tron/system.md ~/.tron/rules/
mv ~/.tron/TRON.md ~/.tron/rules/
```

## Summary of Files to Modify

**TypeScript (4 files)**
- `packages/server/src/index.ts`
- `packages/server/src/event-store-orchestrator.ts`
- `packages/tui/src/app.tsx`
- `packages/server/src/transcription-sidecar.ts`

**Core context loading (2 files)**
- `packages/core/src/context/system-prompts.ts`
- `packages/core/src/context/loader.ts`

**iOS app (1 file)**
- `packages/ios-app/Sources/Database/EventDatabase.swift`

**Shell scripts (3 files)**
- `beta`
- `scripts/tron`
- `scripts/event-tree`

**Python/transcribe (2 files)**
- `services/transcribe/config.py`
- `services/transcribe/write-config.sh`

**Documentation (3 files)**
- `services/transcribe/README.md`
- `docs/event-sourced-session-system.md`
- `README.md`

**Code comments to update (4 files)** - optional but recommended:
- `packages/core/src/hooks/builtin/pre-compact.ts`
- `packages/core/src/hooks/builtin/session-start.ts`
- `packages/core/src/hooks/builtin/session-end.ts`
- `packages/server/src/orchestrator/types.ts` (default path comment)

## Verification Steps

1. **Build**: `bun run build` passes
2. **Tests**: `bun run test` passes
3. **Beta server**: `./beta` starts and uses `~/.tron/db/beta.db`
4. **Prod server**: Server starts and uses `~/.tron/db/prod.db`
5. **TUI**: Connects to `~/.tron/db/prod.db`
6. **Transcription**: Sidecar starts from `~/.tron/mods/transcribe/`
7. **Rules loading**: Global rules loaded from `~/.tron/rules/`

## Notes
- Environment variables still work as overrides (TRON_EVENT_STORE_DB, TRON_TRANSCRIBE_BASE_DIR)
- Project-level paths unchanged (`.tron/SYSTEM.md`, `.tron/skills/`)
- System prompt loader updated to check both `SYSTEM.md` and `system.md` (case-insensitive)
- `TRON.md` moved but not auto-loaded (reference documentation only)
- Test files continue to use `events.db` as test database name (no change needed)
