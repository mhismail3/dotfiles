# dotfiles

Setup for **mac-server** (M5 Max MacBook Pro home server).

## Quick Start

```bash
git clone https://github.com/mhismail3/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./setup.sh
```

## What's Included

| File | Purpose |
|---|---|
| `setup.sh` | Main bootstrap script (interactive) |
| `Brewfile` | Homebrew packages |
| `zsh/.zshrc` | Shell config |
| `zsh/path.zsh` | PATH setup (GNU tools, user bins) |
| `zsh/aliases.zsh` | Shell aliases |
| `git/.gitconfig` | Git config (HTTPS-first) |
| `git/.gitignore_global` | Global gitignore |
| `tmux/.tmux.conf` | tmux config |
| `starship/starship.toml` | Prompt config |
| `macos/.macos` | macOS system preferences |
| `claude/` | Claude Code config (CLAUDE.md, settings, skills, ledger) |

## Updating

Edit files here, commit, push. On the server: `cd ~/.dotfiles && git pull`.

Symlink-based — changes to dotfiles are live immediately.
