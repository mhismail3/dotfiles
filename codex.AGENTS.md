# Codex Global Guidance

## Working Defaults

- Read the repository `AGENTS.md`, `README.md`, and nearby docs before changing code.
- Keep edits scoped to the user request and the conventions already present.
- Prefer `rg` for search and use the repository's existing commands for validation.
- Preserve user changes. Do not revert or overwrite unrelated work.
- Avoid destructive commands unless the user explicitly asks for them.
- Report what changed and what was verified.

## Dotfiles

- This file is global personal guidance for Codex across repositories.
- Repo-specific rules belong in that repo's `AGENTS.md`.
- The dotfiles repo lives at `~/Workspace/dotfiles`; `~/.dotfiles` is a
  compatibility symlink.
- Durable Codex defaults live in `codex.config.toml`. Do not symlink it over the
  live `~/.codex/config.toml` app/plugin state unless doing a deliberate merge.
- Do not commit Codex auth, logs, sessions, cache, generated state, or project
  trust history.
