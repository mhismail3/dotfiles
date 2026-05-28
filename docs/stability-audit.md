# Mac Mini Stability Audit

This branch should be boring by default. The default setup path should install only durable primitives that are useful on every deploy and unlikely to require app-specific login, volatile UI state, or frequent manual repair.

## Default Setup Standard

Keep default setup items if they are:

- Needed for remote access, shell work, Git, Codex/Claude bootstrap, sync, or local model/service basics.
- Idempotent across fresh installs and repeated runs.
- Safe to run without committing secrets, local data, cookies, runtime databases, or credentials.
- Useful even when the Mac Mini is headless and accessed through Tailscale.

Move items to `Brewfile.optional` if they are:

- Login-heavy GUI apps.
- Project-specific or task-specific.
- Apps with large mutable local state.
- Apps whose failure should not block a fresh server bootstrap.
- Convenience tools that can be installed after the server is reachable.

## Changes From Audit

- Kept the default Brewfile focused on CLI primitives, language runtimes, Tailscale, Syncthing, Codex, Claude Code, and Ollama.
- Moved Cursor, Ghostty, Chrome, Docker Desktop, Container, RustDesk, PIA, Synology Drive, Google Drive, `mas`, `xcodegen`, `agent-browser`, Google Workspace CLI, and `tron-twitter` to `Brewfile.optional`.
- Added Syncthing to the default install and service startup path because the Mac Mini is the planned personal-file sync hub.
- Removed brittle `.macos` automation for auto-login, Remote Management/ARD, LaunchServices quarantine disabling, and Caps Lock LaunchDaemon remapping.
- Updated `.macos` to use `mac-mini` as the system name and keep critical system/security data updates enabled while avoiding surprise macOS upgrades.

## Known Legacy Surface

The `claude/` directory still contains historical Claude setup and tracked plan files. This audit did not remove or rewrite that content because the current pass was scoped to keeping Claude intact while hardening the Mac Mini and Codex setup path.

If this branch later needs a deeper cleanup, handle Claude as a separate migration with its own backup and review step.
