# Changelog

All notable changes to this dotfiles project are documented in this file.

> **For AI Agents:** This changelog is your primary reference for understanding the project state, architecture decisions, and modification history. Always consult this before making changes.

---

## Project Context

| Key | Value |
|-----|-------|
| **Owner** | moose (mhismail3@gmail.com) |
| **Machine** | Mac Mini home server ("moose-home-server") |
| **Location** | `~/.dotfiles` |
| **NAS** | MooseStation (`smb://MooseStation`) |
| **Bootstrap** | `curl -fsSL https://raw.githubusercontent.com/mhismail3/dotfiles/main/start.sh \| zsh` |

---

## Current File Structure

```
~/.dotfiles/
├── start.sh              # Bootstrap script (entry point)
├── .macos                # macOS preferences + Dock layout
├── Brewfile              # Homebrew packages/apps
├── ssh.sh                # SSH key generation
├── .zshrc                # Zsh configuration
├── aliases.zsh           # Shell aliases
├── path.zsh              # PATH modifications
├── .gitconfig            # Git configuration
├── .gitignore_global     # Global gitignore
├── .mackup.cfg           # Mackup configuration
├── .mackup/              # Custom Mackup app configs
│   ├── synology-drive.cfg
│   └── google-drive.cfg
├── README.md             # User-facing quick start
└── CHANGELOG.md          # This file (agent reference)
```

---

## Current Configuration State

### Dock Layout (left → right)
```
Finder → Calendar → Things 3 → Messages → Arc → Stremio → Photos → Cursor → Terminal → Warp → Screen Sharing → Settings → [Trash]
```
- Recent apps: **disabled**
- Configured via: `dockutil` in `.macos`
- To modify: Edit `DOCK_APPS` array in `.macos`

### Brewfile Categories
| Category | Packages |
|----------|----------|
| CLI Core | coreutils, findutils, gnu-sed, gawk, grep, wget, curl, openssh |
| Modern CLI | bat, eza, fd, ripgrep, fzf, zoxide, htop, btop, tldr, dust, duf, procs |
| Dev Tools | git, git-lfs, git-delta, gh, jq, yq, httpie, tmux, neovim, shellcheck |
| Dock Mgmt | dockutil |
| Display Mgmt | nightlight (Night Shift CLI) |
| Networking | nmap, mtr, iperf3, rsync, ssh-copy-id, mas |
| Version Mgrs | pyenv, nvm, rbenv, go, rustup-init |
| Shell | zsh-syntax-highlighting, zsh-autosuggestions, zsh-completions, starship |
| Fonts | JetBrains Mono, Fira Code (+ Nerd Font variants) |
| Apps | Arc, Chrome, Cursor, VS Code, Warp, Raycast, 1Password, Stremio, VLC, Keka, qBittorrent |
| Cloud | Synology Drive, Google Drive |
| AI CLIs | gemini-cli, codex, claude-code |
| App Store | Things 3, Hand Mirror |

### macOS Preferences (`.macos`)
- **Identity:** Computer name from `$COMPUTER_NAME` env var
- **Remote:** SSH (user-restricted), Screen Sharing, Remote Management
- **Power:** Never sleep, wake on LAN, auto-restart on power failure
- **UI:** Dark mode, multicolor accent, natural scrolling
- **Desktop:** Widgets hidden (both standard and Stage Manager)
- **Dock:** Bottom, 48px, magnification 80px, auto-hide, no recents
- **Hot Corners:** TL=Launchpad, TR=Mission Control, BL=Screen Saver, BR=Desktop
- **Finder:** Column view, Downloads default, no desktop icons
- **Keyboard:** Fast repeat, Caps Lock→Command (hidutil LaunchDaemon)
- **Shortcut:** Option+L = Lock Screen

### What Cannot Be Automated
| Item | Reason |
|------|--------|
| Apple ID sign-in | Security requirement |
| App Store sign-in | Linked to Apple ID |
| Display "More Space" | Requires GUI or displayplacer |
| Finder sidebar | Binary plist format |
| App sign-ins | OAuth/password required |
| Printers/Bluetooth | Device-specific |

---

## [Unreleased]

### Added
- Hide desktop widgets setting in `.macos` (StandardHideWidgets)
- Hide Stage Manager widgets setting in `.macos` (StageManagerHideWidgets)
- `nightlight` CLI for Night Shift control (via `smudge/smudge` tap in Brewfile)
- Automated Night Shift configuration in `.macos`: Sunset to Sunrise schedule, 70% warmth

### Changed
- Night Shift is now automated (removed from manual steps in `.macos` output)

---

## [2024-12-06] - Automated Dock Layout

