# AGENTS.md

AI agent log and operations guide for this dotfiles repository. Use it as the single source of truth for what changed, why, and how to work safely.

## How to use this file
- Read the topmost entries before editing; they describe current expectations and recent decisions.
- When you make a change that affects behavior, add a dated entry (YYYY-MM-DD) at the top with what changed, why, and the primary files touched.
- Keep entries concise; link to README for user-facing details when applicable.
- Maintain idempotency and macOS compatibility; prefer environment-derived paths over hardcoded ones.
- Avoid destructive commands; ask for confirmation when a step risks losing user data.

## Current expectations for this repo
- Scripts must stay idempotent and macOS-only; detect Homebrew prefix and use $HOME/$DOTFILES instead of absolute paths.
- Bootstrapping flows live in `start.sh`; system defaults and Dock/layout automation live in `.macos` (with Finder sidebar helpers in `finder.sh`/`bin/sidebarctl.swift`); package sources live in `Brewfile`.
- Shell startup performance relies on lazy-loading version managers (pyenv, nvm, rbenv) and streamlined fzf/history settings—preserve that behavior when editing shell files.
- Some tasks remain manual by design (Apple ID/App Store sign-in, display "More Space", device-specific peripherals); do not attempt to automate them without approval.

## Timeline (newest first)
### 2025-12-08 — Automate hiding Recents/Shared sidebar sections
- Added `bin/sidebarsections.swift` to programmatically hide Recents and Shared sections from Finder sidebar by editing `com.apple.LSSharedFileList.TopSidebarSection.sfl4` and `com.apple.LSSharedFileList.NetworkBrowser.sfl4`.
- Integrated into `.macos` via `configure_sidebar_sections()` function.
- Key insight: The SFL files use NSKeyedArchiver format; TopSidebarSection contains cannedSearch references for Recents/Shared; NetworkBrowser has `bonjourEnabled` property.

### 2025-12-08 — Fix .DS_Store cleanup hang + add progress messages
- Changed `reset_home_ds_store` to only clean Desktop/Documents/Downloads instead of recursively searching the entire home directory (which could take minutes on large ~/Library).
- Added echo statements throughout `.macos` so each major section announces itself, making it easier to identify where hangs occur.
- Root cause: `find "$HOME" -name ".DS_Store" -delete` was traversing 50GB+ of ~/Library with thousands of directories.

### 2025-12-08 — Dockutil hang fix: polling timeout + Dock restart
- Replaced background-subshell timeout with polling-based timeout (more reliable on macOS where `wait` can block indefinitely on signaled processes).
- Added immediate `killall Dock` after dockutil loop completes to apply all `--no-restart` changes and reset Dock state before subsequent `defaults write` commands.
- Root cause: the manual timeout's `wait "$pid"` could hang if dockutil entered an uninterruptible state; also, Dock remained in a dirty state after many rapid `--no-restart` operations.

### 2025-12-08 — Dockutil hang fallback
- Dock layout now enforces a hard timeout per dockutil call: prefers gtimeout/timeout but falls back to an inline watcher that kills the process after the configured interval. Helps avoid stalls during bootstrap even when no timeout utility is installed.

### 2025-12-08 — Finder sidebar FDA hint
- Added explicit Full Disk Access guidance when `sidebarctl` cannot read/write Finder favorites (opens Privacy & Security → Full Disk Access deep link and surfaces SFL path).
- Goal: give operators a clear remediation path when macOS blocks sidebar automation.

### 2025-12-08 — Dockutil hang guard
- Added timeout wrapper (`gtimeout`/`timeout` if available) around dockutil remove/add to prevent hangs during Dock configuration.
- Goal: ensure bootstrap continues even if dockutil stalls on Sequoia.

### 2025-12-06 — Agent log rewrite and rule cleanup
- Renamed the changelog to `AGENTS.md` and rewrote it as an agent-first, reverse-chronological log that captures rationale.
- Generalized `.cursorrules` to remove project-specific references while keeping doc/update/commit expectations.
- Goal: give agents a concise single source for history and intent, reducing confusion when starting work.

### 2024-12-06 — Automated Dock layout
- Added `dockutil` and `stremio` to `Brewfile`; `.macos` now sets the Dock order via an idempotent loop to avoid duplicates, restarting Dock only once.
- Goal: provide consistent Dock configuration across reruns without manual cleanup.

### 2024-12-?? — Night Shift + Finder sidebar automation
- Added `nightlight` CLI and automated Night Shift (Sunset→Sunrise, 70% warmth).
- Bundled `sidebarctl.swift` and `finder.sh` to configure Finder sidebar favorites (Home, Applications, Downloads, iCloud Drive) with optional `.DS_Store` reset for idempotent reruns.
- Goal: remove recurring manual steps after bootstrap while keeping reruns safe.

### 2024-12-?? — Comprehensive audit and performance improvements
- Cleaned Brewfile taps; replaced `unrar` with `unar`; added `git-delta`; commented out `yarn` in favor of corepack.
- Optimized shell startup (lazy-loading pyenv/nvm/rbenv, `fzf --zsh`, larger history with safety flags).
- Hardened `start.sh` for idempotency (macOS check, smarter symlinks with backups, improved Homebrew detection, optional `.macos` prompt) and tightened `ssh.sh` permissions/config.
- Updated Mackup paths, aliases (`fnd`, `rgrep`, `reload`), git settings (delta theme, rerere, branch sort, SSH URL rewrite, GPG placeholders), and macOS defaults messaging.
- Goal: reduce latency, align tooling, and make repeated runs safe.

### 2024-12-?? — Initial creation
- Established the dotfiles baseline: bootstrap entrypoint, macOS defaults, Brewfile inventory, Zsh/Oh My Zsh setup with lazy-loaded managers, SSH helper, Mackup configs, and key architecture choices (qBittorrent, Keka, dockutil, lazy-loading strategy).
- Goal: enable single-command setup for the Mac Mini home server with repeatable results.
