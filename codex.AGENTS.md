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
- Durable Codex settings belong in `~/.codex/config.toml`, managed here by
  `codex.config.toml`.
- Do not commit Codex auth, logs, sessions, cache, generated state, or project
  trust history.
