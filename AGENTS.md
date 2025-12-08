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
### 2025-12-08 — Add Cursor IDE configuration to bootstrap sequence
- Added `cursor/` directory with `settings.json`, `keybindings.json`, and `extensions.txt`.
- Added `cursor-cli` cask to Brewfile (provides `cursor-agent` command).
- Bootstrap symlinks settings and keybindings to `~/Library/Application Support/Cursor/User/`.
- Extensions installed via `cursor-agent --install-extension` if CLI available.
- Follows symlink pattern so dotfiles remain single source of truth.

### 2025-12-08 — Add Raycast config import to bootstrap sequence
- Added Raycast configuration import section to `start.sh` after Git LFS setup.
- Opens Raycast import dialog via deeplink (`raycast://extensions/raycast/raycast/import-settings-data`) and reveals the `.rayconfig` file in Finder.
- User just needs to select the revealed file to complete import.
- Graceful fallback if Raycast isn't installed or config file is missing.
- Follows existing idempotent/skip-friendly pattern used throughout bootstrap.

### 2025-12-08 — Add screenshots.sh for screenshot location configuration
- Added standalone `screenshots.sh` script to configure macOS default screenshot save location.
- Uses `defaults write com.apple.screencapture location` and restarts SystemUIServer to apply immediately.
- Designed to be run independently after SynologyDrive or other sync services are configured.
- Supports CLI arguments, environment variable override, --show, --reset, and --help options.
- Default location: `~/Pictures/Screenshots`.

### 2025-12-08 — Disable Spotlight shortcuts; document Lock Screen limitation
- Added automation to disable Spotlight keyboard shortcuts (Cmd+Space and Cmd+Option+Space) via PlistBuddy.
- This frees Cmd+Space for Raycast or other launchers without manual System Settings interaction.
- Uses `com.apple.symbolichotkeys.plist` keys 64 (Spotlight search) and 65 (Finder search window).
- Note: Spotlight changes require logout/restart to take effect.
- **Lock Screen shortcut (Option+L) CANNOT be automated**: "Lock Screen" is in the Apple Menu (️), which does not respect NSUserKeyEquivalents. Removed non-functional code and added clear manual setup instructions.
- Reference: This is a known macOS limitation for all Apple Menu items.

### 2025-12-08 — Add home folder control in Locations section
- Added `--hide-home-in-locations` / `--show-home-in-locations` to control home folder visibility in Locations.
- Home folder in Locations uses `SpecialItemIdentifier: com.apple.LSSharedFileList.IsHome`.
- This is separate from Favorites where home folder is controlled by `sidebarctl`.
- Added to `--all-hidden` preset.

### 2025-12-08 — Fix Locations items visibility by setting item-level properties
- Fixed Computer and iCloud Drive not hiding: must set `visibility` on items by `SpecialItemIdentifier`, not just file-level properties.
- Items in FavoriteVolumes.sfl4 have their own `visibility` property that takes precedence over file-level settings.
- Removed iCloudItems.sfl4 handling (was for iCloud section, not Locations).
- Note: AirDrop doesn't appear in SFL files on macOS Sequoia; no programmatic control found.

### 2025-12-08 — Extended sidebarsections to control Locations items
- Added support for hiding/showing: Computer, iCloud Drive, cloud services, hard drives, network volumes.
- New options: `--hide-computer`, `--hide-icloud-drive`, `--hide-cloud-services`, `--hide-hard-drives`, `--hide-network-volumes` (and corresponding `--show-*` variants).
- Added `--locations-minimal` preset and expanded `--all-hidden` to include Locations items.
- Controls `FavoriteVolumes.sfl4` for Locations section.

### 2025-12-08 — Consistency fixes across finder.sh and sidebarctl.swift
- Fixed `finder.sh` to also update scripts when source is newer (same issue as `.macos`).
- Fixed `finder.sh` DS_Store cleanup to only clean Desktop/Documents/Downloads (was recursively searching entire `$HOME`).
- Improved `sidebarctl.swift` error handling to match `sidebarsections.swift` (better file existence checks and error messages).

### 2025-12-08 — Fix sidebar script install to update when source changes
- Changed `install_sidebarctl()` and `install_sidebarsections()` in `.macos` to update installed scripts when source is newer.
- Root cause: The install functions returned early if the script already existed, leaving stale versions in place after pulling fixes.

### 2025-12-08 — Fix sidebarsections missing file handling
- Updated `bin/sidebarsections.swift` to create SFL files if they don't exist, matching the pattern from `sidebarctl.swift`.
- Added `createEmptyTopSidebarSectionIfMissing()` and `createEmptyNetworkBrowserIfMissing()` helper functions.
- Improved `openSFL()` error handling to distinguish between missing files vs permission errors.
- Root cause: On fresh macOS installs, `TopSidebarSection.sfl4` and `NetworkBrowser.sfl4` may not exist yet; the script was incorrectly reporting "Full Disk Access required" for missing files.

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
