# Dotfiles Setup Script Analysis

## General Overview

Your `start.sh` is a comprehensive macOS bootstrap script (~1000 lines) that orchestrates 12 modules. It supports three modes: interactive (prompts for each step), `--all` (runs everything), and `--module NAME` (single module). Here's the complete breakdown:

---

## Module-by-Module Analysis

### 1. **CORE** (Lines 435-530) - **ESSENTIAL**
**What it does:**
- Installs **Xcode Command Line Tools** - the foundation for all dev tools
- Installs **Homebrew** - package manager for everything else
- Clones your **dotfiles repo** to `~/.dotfiles`
- Installs **Oh My Zsh** - zsh framework with plugins/themes

**Necessity:** 100% essential. Without this, nothing else works.

---

### 2. **PACKAGES** (Lines 536-596) - **ESSENTIAL (but Brewfile can be trimmed)**
**What it does:**
- Runs `brew bundle --file=Brewfile` to install ~90 packages
- Fixes Homebrew directory permissions for zsh completions
- Requests sudo upfront for casks that need it

**Your Brewfile contains:**
| Category | Packages | Essential? |
|----------|----------|------------|
| GNU Core Utils | coreutils, findutils, gnu-sed, gawk, grep | Nice-to-have |
| Modern CLI | bat, eza, fd, ripgrep, zoxide, fzf | Highly useful |
| Git tools | git, git-lfs, git-delta, gh | Essential |
| Languages | pyenv, nvm, rbenv, go, rustup-init | Depends on work |
| Zsh plugins | syntax-highlighting, autosuggestions, completions | Nice-to-have |
| Fonts | JetBrains Mono, Fira Code | Cosmetic |
| Productivity | Raycast, 1Password, Arc, superwhisper, Claude | Personal pref |
| Dev tools | Cursor, VS Code, Warp, Ghostty | Personal pref |
| AI CLIs | claude-code, gemini-cli, llm, opencode, codex | Personal pref |
| Cloud storage | Synology Drive, Google Drive | Personal pref |
| Media | Stremio, VLC, Telegram, qbittorrent | Nice-to-have |
| Privacy | Tailscale, PIA VPN | Personal pref |
| Mac App Store | Things 3, Hand Mirror, Folder Peek | Personal pref |

**Recommendation:** The Brewfile is the most "bloated" part. Trim to what you actually use.

---

### 3. **SYMLINKS** (Lines 602-619) - **ESSENTIAL**
**What it does:**
Creates symlinks for:
- `~/.zshrc` → your zsh config
- `~/.gitconfig` → your git config
- `~/.gitignore_global` → global gitignore
- `~/.mackup.cfg` and `~/.mackup/` → Mackup app preference sync
- `~/.tmux.conf` → tmux config

**Necessity:** Essential for dotfiles to work. Without symlinks, you'd just have files sitting in `~/.dotfiles` doing nothing.

---

### 4. **SSH** (Lines 625-714) - **ESSENTIAL**
**What it does:**
- Generates ed25519 SSH key if none exists
- Adds key to ssh-agent with macOS Keychain integration
- Creates `~/.ssh/config` with GitHub host config
- Copies public key to clipboard for adding to GitHub

**Necessity:** Essential for GitHub/GitLab SSH access. The script handles this well - skip if you already have keys.

---

### 5. **SHELL** (Lines 720-748) - **SEMI-ESSENTIAL**
**What it does:**
- Sets Zsh as default shell (if not already)
- Creates `~/Downloads/projects` and `~/.ssh` directories

**Necessity:** Minor. Zsh is already default on macOS since Catalina. The directory creation is trivial.

---

### 6. **VERSION-MANAGERS** (Lines 754-816) - **CONDITIONAL**
**What it does:**
- Creates `~/.nvm` directory
- Installs Node LTS via nvm
- Enables corepack (for yarn/pnpm)
- Installs Rust toolchain via rustup-init
- Sets up Git LFS

**Necessity:** Only needed if you work with Node/Rust. If you don't, this is wasted time.

---

