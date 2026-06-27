# Codex Global Guidance

- Keep this file high signal. Add durable rules only after they have proven useful.
- Read the repo's `AGENTS.md`, `README.md`, and nearby docs before editing.
- Preserve user work. Do not revert unrelated changes or run destructive commands
  unless explicitly asked.
- Use the repo's documented validation commands and report what was verified.
- Dotfiles live at `~/Workspace/dotfiles`; `~/.dotfiles` is a compatibility
  symlink.
- Durable Codex defaults live in `codex.config.toml`. Do not symlink it over
  `~/.codex/config.toml`; merge deliberately so app/plugin state is preserved.
- Never commit Codex auth, sessions, logs, cache, generated state, or project
  trust history.
