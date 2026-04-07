# dotfiles

Setup for a **personal MacBook** — daily driver for development, AI, and general use.

## Quick Start

```bash
git clone https://github.com/mhismail3/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./setup.sh

# Re-run safely (skips what's done):
./setup.sh

# Force re-apply everything:
./setup.sh --reset
```

## Architecture

**Single-script design.** `setup.sh` contains all logic as functions. Brewfile and config files live in their own directories.

**Symlink-based.** Config files are symlinked — editing this repo takes effect immediately.

**Two modes:**
- `./setup.sh` — idempotent, skips completed steps
- `./setup.sh --reset` — force re-applies everything (never destroys SSH keys)

## What's Included

| File | Purpose |
|---|---|
| `setup.sh` | Main bootstrap script (12 steps, interactive) |
| `Brewfile` | All Homebrew packages and casks |
| `zsh/.zshrc` | Shell config (Homebrew, languages, plugins, starship) |
| `zsh/path.zsh` | PATH: GNU tools override BSD, user bins |
| `zsh/aliases.zsh` | Aliases + guardrails (pip warns→uv, npm warns on -g) |
| `git/.gitconfig` | HTTPS-first auth (via gh) |
| `git/.gitignore_global` | Global gitignore |
| `tmux/.tmux.conf` | tmux: mouse, splits, Alt+arrow nav |
| `starship/starship.toml` | Minimal prompt: directory + git branch |
| `ghostty/config` | Ghostty terminal config |
| `macos/.macos` | macOS system preferences |
| `claude/` | Claude Code: CLAUDE.md, settings, skills, LEDGER |

## macOS Preferences (.macos)

| Category | What it sets |
|---|---|
| SSH | Remote Login enabled |
| UI | Dark mode, sounds on, natural scrolling, tabs always, restore windows |
| Dock | Auto-hide, size 80, magnification, managed app layout via dockutil |
| Siri | Disabled |
| Menu Bar | Spotlight icon hidden, 24h clock with date + seconds |
| Spotlight | Cmd+Space freed for Raycast, limited categories |
| Display | Night Shift off, auto-brightness off |
| Finder | Show hidden files, extensions, path bar, column view, folders first |
| Keyboard | Fast repeat (2/15), no press-and-hold, full keyboard nav |
| Trackpad | Tap to click, three-finger drag |
| Mission Control | Don't rearrange spaces, group by app, hot corners |
| Screen Time | Disabled |
| Privacy | Analytics off, ad tracking off |
| Security | Password on wake |
| Updates | Download only, no auto-install |
| Caps Lock | Remapped to Command |

## Language Environment

System stays clean — every runtime is isolated:
- **Python**: `uv` (project venvs). `pip` warns to use uv.
- **Node**: `nvm`. `npm -g` warns about pollution.
- **Ruby**: `rbenv`
- **Rust**: `rustup` → `~/.cargo/`
- **Bun**: project-local

## Other Branches

| Branch | Purpose |
|---|---|
| `main` | Personal MacBook (this branch) |
| `server-laptop` | MacBook as always-on server (lid-closed, AC/battery profiles) |
| `server-desktop` | Mac Mini/Studio headless server |

## Updating

```bash
cd ~/.dotfiles && git pull        # Symlinked files take effect immediately
source ~/.dotfiles/macos/.macos   # Re-apply macOS prefs
brew bundle --file=~/.dotfiles/Brewfile  # Re-sync packages
./setup.sh --reset                # Nuclear option: re-apply everything
```
