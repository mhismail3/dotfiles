# dotfiles

Personal MacBook setup for development, AI tools, and daily use.

Canonical repo: `mhismail3/dotfiles`
Canonical branch: `main`

## Quick Start

```bash
git clone --branch main https://github.com/mhismail3/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./setup.sh
```

Re-run safely:

```bash
./setup.sh
```

Force re-apply symlinks, packages, and preferences:

```bash
./setup.sh --reset
```

## Structure

Config files live at the repo root unless a tool truly requires a directory.
`setup.sh` is the entrypoint agents and humans should use to apply the machine.

| File | Applied to | Purpose |
|---|---|---|
| `setup.sh` | run directly | Bootstrap script for packages, symlinks, runtimes, and macOS preferences |
| `Brewfile` | `brew bundle --file=~/.dotfiles/Brewfile` | Homebrew packages, casks, and Mac App Store apps |
| `.zshrc` | `~/.zshrc` | Shell config, PATH, aliases, language managers, completions, prompt |
| `.gitconfig` | `~/.gitconfig` | Global Git defaults |
| `.gitignore_global` | `~/.gitignore_global` | Global Git ignore file |
| `.tmux.conf` | `~/.tmux.conf` | tmux mouse, splits, pane navigation, indexes, scrollback |
| `starship.toml` | `~/.config/starship.toml` | Starship prompt config |
| `codex.config.toml` | `~/.codex/config.toml` | Personal Codex defaults |
| `codex.AGENTS.md` | `~/.codex/AGENTS.md` | Global personal Codex guidance |
| `.macos` | sourced by `setup.sh` | macOS system preferences |
| `AGENTS.md` | read by agents | Agent operating notes for this repo |

No Claude config folder is applied right now.

`setup.sh` also creates `~/Workspace` for projects and `~/.local/bin` for user
executables.

Codex runtime state is intentionally not tracked. Do not commit `~/.codex`
wholesale; it contains auth, logs, sessions, caches, generated app state, and
project trust history.

## Starship

Starship is the shell prompt renderer initialized by `.zshrc`. This repo uses it
for a small prompt that shows the current directory, Git branch/status, and a
green or red prompt character.

## Agent Workflow

Use `./setup.sh` for real application. Use syntax checks for validation before
running anything that changes the machine:

```bash
zsh -n setup.sh
zsh -n .zshrc
bash -n .macos
zsh -n .macos
git config --file .gitconfig --list
```

Do not source `.macos` unless the user explicitly wants macOS preferences applied;
it changes system settings and restarts affected Apple services.

## macOS Preferences

| Category | What it sets |
|---|---|
| SSH | Remote Login enabled |
| UI | Dark mode, sounds on, natural scrolling, tabs always, restore windows |
| Dock | Auto-hide, size, magnification, managed app layout via dockutil |
| Siri | Disabled |
| Menu Bar | Spotlight icon hidden, 24h clock with date and seconds |
| Spotlight | Cmd+Space freed for Raycast, limited categories |
| Display | Night Shift off, auto-brightness off |
| Finder | Hidden files, extensions, path bar, column view, folders first |
| Keyboard | Fast repeat, no press-and-hold, full keyboard nav |
| Trackpad | Tap to click, three-finger drag |
| Mission Control | Stable spaces, group by app, hot corners |
| Screen Time | Disabled |
| Privacy | Analytics off, ad tracking off |
| Security | Password on wake |
| Updates | Download only, no auto-install |
| Caps Lock | Remapped to Command |

## Language Environment

System installs stay clean. Runtime managers are used instead:

| Runtime | Tool |
|---|---|
| Python | `uv` |
| Node | `nvm` |
| Ruby | `rbenv` |
| Rust | `rustup` |
| Bun | project-local Bun |

## Updating

```bash
cd ~/.dotfiles && git pull --rebase origin main
brew bundle --file=~/.dotfiles/Brewfile
./setup.sh --reset
```