### 7. **CURSOR** (Lines 822-828 → `setup/cursor.sh`) - **CONDITIONAL**
**What it does:**
- Symlinks `settings.json` to `~/Library/Application Support/Cursor/User/`
- Symlinks `keybindings.json` to same location
- Symlinks `mcp.json` to `~/.cursor/`
- Installs extensions from `extensions.txt`

**Necessity:** Only if you use Cursor IDE.

---

### 8. **CLAUDE** (Lines 834-840 → `setup/claude.sh`) - **CONDITIONAL**
**What it does:**
- Symlinks `CLAUDE.md`, `settings.json`, `commands/`, `skills/`, `plans/`, `agents/`, `LEDGER.jsonl`, `ledger-context/` to `~/.claude/`
- Syncs plugins from manifest (reinstalls missing plugins)

**Necessity:** Only if you use Claude Code CLI.

---

### 9. **SUPERWHISPER** (Lines 846-852 → `setup/superwhisper.sh`) - **CONDITIONAL**
**What it does:**
- Detects SuperWhisper's data folder location
- Symlinks `modes/` and `settings/` directories
- Leaves recordings/models local

**Necessity:** Only if you use SuperWhisper (AI transcription app).

---

### 10. **RAYCAST** (Lines 858-864 → `setup/raycast.sh`) - **CONDITIONAL**
**What it does:**
- Opens Raycast's import settings dialog
- Reveals your `.rayconfig` file in Finder
- You manually drag to import (Raycast doesn't support symlinks)

**Necessity:** Only if you use Raycast. And it's semi-manual anyway.

---

### 11. **ARC-EXTENSIONS** (Lines 870-892 → `setup/arc-extensions.sh`) - **CONDITIONAL**
**What it does:**
- Creates JSON files in Arc's External Extensions folder
- Configures: 1Password, Raindrop.io extensions
- Extensions auto-install on next Arc launch

**Necessity:** Only if you use Arc browser AND want these specific extensions.

---

### 12. **MACOS** (Lines 898-924 → `macos/.macos`) - **VERY OPTIONAL**
**What it does (797 lines!):**
- Sets computer name (ComputerName, HostName, LocalHostName)
- Enables SSH, Screen Sharing, Remote Management
- Configures power management (never sleep, wake on LAN, auto-restart)
- Sets Dark mode, scrolling behavior, UI preferences
- Configures Dock (size, autohide, magnification, hot corners, layout via dockutil)
- Configures Mission Control, Spaces, Window Tiling
- Disables Stage Manager
- Finder preferences (show hidden files, path bar, column view, etc.)
- Keyboard settings (fast repeat, no press-and-hold)
- Screenshot settings
- Lock screen (require password immediately)
- Night Shift (sunset-to-sunrise, 70% warmth)
- Menu bar clock/battery
- Disables Spotlight shortcuts (Cmd+Space freed for Raycast)
- Caps Lock → Command remap via hidutil LaunchDaemon
- Sets Arc as default browser
- Configures Synology Drive Client preferences

**Necessity:** Highly personal. Most people don't need 80% of this. The server-specific stuff (never sleep, remote access) only matters for home servers.

---

## What's TRULY Essential for a Fresh Mac

**Minimum viable setup:**
```
1. core        → Xcode CLI, Homebrew, dotfiles clone, Oh My Zsh
2. symlinks    → Link your configs
3. ssh         → Generate SSH key for GitHub
```

**Add based on your workflow:**
```
4. packages    → But trim Brewfile to what you actually use
5. version-managers → Only if you do Node/Rust development
6. cursor/claude/superwhisper/raycast → Only if you use these apps
```

**Skip unless you're setting up a home server:**
```
- macos module → Most of this is cosmetic or server-specific
```

---

## Specific Redundancies and Bloat

### In `start.sh`:
1. **Shell module** (Lines 720-748) - Almost useless. Zsh is default, creating 2 directories isn't worth a module.

2. **Helper functions duplicated** - `symlink()` is defined in both `start.sh` (Lines 269-321) AND `_lib.sh`. The `_lib.sh` version is more robust.

3. **Error handling** - Multiple try/catch patterns that could be consolidated.

### In Brewfile:
1. **GNU utils overlap** - You install `coreutils`, `findutils`, `gnu-sed`, `gawk` but then also `bat`, `eza`, `fd`, `ripgrep`, `sd` which are modern replacements. Pick one approach.

2. **Multiple terminals** - Warp AND Ghostty AND the default Terminal.

3. **AI CLI tools** - claude-code, gemini-cli, llm, opencode, codex - do you use all 5?

4. **Mac App Store** - `mas` + 3 apps. Worth the complexity?

### In `.macos`:
1. **750+ lines** for preferences most people set once via GUI.
2. **Server-specific settings** mixed with general preferences.
3. **dockutil timeout handling** (Lines 218-258) - 40 lines to prevent hangs in a dock utility.

---

## Recommendations to Pare Down

### Tier 1: Keep as-is
- `core` module
- `symlinks` module
- `ssh` module
- Your `~/.zshrc`, `~/.gitconfig`, etc.

### Tier 2: Simplify
- **Brewfile**: Split into `Brewfile.essential` and `Brewfile.extras`
- **Shell module**: Merge into `core` or delete entirely
- **App config scripts**: Keep only for apps you actively use

### Tier 3: Consider removing
- **macos module**: Either make it opt-in only, or split into:
  - `macos-server.sh` (power, remote access)
  - `macos-preferences.sh` (UI, Finder, etc.)
- **arc-extensions.sh**: Just install extensions manually
- **chrome-extensions.sh**: Same

### Tier 4: Questions to answer
- Do you need all 5 AI CLI tools?
- Do you need both Warp and Ghostty?
- Do you actually use `mackup`?
- Is the Dock layout automation worth 60 lines of timeout-guarded code?

---

## Summary: Essential vs Nice-to-Have

| Component | Essential | Nice-to-Have | Skip |
|-----------|-----------|--------------|------|
| Xcode CLI Tools | ✓ | | |
| Homebrew | ✓ | | |
| Oh My Zsh | | ✓ | |
| Dotfiles clone | ✓ | | |
| Symlinks | ✓ | | |
| SSH keys | ✓ | | |
| Brewfile (trimmed) | ✓ | | |
| Version managers | | ✓ | |
| Cursor config | | ✓ | |
| Claude config | | ✓ | |
| SuperWhisper config | | | Maybe |
| Raycast config | | ✓ | |
| Arc extensions | | | ✓ |
| macOS preferences | | | Most of it |

---

## Brewfile Deep Audit

### Section 1: CLI Tools - Core Utilities
| Package | What it does | Verdict | Notes |
|---------|--------------|---------|-------|
| `coreutils` | GNU ls, cp, mv, etc. (prefixed with 'g') | **REMOVE** | You have eza, bat, etc. that replace these |
| `findutils` | GNU find, xargs, locate | **REMOVE** | You have fd which is better |
| `gnu-sed` | GNU sed | **REMOVE** | You have sd which is better |
| `gawk` | GNU awk | **CONDITIONAL** | Only if you write awk scripts |
| `grep` | GNU grep | **REMOVE** | You have ripgrep which is 10x faster |
| `wget` | Download files | **KEEP** | Useful for scripts |
| `curl` | Transfer data | **KEEP** | Essential, newer than system |
| `openssh` | SSH client | **CONDITIONAL** | System SSH is usually fine |

**Recommendation:** Remove coreutils, findutils, gnu-sed, grep. You installed modern replacements anyway.

---

### Section 2: CLI Tools - Modern Replacements
| Package | What it does | Verdict | Notes |
|---------|--------------|---------|-------|
| `bat` | Better cat with syntax highlighting | **KEEP** | Very useful |
| `eza` | Better ls | **KEEP** | Very useful |
| `fd` | Better find | **KEEP** | Very useful |
| `ripgrep` | Better grep (rg) | **KEEP** | Essential for Claude Code |
| `sd` | Better sed for find/replace | **KEEP** | Nice for quick edits |
| `zoxide` | Better cd with frecency | **KEEP** | Very useful |
| `fzf` | Fuzzy finder | **KEEP** | Powers many integrations |
| `htop` | Better top | **REMOVE** | You have btop |
| `btop` | Even better top with graphs | **KEEP** | Pick one (btop is better) |
| `ncdu` | Disk usage analyzer | **KEEP** | Useful occasionally |
| `dust` | Better du | **REMOVE** | ncdu is enough |
| `duf` | Better df | **REMOVE** | df works fine |
| `procs` | Better ps | **REMOVE** | htop/btop shows this |
| `tldr` | Simplified man pages | **KEEP** | Very useful |

**Recommendation:** Remove htop (btop is better), dust, duf, procs (all redundant).

---

### Section 3: CLI Tools - Development & Productivity
| Package | What it does | Verdict | Notes |
|---------|--------------|---------|-------|
| `git` | Version control | **KEEP** | Essential |
| `git-lfs` | Large file storage | **CONDITIONAL** | Only if working with large binary files |
| `git-delta` | Better git diff pager | **KEEP** | Makes diffs readable |
| `gh` | GitHub CLI | **KEEP** | Very useful |
| `jq` | JSON processor | **KEEP** | Essential for scripts |
| `yq` | YAML processor | **KEEP** | Useful for k8s/configs |
| `httpie` | Better curl for APIs | **CONDITIONAL** | Nice but curl works |
| `tree` | Directory tree | **KEEP** | Simple, useful |
| `watch` | Execute command periodically | **KEEP** | Useful for monitoring |
| `tmux` | Terminal multiplexer | **CONDITIONAL** | Only if you use it |
| `neovim` | Modern vim | **CONDITIONAL** | Only if you use it |
| `shellcheck` | Shell script linter | **KEEP** | Essential for bash |
| `shfmt` | Shell script formatter | **KEEP** | Pairs with shellcheck |
| `exiftool` | Image metadata | **CONDITIONAL** | Only for photo work |

---

### Section 4: CLI Tools - Dock/Browser/Display Management
| Package | What it does | Verdict | Notes |
|---------|--------------|---------|-------|
| `dockutil` | CLI to manage Dock items | **CONDITIONAL** | Only if you want automated Dock layout |
| `defaultbrowser` | CLI to set default browser | **REMOVE** | Set once manually |
| `nightlight` (tap) | CLI for Night Shift | **REMOVE** | Set once in System Settings |

---

### Section 5: CLI Tools - Networking & System
| Package | What it does | Verdict | Notes |
|---------|--------------|---------|-------|
| `nmap` | Network scanner | **CONDITIONAL** | Only for network diagnostics |
| `mtr` | Traceroute + ping | **CONDITIONAL** | Nice for debugging |
| `iperf3` | Network performance | **CONDITIONAL** | Rarely needed |
| `rsync` | File sync | **KEEP** | Better than system rsync |
| `ssh-copy-id` | Copy SSH keys to servers | **KEEP** | Useful |
| `mas` | Mac App Store CLI | **CONDITIONAL** | Only if you want MAS apps via script |

---

### Section 6: CLI Tools - Port Management
| Package | What it does | Verdict | Notes |
|---------|--------------|---------|-------|
| `portkiller` (cask) | Kill processes by port | **REMOVE** | `lsof -i :PORT` + kill works fine |

---

### Section 7: CLI Tools - Compression
| Package | What it does | Verdict | Notes |
|---------|--------------|---------|-------|
| `p7zip` | 7-Zip | **KEEP** | Useful for .7z files |
| `xz` | XZ compression | **KEEP** | Common format |
| `zstd` | Zstandard compression | **CONDITIONAL** | Newer format, less common |
| `pigz` | Parallel gzip | **CONDITIONAL** | Only for large files |
| `unar` | Universal archive extractor | **KEEP** | Better than unrar |

---

### Section 8: Languages & Version Managers
| Package | What it does | Verdict | Notes |
|---------|--------------|---------|-------|
| `pyenv` | Python version manager | **CONDITIONAL** | Only if doing Python |
| `pyenv-virtualenv` | Virtualenv for pyenv | **CONDITIONAL** | Goes with pyenv |
| `pipx` | Isolated Python apps | **KEEP** | Useful for Python CLIs |
| `uv` | Fast Python package manager | **KEEP** | Modern, fast |
| `nvm` | Node version manager | **CONDITIONAL** | Only if doing JavaScript |
| `rbenv` | Ruby version manager | **CONDITIONAL** | Only if doing Ruby |
| `ruby-build` | Install Ruby versions | **CONDITIONAL** | Goes with rbenv |
| `go` | Go language | **CONDITIONAL** | Only if doing Go |
| `rustup-init` | Rust toolchain installer | **CONDITIONAL** | Only if doing Rust |

**Note:** You probably don't need ALL of pyenv/nvm/rbenv/go/rust. Pick based on what you actually code in.

---

### Section 9: Shell Enhancements
| Package | What it does | Verdict | Notes |
|---------|--------------|---------|-------|
| `zsh-syntax-highlighting` | Colorize commands | **KEEP** | Very useful |
| `zsh-autosuggestions` | Fish-like suggestions | **KEEP** | Very useful |
| `zsh-completions` | Extra completions | **KEEP** | Useful |
| `starship` | Cross-shell prompt | **REMOVE** | Commented out in .zshrc anyway |

---

### Section 10: Fonts
| Package | What it does | Verdict | Notes |
|---------|--------------|---------|-------|
| `font-jetbrains-mono` | JetBrains font | **KEEP (one)** | Good programming font |
| `font-jetbrains-mono-nerd-font` | With icons | **CONDITIONAL** | Only if you use icons |
| `font-fira-code` | Fira Code font | **REMOVE** | Pick one font family |
| `font-fira-code-nerd-font` | With icons | **REMOVE** | Pick one font family |

**Recommendation:** Pick JetBrains Mono OR Fira Code, not both.

---

### Section 11: Applications - Productivity
| Package | What it does | Verdict | Notes |
|---------|--------------|---------|-------|
| `raycast` | Spotlight replacement | **KEEP** | Your launcher |
| `1password` | Password manager | **KEEP** | Essential |
| `superwhisper` | Voice-to-text | **CONDITIONAL** | Only if you use it |
| `claude` | Claude desktop app | **KEEP** | |
| `chatgpt` | ChatGPT desktop | **CONDITIONAL** | Do you use both Claude AND ChatGPT desktop? |
| `arc` | Browser | **KEEP** | Your main browser |
| `google-chrome` | Browser | **CONDITIONAL** | Only if you need Chrome specifically |
| `obsidian` | Notes | **KEEP** | If you use it |

---

### Section 12: Applications - Development
| Package | What it does | Verdict | Notes |
|---------|--------------|---------|-------|
| `cursor` | AI code editor | **KEEP** | Your main editor |
| `cursor-cli` | Cursor Agent CLI | **KEEP** | Goes with Cursor |
| `visual-studio-code` | VS Code | **REMOVE** | You have Cursor |
| `warp` | Modern terminal | **PICK ONE** | Warp or Ghostty? |
| `ghostty` | GPU terminal | **PICK ONE** | Warp or Ghostty? |
| `db-browser-for-sqlite` | SQLite browser | **CONDITIONAL** | Only if you work with SQLite |

**Recommendation:** Pick Warp OR Ghostty, not both. Remove VS Code if Cursor is your editor.

---

### Section 13: AI Coding CLIs
| Package | What it does | Verdict | Notes |
|---------|--------------|---------|-------|
| `gemini-cli` | Google Gemini CLI | **AUDIT** | Do you use this? |
| `llm` | Simon Willison's LLM CLI | **AUDIT** | Do you use this? |
| `opencode` | Open-source AI agent TUI | **AUDIT** | Do you use this? |
| `codex` (cask) | OpenAI Codex CLI | **AUDIT** | Do you use this? |
| `claude-code` (cask) | Claude Code CLI | **KEEP** | Primary tool |

**Question:** Do you actually use all 5 AI CLIs? Most people pick 1-2.

---

### Section 14: Cloud Storage
| Package | What it does | Verdict | Notes |
|---------|--------------|---------|-------|
| `synology-drive` | NAS sync | **CONDITIONAL** | Only if you have Synology NAS |
| `google-drive` | Google Drive sync | **CONDITIONAL** | Only if you use Google Drive |

---

### Section 15: Media & Utilities
| Package | What it does | Verdict | Notes |
|---------|--------------|---------|-------|
| `stremio` | Media center | **CONDITIONAL** | Personal entertainment |
| `telegram` | Messaging | **CONDITIONAL** | Personal use |
| `vlc` | Media player | **KEEP** | Standard player |
| `keka` | Archive utility | **KEEP** | Better than built-in |
| `shottr` | Screenshot tool | **CONDITIONAL** | macOS screenshots work fine |
| `qbittorrent` | Torrent client | **CONDITIONAL** | Personal use |
| `logi-options+` | Logitech customization | **CONDITIONAL** | Only if you have Logitech hardware |

---

### Section 16: Privacy & Security
| Package | What it does | Verdict | Notes |
|---------|--------------|---------|-------|
| `tailscale` | Mesh VPN | **KEEP** | Very useful |
| `private-internet-access` | VPN | **CONDITIONAL** | Personal preference |

---

### Section 17: Mac App Store
| Package | What it does | Verdict | Notes |
|---------|--------------|---------|-------|
| `mas "Things 3"` | Task manager | **CONDITIONAL** | Only if you use Things |
| `mas "Hand Mirror"` | Camera check | **REMOVE** | Very niche |
| `mas "Folder Peek"` | Menu bar folder | **REMOVE** | Very niche |

---

## Recommended Trimmed Brewfile

Here's what a minimal Brewfile might look like:

```ruby
# ESSENTIAL - Core development
brew "git"
brew "gh"
brew "jq"
brew "yq"
brew "shellcheck"
brew "shfmt"
brew "wget"
brew "curl"
brew "rsync"
brew "ssh-copy-id"

# ESSENTIAL - Modern CLI replacements
brew "bat"
brew "eza"
brew "fd"
brew "ripgrep"
brew "sd"
brew "zoxide"
brew "fzf"
brew "btop"
brew "tldr"
brew "tree"

# Shell enhancements
brew "zsh-syntax-highlighting"
brew "zsh-autosuggestions"
brew "zsh-completions"

# Archives
brew "p7zip"
brew "xz"
brew "unar"

# Fonts (pick ONE)
cask "font-jetbrains-mono-nerd-font"

# Apps - Essential
cask "raycast"
cask "1password"
cask "arc"
cask "cursor"
cask "claude-code"
cask "ghostty"  # OR warp, pick one
cask "tailscale"
cask "vlc"
cask "keka"

# Apps - If you use them
# cask "claude"
# cask "obsidian"
# cask "synology-drive"
# cask "google-drive"

# Version managers - Only languages you use
# brew "nvm"       # JavaScript
# brew "pyenv"     # Python
# brew "uv"        # Python (modern)
# brew "rbenv"     # Ruby
# brew "go"        # Go
# brew "rustup-init" # Rust
```

---

## Package Count Summary

| Category | Original | Trimmed | Removed |
|----------|----------|---------|---------|
| CLI Tools - Core | 8 | 4 | 4 (redundant GNU tools) |
| CLI Tools - Modern | 14 | 10 | 4 (htop, dust, duf, procs) |
| CLI Tools - Dev | 14 | 10 | 4 (conditional) |
| CLI Tools - Special | 6 | 0 | 6 (all conditional/removable) |
| Languages | 9 | 0-9 | Depends on what you code |
| Shell | 4 | 3 | 1 (starship unused) |
| Fonts | 4 | 1 | 3 (pick one family) |
| Apps - Productivity | 8 | 4-6 | Depends on use |
| Apps - Development | 6 | 2-3 | Pick one terminal, one editor |
| AI CLIs | 5 | 1-2 | 3-4 (audit which you use) |
| Cloud/Media/Privacy | 10 | 3-5 | Depends on use |
| Mac App Store | 3 | 0 | 3 (niche) |

**Total: ~90 packages → ~25-35 essential + your specific needs**
