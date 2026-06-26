# Bootstrap Notes

Real fresh-machine findings that should stay encoded in the setup, not just in
agent memory.

## 2026-06-26 Fresh MacBook Setup

- The canonical checkout lives at `~/Workspace/dotfiles`. Keep `~/.dotfiles` as
  a compatibility symlink because existing shell/config links and older commands
  may still refer to it.
- Homebrew now requires tap trust for external taps. Use core `brew "bun"`
  instead of `oven-sh/bun/bun`.
- Homebrew `rustup-init` is now `rustup`, and it is keg-only. Put
  `$(brew --prefix rustup)/bin` on `PATH` so `rustup`, `rustc`, and `cargo`
  resolve in interactive shells.
- `brew bundle` failures must not be reported as success. `setup.sh` now checks
  the bundle exit status and validates with `brew bundle check`.
- Private Internet Access can leave a quarantined partial app bundle after a
  failed cask install. `setup.sh` now removes the top-level quarantine attribute
  when present and retries `brew install --cask private-internet-access --adopt`.
- Fresh Codex app installs write live plugin, MCP, desktop, and project trust
  state into `~/.codex/config.toml`. Do not symlink over that file blindly;
  keep `codex.config.toml` as a durable baseline to merge deliberately.
- Zsh completion directories may become group-writable during Homebrew setup.
  Fix `go-w` permissions before `compinit`, and do not run `compinit` unless
  stdin/stdout are real terminals.
- macOS may block `systemsetup -setremotelogin on` unless the controlling app
  has Full Disk Access. `.macos` now tries `systemsetup`, then the launchd SSH
  service fallback, then prints an explicit manual step if verification fails.
- The Remote Login "Allow full disk access for remote users" checkbox maps to a
  TCC authorization in Apple's Sharing extension. It did not expose a public
  `systemsetup` or `defaults` flag locally, and direct TCC database access is
  denied without Full Disk Access. Keep it manual unless using a deliberate MDM
  PPPC profile.
- Display scaling is scriptable with `displayplacer`. On the built-in
  3024x1964 Liquid Retina XDR panel, "More Space" maps to
  `res:1800x1169 hz:120 scaling:on`.
- Dock entries should be path-checked before adding them. Missing apps become
  question marks, and Screen Sharing lives at
  `/System/Applications/Utilities/Screen Sharing.app` on this macOS build.
- `dockutil --before/--after` may report success without persisting on this
  macOS build. Prefer rebuilding the Dock from a complete ordered list.
- Finder built-in sidebar item visibility for Recents, AirDrop, Shared, and
  On My Mac did not show a stable `defaults` key or usable shared-file-list
  mutation path on this macOS build. Keep it as a manual verification step
  unless a future, tested API appears.
- Login items for normal apps are scriptable with `System Events`. `.macos`
  adds Raycast, 1Password, and Tailscale after checking that their app bundles
  exist.
- Raycast exposes strings for `raycastGlobalHotkey` and a Spotlight hotkey
  migration command, but a fresh install has no preferences domain and no
  supported CLI for setting the global hotkey before onboarding. Keep
  `Cmd+Space` assignment manual in Raycast settings.
- Full Xcode should be part of this setup because the Dock layout includes it
  and iOS/macOS development needs more than Command Line Tools. Install it with
  Mac App Store id `497799835`, then select
  `/Applications/Xcode.app/Contents/Developer`.
- Keep sudo keepalive loops fully redirected and kill them at the end of setup
  steps. Otherwise they can hold pipes open and make agent-visible logs appear
  hung after the real work is complete.
- Current `/usr/bin/ssh-add` supports `-K`, not always `--apple-use-keychain`.
  Try both and fall back to plain `ssh-add`.
- `gh auth login --git-protocol ssh` does not necessarily upload the SSH key.
  `setup.sh` now verifies raw GitHub SSH and can refresh `admin:public_key`
  scope to upload the public key when needed.