### Added
- `dockutil` to Brewfile for Dock management CLI
- `stremio` to Brewfile (media center app)
- Dock layout configuration in `.macos` with 12 apps in specific order
- Idempotent dock script (removes before adding to prevent duplicates)

### Changed
- `.macos` now includes `DOCK_APPS` array for customizable dock layout
- Dock configuration runs as part of `.macos` (not separate script)

### Technical Details
```bash
# How dock layout works in .macos:
dockutil --remove all --no-restart
for app in "${DOCK_APPS[@]}"; do
    dockutil --remove "$app_name" --no-restart  # Prevent duplicates
    dockutil --add "$app" --no-restart
done
# Dock restarts once at end of .macos
```

---

## [2024-12-XX] - Comprehensive Audit & Improvements

### Fixed (Brewfile)
- Removed deprecated taps: `homebrew/bundle`, `homebrew/cask-fonts`
- Removed `unrar` (license issues) → replaced with `unar`
- Added missing `git-delta` (required by .gitconfig)
- Commented out `yarn` (use corepack instead)

### Fixed (Shell Performance)
- Lazy loading for pyenv, nvm, rbenv (shell startup: 400-600ms → <50ms)
- Updated fzf initialization to use `fzf --zsh`
- Increased history: 10,000 → 50,000 entries
- Added history options: HIST_IGNORE_SPACE, EXTENDED_HISTORY, HIST_VERIFY

### Fixed (start.sh)
- Made fully idempotent (safe to re-run)
- Changed shebang from bash to zsh
- Added macOS platform check
- Improved Homebrew detection (Apple Silicon + Intel)
- SSH/HTTPS fallback for git clone
- Smarter symlink function with timestamped backups
- Interactive prompt before running .macos

### Fixed (ssh.sh)
- Correct permissions: ~/.ssh (700), private key (600), public key (644)
- Better SSH config with GitHub host
- Accepts email as CLI argument

### Fixed (Mackup)
- Removed machine-specific paths from Google Drive config
- Commented out Synology Drive Application Support (large databases)

### Fixed (Aliases)
- Changed `find→fd` to `fnd` alias (fd has different syntax)
- Changed `grep→rg` to `rgrep` alias (rg has different syntax)
- Added `reload` alias using `exec zsh`

### Fixed (Git)
- Added git-delta with Dracula theme
- Added rerere (remembers merge resolutions)
- Added branch.sort by recent commit
- Added SSH URL rewrite for GitHub
- Added GPG signing placeholders

### Fixed (macOS)
- Graceful error handling for remote access commands
- Warnings about Sequoia/Sonoma limitations
- Documented hot corner modifier values

---

## [2024-12-XX] - Initial Creation

### Added
- Complete dotfiles system for Mac Mini home server
- Bootstrap script (`start.sh`) for single-command setup
- Comprehensive macOS preferences (`.macos`)
- Brewfile with 70+ CLI tools and apps
- Oh My Zsh configuration with lazy-loaded version managers
- SSH key generation script
- Mackup configuration for app preference backup
- Custom Mackup configs for Synology Drive and Google Drive

### Architecture Decisions
1. **qBittorrent over uTorrent** — uTorrent has adware
2. **Keka over The Unarchiver** — More formats, power user preferred
3. **Version managers over direct installs** — Avoid system conflicts
4. **hidutil for Caps Lock remap** — LaunchDaemon for persistence
5. **dockutil for Dock layout** — CLI automation for dock
6. **VS Code/Cursor use built-in sync** — Not in Mackup to avoid conflicts
7. **Lazy-load version managers** — Fast shell startup

---

## Agent Instructions

### Before Making Changes
1. Read this CHANGELOG.md to understand current state
2. Check README.md for user-facing documentation
3. Verify which files will be affected

### After Making Changes
1. Update this CHANGELOG.md with your changes
2. Update README.md if user-facing behavior changed
3. Commit with conventional commit format:
   - `feat:` new feature
   - `fix:` bug fix
   - `docs:` documentation only
   - `refactor:` code change without feature/fix

### Key Files to Understand
| File | Purpose | Modify When |
|------|---------|-------------|
| `start.sh` | Bootstrap orchestration | Changing install order or adding setup steps |
| `.macos` | System preferences + Dock | Changing macOS settings or dock layout |
| `Brewfile` | Package list | Adding/removing apps or CLI tools |
| `.zshrc` | Shell config | Changing shell behavior or plugins |
| `aliases.zsh` | Shell aliases | Adding/modifying command shortcuts |
| `path.zsh` | PATH setup | Adding new tool paths |

### Testing Changes
```bash
# Syntax check shell scripts
bash -n start.sh && bash -n .macos && echo "OK"

# Test dock configuration
source .macos  # Will reconfigure dock

# Re-run bootstrap (safe, idempotent)
./start.sh
```

