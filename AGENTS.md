# Agent Notes

This repo is intentionally flat. Keep configuration files at the root unless a
tool requires a nested directory layout.

## Source of Truth

- Repo: `mhismail3/dotfiles`
- Branch: `main`
- Canonical local checkout: `~/Workspace/dotfiles`
- Compatibility symlink: `~/.dotfiles`
- Apply entrypoint: `./setup.sh`
- Symlink map: `CONFIG_LINKS` in `setup.sh`
- Personal Codex skills: `skills/<name>` installed to `~/.codex/skills/<name>`
  by `step_codex_skills` in `setup.sh`
- Function test guard: set `DOTFILES_SKIP_MAIN=true` before sourcing `setup.sh`

## Change Rules

- Prefer editing root config files directly.
- Do not add app-specific folders unless the target path cannot be represented by
  a root file plus a symlink.
- Codex skill packages are an allowed nested-directory exception under `skills/`.
- Keep setup behavior idempotent and safe to re-run.
- Do not run or source `.macos` during validation unless explicitly asked; it
  writes system preferences and restarts Apple services.
- Avoid storing machine noise, credentials, generated logs, or per-agent memory in
  this repo.

## Validation

Run these after changing shell, setup, macOS, or Git config:

```bash
zsh -n setup.sh
zsh -n .zshrc
bash -n .macos
zsh -n .macos
git config --file .gitconfig --list
```

Run this after changing Codex config:

```bash
python3.14 -c 'import pathlib,tomllib; tomllib.loads(pathlib.Path("codex.config.toml").read_text())'
```

Run these after changing the app setup registry or app status script:

```bash
yq e '.' apps.yaml >/dev/null
zsh -n app-status.sh
./app-status.sh summary
```

Run these after changing personal Codex skills:

```bash
python3 -m py_compile skills/things-3/scripts/things.py skills/apple-calendar/scripts/calendar.py
swiftc -parse skills/apple-calendar/scripts/calendar_helper.swift
uvx --with pyyaml python - <<'PY'
import pathlib, yaml
for path in sorted(pathlib.Path("skills").glob("*/agents/openai.yaml")):
    yaml.safe_load(path.read_text())
PY
```
