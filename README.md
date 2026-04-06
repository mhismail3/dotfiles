# dotfiles

Setup for **mac-server** — an M5 Max MacBook Pro running as an always-on home server, primarily for AI agents, local LLMs (Ollama), Docker services, and remote development.

The MacBook runs with the lid closed, accessed via SSH, RustDesk, or Screen Sharing over Tailscale. When unplugged, it behaves as a normal laptop.

## Quick Start

```bash
# Fresh Mac:
git clone https://github.com/mhismail3/dotfiles.git ~/.dotfiles
cd ~/.dotfiles && git checkout mac-server
./setup.sh

# Re-run safely (skips what's done):
./setup.sh

# Force re-apply everything to match dotfiles:
./setup.sh --reset
```

## Architecture

**Single-script design.** `setup.sh` contains all logic as functions — no separate module files, no `_lib.sh`. The Brewfile and config files live in their own directories.

**Symlink-based.** Config files are symlinked from `~/.dotfiles/` to their expected locations. Editing a file in this repo immediately takes effect — no re-running needed.

**Two modes:**
- `./setup.sh` — idempotent. Safe to run multiple times. Skips completed steps.
- `./setup.sh --reset` — force re-applies everything. Re-creates symlinks, re-runs brew bundle with `--force`, re-applies all macOS preferences. Never destroys SSH keys.

## What's Included

| File | Purpose |
|---|---|
| `setup.sh` | Main bootstrap script (12 steps, interactive) |
| `Brewfile` | All Homebrew packages and casks |
| `zsh/.zshrc` | Shell config (Homebrew, languages, plugins, starship) |
| `zsh/path.zsh` | PATH: GNU tools override BSD, user bins |
| `zsh/aliases.zsh` | Aliases + guardrails (pip warns to use uv, npm warns on -g) |
| `git/.gitconfig` | HTTPS-first auth (via gh), no SSH URL rewriting |
| `git/.gitignore_global` | Global gitignore patterns |
| `tmux/.tmux.conf` | tmux: mouse, `\|`/`-` splits, Alt+arrow nav, 10k scrollback |
| `starship/starship.toml` | Minimal prompt: directory + git branch |
| `ghostty/config` | Ghostty terminal: performance defaults, 50k scrollback |
| `macos/.macos` | macOS system preferences (see below) |
| `claude/` | Claude Code: CLAUDE.md, settings.json, skills/, LEDGER.jsonl |

## Setup Steps (in order)

1. **Xcode CLI Tools** — required for git, compilers
2. **Homebrew** — package manager
3. **Clone dotfiles** — this repo to `~/.dotfiles`
4. **Brew bundle** — install everything from Brewfile
5. **Symlinks** — link config files to home directory
6. **SSH key** — generate ed25519 key for server access
7. **GitHub CLI auth** — `gh auth login` sets up HTTPS git credentials
8. **Shell** — set zsh as default, create ~/Workspace and ~/.local/bin
9. **Language runtimes** — Rust (rustup), Node (nvm LTS), rbenv, uv
10. **Claude Code** — symlink config to ~/.claude/
11. **Ollama** — start as brew service (auto-starts on boot)
12. **macOS preferences** — apply .macos script

## macOS Preferences (.macos)

The `.macos` script automates these System Settings:

| Category | What it sets |
|---|---|
| Computer Name | `mac-server` on all interfaces (Bonjour, SMB, etc.) |
| Remote Access | SSH + Screen Sharing + Remote Management (ARD) |
| Power (AC) | Never sleep, no hibernation, no standby, WoL, TCP keepalive |
| Power (Battery) | Sleep 30min, hibernate mode 3, deep sleep after 15min |
| Lid-Closed | `disablesleep 1` + LaunchDaemon to persist across reboots |
| Auto-restart | On kernel panic |
| Auto-login | For current user (requires FileVault off) |
| UI | Dark mode, no iCloud save default, no quarantine dialog |
| Autocorrect | All disabled (spelling, quotes, dashes, caps, period) |
| Dock | Auto-hide, no delay |
| Siri | Disabled entirely, icon hidden |
| Menu Bar | Spotlight icon hidden, 24h clock with date + seconds |
| Display | Night Shift off, auto-brightness off |
| Finder | Show hidden files, extensions, path bar; column view; folders first |
| Keyboard | Fast repeat (2/15), no press-and-hold, full keyboard nav |
| Spotlight | Only indexes: Apps, System Prefs, Directories, Documents |
| Screen Time | Disabled |
| Privacy | Analytics off, ad tracking off, crash reports off |
| Security | Password required immediately on wake |
| Updates | Auto-download, no auto-install (prevents surprise reboots) |
| Caps Lock | Remapped to Command via LaunchDaemon |

After running, a checklist of **15 manual steps** is printed (FileVault, auto-login, charge limit, Wi-Fi, firewall, etc.).

## Language Environment Philosophy

**System stays clean.** Every language runtime is isolated:
- **Python**: managed by `uv` (project-level venvs). `pip` is aliased to warn you.
- **Node**: managed by `nvm` (per-project versions). `npm -g` warns about pollution.
- **Ruby**: managed by `rbenv`
- **Rust**: managed by `rustup`, installs to `~/.cargo/`
- **Bun**: project-local by default

## Key Design Decisions

- **HTTPS-first git** — `gh auth login` handles credentials. No SSH URL rewriting in .gitconfig. SSH key is still generated for server access, just not forced for git.
- **Git editor set to `true`** — prevents editors from blocking automated git operations (agent-friendly).
- **No Raycast/Obsidian/Things** — server doesn't need productivity GUI apps.
- **No pyenv** — `uv` replaces it entirely for Python version + venv management.
- **Apple native charge limit** — no third-party bclm; use System Settings > Battery > Charging > 80%.
- **`brewdiff` alias** — `brew bundle cleanup` shows drift from Brewfile.

## Updating

Edit files in this repo, commit, push. On the server:

```bash
cd ~/.dotfiles && git pull
```

Symlinked files take effect immediately. For macOS preferences or Brewfile changes:

```bash
# Re-apply macOS prefs:
source ~/.dotfiles/macos/.macos

# Re-sync Brewfile:
brew bundle --file=~/.dotfiles/Brewfile

# Or re-run everything:
./setup.sh --reset
```

## Future Enhancements

Documented at the end of `.macos` output:
- **Monitoring** — ntfy.sh + healthchecks.io heartbeat
- **Backups** — Time Machine to Synology NAS
- **SSH hardening** — disable password auth, limit attempts
- **Scheduled maintenance** — weekly brew/docker cleanup LaunchAgent
- **System audit** — periodic snapshot of installed software, permissions, services
