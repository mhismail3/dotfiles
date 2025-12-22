# moose's dotfiles

Bootstrap a fresh macOS installation with a single command.

## Quick Start (New Mac)

```bash
curl -fsSL https://raw.githubusercontent.com/mhismail3/dotfiles/main/start.sh | zsh
```

> **Note:** A popup will appear asking to install Xcode Command Line Tools. Click **Install** and wait for it to complete. The script will continue automatically.

## Execution Modes

The bootstrap script supports multiple execution modes:

```bash
# Interactive (default) - prompts before each step
./start.sh

# Run everything - minimal prompts, uses safe defaults
./start.sh --all

# Run everything with no prompts (CI/automation mode)
./start.sh --all --force

# Run only a specific module
./start.sh --module cursor

# Preview what would happen (no changes made)
./start.sh --dry-run --all

# List available modules
./start.sh --list

# Show help
./start.sh --help
```

### Available Modules

| Module | Description |
|--------|-------------|
| `core` | Xcode CLI Tools, Homebrew, Oh My Zsh |
| `packages` | Install Brewfile packages |
| `symlinks` | Create dotfile symlinks |
| `ssh` | SSH key setup |
| `shell` | Set Zsh as default shell |
| `version-managers` | Set up nvm, Node, Rust, etc. |
| `cursor` | Cursor IDE configuration |
| `claude` | Claude Code CLI configuration |
| `superwhisper` | SuperWhisper configuration |
| `raycast` | Raycast configuration |
| `macos` | macOS system preferences |

## What Gets Installed

### CLI Tools
- GNU coreutils, findutils, sed, awk, grep
- Modern replacements: `bat`, `eza`, `fd`, `ripgrep`, `fzf`, `zoxide`
- Dev tools: `git`, `gh`, `neovim`, `tmux`, `jq`, `httpie`
- Version managers: `pyenv`, `nvm`, `rbenv`, `rustup`

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
7. Configures app settings (Cursor, SuperWhisper, Raycast)
8. Sets up SSH key (optional, asks first)
9. Applies macOS preferences (optional, asks first)
   - Includes automated Dock layout configuration
   - Configures Finder defaults and sidebar favorites

## Manual Steps After Setup

The script will print these, but here's a summary:

1. **Apple ID** — Sign in if not done during macOS setup
2. **Display** — System Settings → Displays → "More Space"
3. **App Sign-ins** — 1Password, Arc, Synology Drive, Google Drive, VS Code/Cursor
4. **SSH Key** — Run `~/.dotfiles/setup/ssh.sh` then add to GitHub
5. **Mackup** — Run `mackup restore` to restore app preferences

## File Structure

```
~/.dotfiles/
├── start.sh              # Bootstrap script (run this first)
├── Brewfile              # Homebrew packages
├── README.md
│
├── setup/                # Modular setup scripts (run individually)
│   ├── _lib.sh           # Shared helper functions
│   ├── cursor.sh         # Cursor IDE config
│   ├── claude.sh         # Claude Code CLI config
│   ├── superwhisper.sh   # SuperWhisper modes/settings
│   ├── raycast.sh        # Raycast config import
│   ├── ssh.sh            # SSH key generation
│   └── screenshots.sh    # Screenshot location
│
├── zsh/                  # Shell configuration
│   ├── .zshrc
│   ├── aliases.zsh
│   └── path.zsh
│
├── git/                  # Git configuration
│   ├── .gitconfig
│   └── .gitignore_global
│
├── cursor/               # Cursor IDE settings
│   ├── settings.json
│   ├── keybindings.json
│   ├── mcp.json
│   └── extensions.json
│
├── claude/               # Claude Code CLI settings
│   ├── settings.json     # Permissions, model preferences
│   ├── commands/         # Custom slash commands
│   └── history.jsonl     # Conversation history
│
├── superwhisper/         # SuperWhisper config
│   ├── modes/
│   └── settings/
│
├── raycast/              # Raycast config
│   └── Raycast.rayconfig
│
├── macos/                # macOS preferences
│   ├── .macos
│   ├── finder.sh
│   └── bin/
│
├── mackup/               # Mackup backup config
│   ├── .mackup.cfg
│   └── .mackup/
│
└── tmux/                 # Tmux configuration
    └── .tmux.conf
```

## Commands Reference

```bash
# Re-run bootstrap
~/.dotfiles/start.sh                    # Interactive mode
~/.dotfiles/start.sh --all              # Run everything
~/.dotfiles/start.sh --all --force      # No prompts (automation)
~/.dotfiles/start.sh --dry-run --all    # Preview changes

# Individual setup scripts (all support --force and --dry-run)
~/.dotfiles/setup/cursor.sh             # Re-link Cursor settings
~/.dotfiles/setup/claude.sh             # Re-link Claude Code config
~/.dotfiles/setup/superwhisper.sh       # Re-link SuperWhisper config
~/.dotfiles/setup/raycast.sh            # Import Raycast settings
~/.dotfiles/setup/ssh.sh                # Generate SSH key
~/.dotfiles/setup/screenshots.sh        # Set screenshot location

# Run a specific module only
~/.dotfiles/start.sh --module symlinks
~/.dotfiles/start.sh --module cursor
~/.dotfiles/start.sh --module macos

# Apply macOS preferences only
source ~/.dotfiles/macos/.macos

# Update Brewfile from current installs
brew bundle dump --file=~/.dotfiles/Brewfile --force

# Backup app preferences
mackup backup

# Restore app preferences (new Mac)
mackup restore
```

## Idempotent & Safe

All scripts are designed to be:

- **Idempotent** — Run multiple times safely; already-done steps are skipped
- **Non-destructive** — Existing files are backed up before symlinking
- **Interruptible** — Ctrl+C at any time; resume by running again
- **Transparent** — Use `--dry-run` to preview all changes

## Dock Layout

The Dock is automatically configured with these apps (left to right):

> Finder → Calendar → Things 3 → Messages → Safari → Chrome → Arc → Stremio → Photos → Obsidian → ChatGPT → Claude → Cursor → Ghostty → Telegram → Screen Sharing → iPhone Mirroring → Settings → [Trash]

- Recent apps: disabled
- To customize, edit the `DOCK_APPS` array in `macos/.macos`

## Customization

Fork this repo and edit:

- `Brewfile` — Add/remove packages and apps
- `macos/.macos` — Adjust system preferences and Dock layout
- `zsh/aliases.zsh` — Add your own aliases
- `git/.gitconfig` — Change name/email

## Credits

Inspired by:
- [Dries Vints](https://github.com/driesvints/dotfiles)
- [Mathias Bynens](https://github.com/mathiasbynens/dotfiles)
