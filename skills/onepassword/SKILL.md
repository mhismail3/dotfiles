---
name: onepassword
description: Work with 1Password CLI on this Mac for private credential handoff. Use when Codex needs to check 1Password CLI readiness, search item metadata, inspect available login fields without revealing values, or copy/paste usernames/passwords into apps and websites without printing secrets.
---

# 1Password

Use the 1Password desktop app integration as the normal authorization boundary.
Do not add an account with account password, Secret Key, or service account
token unless the user explicitly asks for that different security model.

## Quick Start

```bash
~/.codex/skills/onepassword/scripts/op-safe.py status
~/.codex/skills/onepassword/scripts/op-safe.py signin
~/.codex/skills/onepassword/scripts/op-safe.py search "private internet access"
~/.codex/skills/onepassword/scripts/op-safe.py item "<item id or title>"
~/.codex/skills/onepassword/scripts/op-safe.py paste-field "<item id or title>" username
~/.codex/skills/onepassword/scripts/op-safe.py paste-field "<item id or title>" password
~/.codex/skills/onepassword/scripts/op-safe.py clear-clipboard
```

## Setup Boundary

1Password CLI must be installed with Homebrew cask `1password-cli`.
The desktop app must have app integration enabled:

1. Open 1Password.
2. Enable Touch ID or another system unlock method in Settings > Security.
3. Enable Settings > Developer > Integrate with 1Password CLI.
4. Run `op-safe.py signin` or `op signin` and authenticate through the app.

## Operating Rules

- Prefer `scripts/op-safe.py` for all 1Password work.
- Never print, summarize, log, save, commit, or quote secret field values.
- Use `search` and `item` for item titles, vault names, URLs, field labels, and
  secret-reference availability only. Treat that metadata as private context.
- Use `copy-field`, `paste-field`, `copy-ref`, or `paste-ref` for actual values.
  These commands return only success/failure and clear the clipboard by default.
- Pause for user confirmation instead of accessing OTP/TOTP, recovery codes,
  backup codes, payment-card fields, Secret Keys, or permission grants unless
  the user explicitly requests that exact access.
- After a login handoff, run `clear-clipboard` unless the wrapper already
  cleared it.
- Do not use shell tracing, paste command output into chat, or run commands that
  reveal values such as `op read ...` directly.
- Do not store 1Password session tokens, account IDs, service account tokens,
  item exports, or vault metadata in dotfiles.

## Login Handoff

For an app or browser login:

1. Use `status`, then `signin` if needed.
2. Use `search "<service>"` to identify the item. If multiple results match,
   use item IDs and ask the user only when ambiguity remains.
3. Use `item "<item>"` to see available field labels without values.
4. Focus the target username field with Browser, Chrome, or Computer Use.
5. Run `paste-field "<item>" username`.
6. Focus the password field.
7. Run `paste-field "<item>" password`.
8. Submit only if the user asked for completion and no additional sensitive
   approval, OTP, or payment step is shown.

If automated paste fails because macOS Automation or Accessibility blocks
System Events, use `copy-field` and paste with the active UI tool, then clear
the clipboard.
