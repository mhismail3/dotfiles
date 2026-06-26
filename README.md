# dotfiles

Personal MacBook setup for development, AI tools, and daily use.

Canonical repo: `mhismail3/dotfiles`
Canonical branch: `main`

## Quick Start

```bash
mkdir -p ~/Workspace
git clone --branch main https://github.com/mhismail3/dotfiles.git ~/Workspace/dotfiles
cd ~/Workspace/dotfiles
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
| `Brewfile` | `brew bundle --file=~/Workspace/dotfiles/Brewfile` | Homebrew packages, casks, and Mac App Store apps |
| `.zshrc` | `~/.zshrc` | Shell config, PATH, aliases, language managers, completions, prompt |
| `.gitconfig` | `~/.gitconfig` | Global Git defaults |
| `.gitignore_global` | `~/.gitignore_global` | Global Git ignore file |
| `.tmux.conf` | `~/.tmux.conf` | tmux mouse, splits, pane navigation, indexes, scrollback |
| `starship.toml` | `~/.config/starship.toml` | Starship prompt config |
| `codex.config.toml` | reference baseline | Personal Codex defaults; not symlinked over live app/plugin state |
| `codex.AGENTS.md` | `~/.codex/AGENTS.md` | Global personal Codex guidance |
| `.macos` | sourced by `setup.sh` | macOS system preferences |
| `AGENTS.md` | read by agents | Agent operating notes for this repo |

No Claude config folder is applied right now.

`~/Workspace/dotfiles` is the canonical local checkout. `setup.sh` also keeps
`~/.dotfiles` as a compatibility symlink for older commands and existing config
links, then creates `~/Workspace` for projects and `~/.local/bin` for user
executables.

Codex runtime state is intentionally not tracked. Do not commit `~/.codex`
wholesale; it contains auth, logs, sessions, caches, generated app state,
plugin/app wiring, MCP runtime paths, and project trust history. On fresh Codex
app installs, keep the live `~/.codex/config.toml` unless intentionally merging
the durable defaults from `codex.config.toml`.

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
brew bundle check --file=Brewfile
python3.14 -c 'import pathlib,tomllib; tomllib.loads(pathlib.Path("codex.config.toml").read_text())'
```

Do not source `.macos` unless the user explicitly wants macOS preferences applied;
it changes system settings and restarts affected Apple services.

Run setup from a visible Terminal when Homebrew, sudo, SSH key generation, GitHub
auth, or macOS preferences may prompt for passwords or browser approval. Hidden
agent terminals are fine for validation and repair commands, but not for first-run
credential prompts.

Known macOS privacy boundary: Remote Login may require Full Disk Access for the
controlling app before `systemsetup -setremotelogin on` can toggle it. `.macos`
tries the systemsetup path, then a launchd SSH fallback, then prints the manual
System Settings step if macOS still blocks it.

Known Remote Login boundary: "Allow full disk access for remote users" is a TCC
authorization controlled by Apple's Sharing settings UI or management profiles,
not a public `systemsetup`/`defaults` flag. Keep it manual unless this Mac is
managed with a deliberate PPPC profile.

Known Raycast boundary: Spotlight's `Cmd+Space` shortcut is disabled
automatically, but Raycast does not expose a stable pre-onboarding preference or
CLI for setting its global hotkey. Set Raycast's hotkey in the app UI.

Known Finder boundary: removing built-in sidebar items like Recents, AirDrop,
Shared, and On My Mac does not currently expose a stable `defaults` setting on
this macOS build. `.macos` records it as a manual verification step instead of
using brittle GUI automation or private shared-file-list mutation.

## macOS Preferences

| Category | What it sets |
|---|---|
| SSH | Remote Login enabled when macOS permissions allow it; otherwise explicit manual step |
| UI | Dark mode, sounds on, natural scrolling, tabs always, restore windows |
| Dock | Auto-hide, size, magnification, managed app layout via dockutil |
| Login Items | Raycast, 1Password, and Tailscale launch at login |
| Siri | Disabled |
| Menu Bar | Spotlight icon hidden, battery percentage, 24h clock with date and seconds |
| Spotlight | Cmd+Space freed for Raycast, limited categories |
| Display | Night Shift off, auto-brightness off, built-in display set to More Space via `displayplacer` |
| Finder | Hidden files, extensions, path bar, column view, folders first; sidebar removals are manual |
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
| Bun | Homebrew `bun` |
| Apple toolchain | Xcode app + Command Line Tools |

## Updating

```bash
cd ~/Workspace/dotfiles && git pull --rebase origin main
brew bundle --file=~/Workspace/dotfiles/Brewfile
./setup.sh --reset
```
