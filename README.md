# moose's dotfiles

Bootstrap a fresh macOS installation with a single command.

## Quick Start (New Mac)

```bash
curl -fsSL https://raw.githubusercontent.com/mhismail3/dotfiles/main/start.sh | zsh
```

> **Note:** A popup will appear asking to install Xcode Command Line Tools. Click **Install** and wait for it to complete. The script will continue automatically.

## What Gets Installed

### CLI Tools
- GNU coreutils, findutils, sed, awk, grep
- Modern replacements: `bat`, `eza`, `fd`, `ripgrep`, `fzf`, `zoxide`
- Dev tools: `git`, `gh`, `neovim`, `tmux`, `jq`, `httpie`
- Version managers: `pyenv`, `nvm`, `rbenv`, `rustup`
- Node.js: installs latest LTS via `nvm` (with `corepack enable` for yarn/pnpm)

### Apps
- **Browsers:** Arc, Chrome
- **Editors:** Cursor, VS Code
- **Terminals:** Warp, Terminal
- **Productivity:** Raycast, 1Password, Things 3
- **Cloud:** Synology Drive, Google Drive
- **Media:** Stremio, VLC, Keka, qBittorrent
- **AI CLIs:** Gemini CLI, Codex, Claude Code

### Shell
- Zsh with Oh My Zsh
- Lazy-loaded version managers (fast shell startup)
- Modern CLI aliases

## What the Script Does

1. Installs Xcode Command Line Tools
2. Installs Homebrew
3. Clones this repo to `~/.dotfiles`
4. Installs Oh My Zsh
5. Runs `brew bundle` (installs all packages)
6. Symlinks dotfiles to home directory
7. Sets up SSH key (optional, asks first)
8. Applies macOS preferences (optional, asks first)
   - Automated Dock layout configuration
   - Finder sidebar: sets favorites (Home, Applications, Downloads, iCloud Drive), hides Recents/Shared/Computer/iCloud Drive from Locations

## Manual Steps After Setup

The script will print these, but here's a summary:

1. **Apple ID** — Sign in if not done during macOS setup
2. **Display** — System Settings → Displays → "More Space"
3. **App Sign-ins** — 1Password, Arc, Synology Drive, Google Drive, VS Code/Cursor
4. **SSH Key** — Run `~/.dotfiles/ssh.sh` then add to GitHub
5. **Mackup** — Run `mackup restore` to restore app preferences
6. **Screenshots** — After Synology Drive syncs, run `~/.dotfiles/screenshots.sh`

> **Note:** If the script warns about Full Disk Access for Finder sidebar automation, open System Settings → Privacy & Security → Full Disk Access, enable your terminal (e.g., Terminal, iTerm2, Cursor), then rerun `source ~/.dotfiles/.macos`

## File Structure

```
~/.dotfiles/
├── start.sh          # Bootstrap script (run this first)
├── ssh.sh            # SSH key generation
├── screenshots.sh    # Screenshot save location config
├── .macos            # macOS system preferences
├── .zshrc            # Zsh configuration
├── aliases.zsh       # Shell aliases
├── path.zsh          # PATH modifications
├── .gitconfig        # Git configuration
├── .gitignore_global # Global gitignore
├── .mackup.cfg       # Mackup configuration
├── .mackup/          # Custom Mackup app configs
├── Brewfile          # Homebrew packages
├── AGENTS.md         # Agent-focused change log and rationale
└── .cursorrules      # AI agent instructions
```

## Commands Reference

```bash
# Re-run bootstrap (safe to run multiple times)
~/.dotfiles/start.sh

# Generate SSH key
~/.dotfiles/ssh.sh

# Set screenshot save location (after configuring sync services)
~/.dotfiles/screenshots.sh ~/SynologyDrive/Screenshots
~/.dotfiles/screenshots.sh --show   # View current setting
~/.dotfiles/screenshots.sh --reset  # Reset to Desktop

# Apply macOS preferences only
source ~/.dotfiles/.macos

# Update Brewfile from current installs
brew bundle dump --file=~/.dotfiles/Brewfile --force

# Backup app preferences
mackup backup

# Restore app preferences (new Mac)
mackup restore
```

## Dock Layout

The Dock is automatically configured with these apps (left to right):

> Finder → Calendar → Things 3 → Messages → Arc → Stremio → Photos → Cursor → Terminal → Warp → Screen Sharing → Settings → [Trash]

- Recent apps: disabled
- To customize, edit the `DOCK_APPS` array in `.macos`

## Customization

Fork this repo and edit:

- `Brewfile` — Add/remove packages and apps
- `.macos` — Adjust system preferences and Dock layout
- `aliases.zsh` — Add your own aliases
- `.gitconfig` — Change name/email

## Credits

Inspired by:
- [Dries Vints](https://github.com/driesvints/dotfiles)
- [Mathias Bynens](https://github.com/mathiasbynens/dotfiles)

