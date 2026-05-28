# Codex Setup

This directory contains only Codex bootstrap and portable sync tooling. It does not store Codex auth, cookies, runtime databases, worktrees, plugin caches, or secrets.

## What Setup Installs

`./setup.sh` installs the Codex Homebrew cask, copies `codex/portable/codex_portable.py` into `~/.codex/portable/`, configures a shared `CodexPortable` remote, and offers to pull the current portable backup when one exists.

Default remote selection:

- iCloud Documents if present: `~/Library/Mobile Documents/com~apple~CloudDocs/Documents/CodexPortable`
- Otherwise: `~/Documents/CodexPortable`

## Normal Flow

Before using Codex on this Mac:

```bash
~/.codex/portable/codex_portable.py sync-pull --yes
~/.codex/portable/codex_portable.py doctor --verify-remote
```

After meaningful Codex setup changes on this Mac:

```bash
~/.codex/portable/codex_portable.py sync-push
```

For a smaller config-only backup:

```bash
~/.codex/portable/codex_portable.py sync-push --core-only --no-archive
```

## Safety Rules

- Log in to Codex separately on each Mac.
- Do not sync `auth.json`, browser cookies, runtime SQLite databases, plugin caches, worktrees, or temp folders.
- Do not run Codex concurrently on multiple Macs while syncing UI preferences.
- Treat portable bundles as sensitive because they can contain prompts, paths, UI state, and audit-only session transcripts.
